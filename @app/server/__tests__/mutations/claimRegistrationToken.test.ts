import {
  asRoot,
  createEventDataAndLogin,
  deleteTestData,
  runGraphQLQuery,
  sanitize,
  setup,
  teardown,
} from "../helpers";

beforeEach(deleteTestData);
beforeAll(setup);
afterAll(teardown);

test("ClaimRegistrationToken", async () => {
  const { events, quotas } = await createEventDataAndLogin();
  const eventId = events[0].id;
  const quotaId = quotas[0].id;

  await runGraphQLQuery(
    `mutation ClaimRegistrationToken($eventId: UUID!, $quotaId: UUID!) {
      claimRegistrationToken(input: { eventId: $eventId, quotaId: $quotaId }) {
        claimRegistrationTokenOutput {
          registrationToken
          updateToken
        }
      }
    }`,

    // GraphQL variables:
    {
      eventId,
      quotaId,
    },

    // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
    {},

    // This function runs all your test assertions:
    async (json, { pgClient, redisClient, req }) => {
      expect(json.errors).toBeFalsy();
      expect(json.data).toBeTruthy();

      const registrationSecrets =
        json.data!.claimRegistrationToken.claimRegistrationTokenOutput;
      expect(registrationSecrets).toBeTruthy();

      expect(sanitize(registrationSecrets)).toMatchInlineSnapshot(`
        Object {
          "registrationToken": "[id-1]",
          "updateToken": "[id-2]",
        }
      `);

      const { registrationToken } = registrationSecrets;
      const { rows: secretRows } = await asRoot(pgClient, () =>
        pgClient.query(
          `SELECT * FROM app_private.registration_secrets WHERE registration_token = $1`,
          [registrationToken]
        )
      );

      if (secretRows.length !== 1) {
        throw new Error("Token not found!");
      }
      // Database should contain new row in registration_secret
      expect(secretRows[0].registration_token).toEqual(registrationToken);

      const registrationId = secretRows[0].registration_id;

      const { rows: registrationRows } = await asRoot(pgClient, () =>
        pgClient.query(`SELECT * FROM app_public.registrations WHERE id = $1`, [
          registrationId,
        ])
      );

      if (registrationRows.length !== 1) {
        throw new Error("Registration not found!");
      }
      // Database should contain new row in registrations
      expect(registrationRows[0].event_id).toEqual(eventId);
      expect(registrationRows[0].quota_id).toEqual(quotaId);
      expect(registrationRows[0].first_name).toBeNull();
      expect(registrationRows[0].last_name).toBeNull();
      expect(registrationRows[0].email).toBeNull();

      const rateLimitId = `${eventId}:${quotaId}`;
      const redisKey = `rate-limit:claimRegistrationToken:${rateLimitId}:${req.ip}`;
      const value = await redisClient.get(redisKey);

      // Redis should contain rate limit value after calling
      // claimRegistrationToken mutation
      expect(value).toEqual("1");
    }
  );
});
