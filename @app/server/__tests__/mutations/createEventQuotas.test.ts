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

const createEventQuotasMutation = `
mutation CreateEventQuotas($input: CreateEventQuotasInput!) {
  createEventQuotas(input: $input) {
    quotas {
      id
      eventId
      title
      size
      position
      createdBy
      updatedBy
      createdAt
      updatedAt
    }
  }
}`;

describe("CreateEventQuotas", () => {
  it("can use custom mutation to create multiple quotas", async () => {
    const { events, session } = await createEventDataAndLogin({
      quotaOptions: { create: false },
      registrationOptions: { create: false },
      registrationSecretOptions: { create: false },
    });
    const eventId = events[0].id;

    await runGraphQLQuery(
      createEventQuotasMutation,

      // GraphQL variables:
      {
        input: {
          eventId,
          quotas: [
            {
              position: 0,
              title: { fi: "Testikiintiö 1", en: "Test quota 1" },
              size: 1,
            },
            {
              position: 1,
              title: { fi: "Testikiintiö 2", en: "Test quota 2" },
              size: 2,
            },
          ],
        },
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {
        user: { session_id: session.uuid },
      },

      // This function runs all your test assertions:
      async (json, { pgClient }) => {
        expect(json.errors).toBeFalsy();
        expect(json.data).toBeTruthy();

        const quotas = json.data!.createEventQuotas.quotas;

        expect(quotas).toBeTruthy();
        expect(quotas.length).toEqual(2);
        expect(quotas[0].eventId).toEqual(eventId);
        expect(quotas[1].eventId).toEqual(eventId);

        expect(sanitize(quotas)).toMatchInlineSnapshot(`
          Array [
            Object {
              "createdAt": "[timestamp-1]",
              "createdBy": "[id-3]",
              "eventId": "[id-2]",
              "id": "[id-1]",
              "position": 0,
              "size": 1,
              "title": Object {
                "en": "Test quota 1",
                "fi": "Testikiintiö 1",
              },
              "updatedAt": "[timestamp-1]",
              "updatedBy": "[id-4]",
            },
            Object {
              "createdAt": "[timestamp-1]",
              "createdBy": "[id-3]",
              "eventId": "[id-2]",
              "id": "[id-5]",
              "position": 1,
              "size": 2,
              "title": Object {
                "en": "Test quota 2",
                "fi": "Testikiintiö 2",
              },
              "updatedAt": "[timestamp-1]",
              "updatedBy": "[id-4]",
            },
          ]
        `);

        const { rows } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_public.quotas WHERE event_id = $1`,
            [eventId]
          )
        );

        if (rows.length !== 2) {
          throw new Error("Quotas not found!");
        }
        expect(rows[0].event_id).toEqual(eventId);
        expect(rows[1].event_id).toEqual(eventId);
      }
    );
  });

  it("must specify at least one event quota", async () => {
    const { events, session } = await createEventDataAndLogin({
      quotaOptions: { create: false },
      registrationOptions: { create: false },
      registrationSecretOptions: { create: false },
    });
    const eventId = events[0].id;

    await runGraphQLQuery(
      createEventQuotasMutation,

      // GraphQL variables:
      {
        input: {
          eventId,
          quotas: [],
        },
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {
        user: { session_id: session.uuid },
      },

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;
        expect(message).toEqual("You must specify at least one quota");
        expect(code).toEqual("DNIED");
      }
    );
  });

  it("can't create quotas while logged out", async () => {
    const { events } = await createEventDataAndLogin({
      quotaOptions: { create: false },
      registrationOptions: { create: false },
      registrationSecretOptions: { create: false },
    });
    const eventId = events[0].id;

    await runGraphQLQuery(
      createEventQuotasMutation,

      // GraphQL variables:
      {
        input: {
          eventId,
          quotas: [
            { title: { fi: "Testikiintiö 1", en: "Test quota 1" }, size: 1 },
            { title: { fi: "Testikiintiö 2", en: "Test quota 2" }, size: 2 },
          ],
        },
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        expect(message).toEqual("You must log in to create event quotas");
      }
    );
  });
});
