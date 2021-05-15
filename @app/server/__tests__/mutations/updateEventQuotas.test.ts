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

const updateEventQuotasMutation = `
mutation UpdateEventQuotas($input: UpdateEventQuotasInput!) {
  updateEventQuotas(input: $input) {
    quotas {
      id
      title
      size
      eventId
      createdBy
      updatedBy
      createdAt
      updatedAt
    }
  }
}`;

describe("UpdateEventQuotas", () => {
  it("can use custom mutation to update multiple quotas", async () => {
    // Create two quotas, update them and add a third with a single mutation
    const { events, session, quotas } = await createEventDataAndLogin({
      quotaOptions: { create: true, amount: 2 },
      registrationOptions: { create: false },
      registrationSecretOptions: { create: false },
    });
    const eventId = events[0].id;

    await runGraphQLQuery(
      updateEventQuotasMutation,

      // GraphQL variables:
      {
        input: {
          eventId,
          quotas: [
            {
              id: quotas[0].id,
              position: 0,
              size: 1,
              title: {
                fi: "Testikiintiö 1",
                en: "Test quota 1",
              },
            },
            {
              id: quotas[1].id,
              position: 1,
              size: 2,
              title: {
                fi: "Testikiintiö 2",
                en: "Test quota 2",
              },
            },
            {
              // Should also be able to create new quotas via this mutation if
              // id is not specified
              position: 2,
              size: 2,
              title: {
                fi: "Testikiintiö 3",
                en: "Test quota 3",
              },
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

        const quotas = json.data!.updateEventQuotas.quotas;

        expect(quotas).toBeTruthy();
        expect(quotas.length).toEqual(3);
        expect(quotas[0].eventId).toEqual(eventId);
        expect(quotas[1].eventId).toEqual(eventId);
        expect(quotas[2].eventId).toEqual(eventId);

        expect(sanitize(quotas)).toMatchInlineSnapshot(`
          Array [
            Object {
              "createdAt": "[timestamp-1]",
              "createdBy": "[id-3]",
              "eventId": "[id-2]",
              "id": "[id-1]",
              "size": 1,
              "title": Object {
                "en": "Test quota 1",
                "fi": "Testikiintiö 1",
              },
              "updatedAt": "[timestamp-2]",
              "updatedBy": "[id-3]",
            },
            Object {
              "createdAt": "[timestamp-1]",
              "createdBy": "[id-3]",
              "eventId": "[id-2]",
              "id": "[id-4]",
              "size": 2,
              "title": Object {
                "en": "Test quota 2",
                "fi": "Testikiintiö 2",
              },
              "updatedAt": "[timestamp-2]",
              "updatedBy": "[id-3]",
            },
            Object {
              "createdAt": "[timestamp-2]",
              "createdBy": "[id-3]",
              "eventId": "[id-2]",
              "id": "[id-5]",
              "size": 2,
              "title": Object {
                "en": "Test quota 3",
                "fi": "Testikiintiö 3",
              },
              "updatedAt": "[timestamp-2]",
              "updatedBy": "[id-6]",
            },
          ]
        `);

        const { rows } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_public.quotas WHERE event_id = $1`,
            [eventId]
          )
        );

        if (rows.length !== 3) {
          throw new Error("Quotas not found!");
        }
        expect(rows[0].event_id).toEqual(eventId);
        expect(rows[1].event_id).toEqual(eventId);
        expect(rows[2].event_id).toEqual(eventId);
      }
    );
  });

  it("can use custom mutation to delete multiple quotas", async () => {
    // Create four quotas and delete three of them with a single mutation
    const { events, session, quotas } = await createEventDataAndLogin({
      quotaOptions: { create: true, amount: 4 },
      registrationOptions: { create: false },
      registrationSecretOptions: { create: false },
    });
    const eventId = events[0].id;

    await runGraphQLQuery(
      updateEventQuotasMutation,

      // GraphQL variables:
      {
        input: {
          eventId,
          quotas: [
            {
              id: quotas[0].id,
              position: 0,
              size: 1,
              title: {
                fi: "Testikiintiö 1",
                en: "Test quota 1",
              },
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

        const quotas = json.data!.updateEventQuotas.quotas;

        expect(quotas).toBeTruthy();
        expect(quotas.length).toEqual(1);
        expect(quotas[0].eventId).toEqual(eventId);

        expect(sanitize(quotas)).toMatchInlineSnapshot(`
          Array [
            Object {
              "createdAt": "[timestamp-1]",
              "createdBy": "[id-3]",
              "eventId": "[id-2]",
              "id": "[id-1]",
              "size": 1,
              "title": Object {
                "en": "Test quota 1",
                "fi": "Testikiintiö 1",
              },
              "updatedAt": "[timestamp-2]",
              "updatedBy": "[id-3]",
            },
          ]
        `);

        const { rows } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_public.quotas WHERE event_id = $1`,
            [eventId]
          )
        );

        if (rows.length !== 1) {
          throw new Error("Quotas not found!");
        }
        expect(rows[0].event_id).toEqual(eventId);
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
      updateEventQuotasMutation,

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

  it("can't update quotas while logged out", async () => {
    const { events, quotas } = await createEventDataAndLogin({
      quotaOptions: { create: true, amount: 1 },
      registrationOptions: { create: false },
      registrationSecretOptions: { create: false },
    });
    const eventId = events[0].id;
    const quotaId = quotas[0].id;

    await runGraphQLQuery(
      updateEventQuotasMutation,

      // GraphQL variables:
      {
        input: {
          eventId,
          quotas: [
            {
              id: quotaId,
              position: 0,
              size: 1,
              title: {
                fi: "Testikiintiö 1",
                en: "Test quota 1",
              },
            },
          ],
        },
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;
        expect(message).toEqual("You must log in to update event quotas");
        expect(code).toEqual("LOGIN");
      }
    );
  });
});
