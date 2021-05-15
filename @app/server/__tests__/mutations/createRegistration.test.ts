import {
  asRoot,
  assertJobComplete,
  createEventDataAndLogin,
  deleteTestData,
  getJobs,
  runGraphQLQuery,
  runJobs,
  sanitize,
  setup,
  teardown,
} from "../helpers";

beforeEach(deleteTestData);
beforeAll(setup);
afterAll(teardown);

const createRegistrationMutation = `
mutation CreateRegistration(
  $registrationToken: String!
  $eventId: UUID!
  $quotaId: UUID!
  $firstName: String!
  $lastName: String!
  $email: String!
) {
  createRegistration(
    input: {
      registrationToken: $registrationToken
      eventId: $eventId
      quotaId: $quotaId
      firstName: $firstName
      lastName: $lastName
      email: $email
    }
  ) {
    registration {
      id
      firstName
      lastName
      eventId
      quotaId
    }
  }
}`;

describe("CreateRegistration", () => {
  // A bit of background about the overall event registration setup. In order
  // to register to an event the user first has to call a ClaimRegistrationToken
  // mutation. This mutation provides the user with a registration token that
  // must be passed to the CreateRegistration mutation. A row is inserted into
  // app_public.registrations already when calling ClaimRegistrationToken. This
  // same row (identified by registration_token) is then updated with user info
  // when the user calls the CreateRegistration mutation. We also have a server
  // plugin called EventRegistrationPlugin that wraps the CreateRegistration
  // mutation. This plugin is reponsible for dispatching a graphile-worker event
  // that deletes the rate limit key from redis after successful registration.
  //
  // This setup is designed to prevent people from claiming registration
  // tokens by calling the API and then distributing registration tokens
  // to their friends. By rate limiting the claimRegistrationToken
  // endpoint we prevent this. After the registration is complete the rate
  // limit key should be removed from redis. This enables multiple people to
  // use the same computer for registering to an event.

  it("can create registration", async () => {
    const { events, quotas } = await createEventDataAndLogin({
      registrationOptions: { create: false },
    });
    const eventId = events[0].id;
    const quotaId = quotas[0].id;

    const rateLimitId = `${eventId}:${quotaId}`;
    const key = `rate-limit:claimRegistrationToken:${rateLimitId}:127.1.1.1`;

    // In order to test the createRegistration mutation, we first need to run
    // claimRegistrationToken which creates a dummy registration.
    const result = await runGraphQLQuery(
      `mutation ClaimRegistrationToken($eventId: UUID!, $quotaId: UUID!) {
        claimRegistrationToken(input: { eventId: $eventId, quotaId: $quotaId }) {
          claimRegistrationTokenOutput {
            registrationToken
            updateToken
          }
        }
      }`,
      {
        eventId,
        quotaId,
      },
      {},
      async (_json, { redisClient }) => {
        const value = await redisClient.get(key);
        // Redis should contain rate limit value after calling
        // claimRegistrationToken mutation
        expect(value).toEqual("1");
      },
      // Don't rollback in order to use the result of this mutation
      false
    );
    const {
      registrationToken,
    } = result.data.claimRegistrationToken.claimRegistrationTokenOutput;

    await runGraphQLQuery(
      createRegistrationMutation,

      // GraphQL variables:
      {
        eventId,
        quotaId,
        registrationToken,
        firstName: "Testname",
        lastName: "Testlastname",
        email: "testuser@example.com",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json, { pgClient, redisClient, req }) => {
        expect(json.errors).toBeFalsy();
        expect(json.data).toBeTruthy();

        const registration = json.data!.createRegistration.registration;

        expect(registration).toBeTruthy();
        expect(registration.eventId).toEqual(eventId);
        expect(registration.quotaId).toEqual(quotaId);

        expect(sanitize(registration)).toMatchInlineSnapshot(`
          Object {
            "eventId": "[id-3]",
            "firstName": "Testname",
            "id": "[id-2]",
            "lastName": "Testlastname",
            "quotaId": "[id-4]",
          }
        `);

        // Registration should exist in the database
        const { rows: registrations } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_public.registrations WHERE id = $1`,
            [registration.id]
          )
        );
        if (registrations.length !== 1) {
          throw new Error("Registration not found!");
        }
        expect(registrations[0].id).toEqual(registration.id);

        // Registration secrets table should be updated with the registration_id
        const { rows: registrationSecrets } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_private.registration_secrets WHERE registration_id = $1`,
            [registration.id]
          )
        );

        if (registrationSecrets.length !== 1) {
          throw new Error("Registration secret not found!");
        }
        expect(registrationSecrets[0].registration_id).toEqual(registration.id);
        expect(registrationSecrets[0].registration_token).toEqual(null);

        const rateLimitjobs = await getJobs(
          pgClient,
          "registration_complete__delete_rate_limit_key"
        );

        expect(rateLimitjobs).toHaveLength(1);
        const [rateLimitJob] = rateLimitjobs;
        expect(rateLimitJob.payload).toMatchObject({
          eventId: eventId,
          ipAddress: req.ip,
        });

        const confirmationEmailJobs = await getJobs(
          pgClient,
          "registration__send_confirmation_email"
        );

        expect(confirmationEmailJobs).toHaveLength(1);
        const [confirmationEmailJob] = confirmationEmailJobs;
        expect(confirmationEmailJob.payload).toMatchObject({
          id: registration.id,
        });

        // Escape transaction set by runGraphQLQuery.
        //
        // When inside a transaction, SQL date functions return values based on
        // the __start time of the current transaction__. This is a problem since
        // graphile-worker only executes a task if its run_at property is less than
        // now(). Our helper function runGraphQLQuery sets up a transaction by calling
        // withPostGraphileContext. Next we run the CreateRegistration mutation that
        // we are testing. The mutation goes through EventRegistrationPlugin which schedules
        // a task called `registration_complete__delete_rate_limit_key`. Next we call
        // `runJobs` that executes a graphile-worker function called `runTaskListOnce`.
        // This function calls a graphile-worker database function called graphile_worker.get_job
        // which only returns a task to run if run_at <= now(). As explained earlier, we are
        // inside a transaction and calls to now() return the timestamp of when the
        // transaction was created (which is before the mutation is run). Thus
        // run_at >= now() and the task is not executed if we don't end the transaction here.
        await pgClient.query("commit");

        // Run the jobs and assert that the jobs run correctly
        await runJobs(pgClient);
        await assertJobComplete(pgClient, rateLimitJob);
        await assertJobComplete(pgClient, confirmationEmailJob);

        // Redis should not contain a rate limiting key after
        // successful registration
        const value = await redisClient.get(key);
        expect(value).toEqual(null);

        // TODO: Figure out a way to test gdpr__delete_event_registrations
        // graphile worker cron task.
      }
    );
  });

  it("can't create registration if registration token is not valid", async () => {
    const { events, quotas } = await createEventDataAndLogin({
      registrationOptions: { create: false },
    });
    // RegistrationSecret is claimed for event[0], try to use it to
    // register to another event which should not be allowed
    const event = events[0];
    const quota = quotas[0];

    await runGraphQLQuery(
      createRegistrationMutation,

      // GraphQL variables:
      {
        eventId: event.id,
        quotaId: quota.id,
        firstName: "Testname",
        lastName: "Testlastname",
        email: "testuser@example.com",
        // Invalid token
        registrationToken: "540f7d0f-7433-4657-bd98-3b405f913a15",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;
        expect(message).toEqual(
          "Registration token was not valid. Please reload the page."
        );
        expect(code).toEqual("DNIED");
      }
    );
  });

  it("can't create registration if quotaId is invalid", async () => {
    const { events, registrationSecrets } = await createEventDataAndLogin({
      registrationOptions: { create: false },
    });
    const eventId = events[0].id;
    const registrationToken = registrationSecrets[0].registration_token;

    await runGraphQLQuery(
      createRegistrationMutation,

      // GraphQL variables:
      {
        eventId,
        quotaId: "d24a4112-81e2-440a-a9fa-be2371944310",
        registrationToken,
        firstName: "Testname",
        lastName: "Testlastname",
        email: "testuser@example.com",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;
        expect(message).toEqual("Quota not found.");
        expect(code).toEqual("NTFND");
      }
    );
  });

  it("can't create registration if eventId is invalid", async () => {
    const { quotas, registrationSecrets } = await createEventDataAndLogin({
      registrationOptions: { create: false },
    });
    const quotaId = quotas[0].id;
    const registrationToken = registrationSecrets[0].registration_token;

    await runGraphQLQuery(
      createRegistrationMutation,

      // GraphQL variables:
      {
        eventId: "d24a4112-81e2-440a-a9fa-be2371944310",
        quotaId,
        firstName: "Testname",
        lastName: "Testlastname",
        email: "testuser@example.com",
        registrationToken,
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;
        expect(message).toEqual("Event not found.");
        expect(code).toEqual("NTFND");
      }
    );
  });

  it("can't create registration if registration is not open", async () => {
    const {
      quotas,
      events,
      registrationSecrets,
    } = await createEventDataAndLogin({
      registrationOptions: { create: false },
      eventOptions: { create: true, amount: 1, signupOpen: false },
    });
    const eventId = events[0].id;
    const quotaId = quotas[0].id;
    const registrationToken = registrationSecrets[0].registration_token;

    await runGraphQLQuery(
      createRegistrationMutation,

      // GraphQL variables:
      {
        eventId,
        quotaId,
        registrationToken,
        firstName: "Testname",
        lastName: "Testlastname",
        email: "testuser@example.com",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;
        expect(message).toEqual("Event registration is not open.");
        expect(code).toEqual("DNIED");
      }
    );
  });

  it("can't create registration if registration token is for another event", async () => {
    const {
      events,
      quotas,
      registrationSecrets,
    } = await createEventDataAndLogin({
      registrationOptions: { create: false },
      eventOptions: { create: true, amount: 2, signupOpen: true },
    });
    // RegistrationSecret is claimed for event[0], try to use it to
    // register to another event which is not allowed
    const eventId = events[1].id;
    const quotaId = quotas[0].id;
    const registrationToken = registrationSecrets[0].registration_token;

    await runGraphQLQuery(
      createRegistrationMutation,

      // GraphQL variables:
      {
        // Registration token is not valid for this event
        eventId,
        quotaId,
        registrationToken,
        firstName: "Testname",
        lastName: "Testlastname",
        email: "testuser@example.com",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;
        expect(message).toEqual(
          "Registration token was not valid. Please reload the page."
        );
        expect(code).toEqual("DNIED");
      }
    );
  });
});
