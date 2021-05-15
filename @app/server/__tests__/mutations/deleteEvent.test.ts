import {
  asRoot,
  createEventDataAndLogin,
  createSession,
  createUsers,
  deleteTestData,
  poolFromUrl,
  runGraphQLQuery,
  setup,
  teardown,
  TEST_DATABASE_URL,
} from "../helpers";

beforeEach(deleteTestData);
beforeAll(setup);
afterAll(teardown);

const deleteEventMutation = `
mutation DeleteEvent($eventId: UUID!) {
  deleteEvent(input: { id: $eventId }) {
    clientMutationId
  }
}`;

describe("DeleteEvent", () => {
  it("admin can delete an event", async () => {
    const { events, session } = await createEventDataAndLogin({
      userOptions: { create: true, isAdmin: true },
    });
    const eventId = events[0].id;

    await runGraphQLQuery(
      deleteEventMutation,

      // GraphQL variables:
      { eventId },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {
        user: { session_id: session.uuid },
      },

      // This function runs all your test assertions:
      async (json, { pgClient }) => {
        expect(json.errors).toBeFalsy();
        expect(json.data).toBeTruthy();

        const { rows: eventRows } = await asRoot(pgClient, () =>
          pgClient.query(`SELECT * FROM app_public.events WHERE id = $1`, [
            eventId,
          ])
        );

        if (eventRows.length !== 0) {
          throw new Error("Event not deleted successfully!");
        }

        expect(eventRows).toEqual([]);
      }
    );
  });

  it("users without the right permissions cannot delete events", async () => {
    const { events } = await createEventDataAndLogin({
      userOptions: { create: true, amount: 1, isAdmin: true },
    });
    const eventId = events[0].id;

    const pool = poolFromUrl(TEST_DATABASE_URL);
    const client = await pool.connect();
    const users = await createUsers(
      client,
      1,
      true, // isVerified
      false // isAdmin
    );
    const secondaryUser = users[0];
    const secondarySession = await createSession(client, secondaryUser.id);
    await client.release();

    await runGraphQLQuery(
      deleteEventMutation,

      // GraphQL variables:
      { eventId },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {
        user: { session_id: secondarySession.uuid },
      },

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();
        const message = json.errors![0].message;

        expect(message).toEqual(
          "No values were deleted in collection 'events' because no values you can delete were found matching these criteria."
        );
      }
    );
  });
});
