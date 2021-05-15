import {
  asRoot,
  createEventDataAndLogin,
  deleteTestData,
  runGraphQLQuery,
  setup,
  teardown,
} from "../helpers";

beforeEach(deleteTestData);
beforeAll(setup);
afterAll(teardown);

const deleteEventRegistrationMutation = `
mutation DeleteEventRegistration($updateToken: String!) {
  deleteRegistration(input: { updateToken: $updateToken }) {
    success
  }
}`;

describe("DeleteRegistration", () => {
  it("can delete a registration with a valid updateToken", async () => {
    const { registrationSecrets } = await createEventDataAndLogin();
    const {
      update_token: updateToken,
      registration_id: registrationId,
    } = registrationSecrets[0];

    await runGraphQLQuery(
      deleteEventRegistrationMutation,

      // GraphQL variables:
      { updateToken },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {
        user: {},
      },

      // This function runs all your test assertions:
      async (json, { pgClient }) => {
        expect(json.errors).toBeFalsy();
        expect(json.data).toBeTruthy();

        const { success } = json.data!.deleteRegistration;
        expect(success).toBeTruthy();

        const { rows: registrationRows } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_public.registrations WHERE id = $1`,
            [registrationId]
          )
        );
        const { rows: secretRows } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_private.registration_secrets WHERE registration_id = $1`,
            [registrationId]
          )
        );

        if (registrationRows.length !== 0) {
          throw new Error("Registration not deleted successfully!");
        }
        if (secretRows.length !== 0) {
          throw new Error("Registration secrets not deleted successfully!");
        }

        expect(registrationRows).toEqual([]);
        expect(secretRows).toEqual([]);
      }
    );
  });

  it("can't update registration if registration token is not valid", async () => {
    await runGraphQLQuery(
      deleteEventRegistrationMutation,

      // GraphQL variables:
      {
        // Invalid updateToken
        updateToken: "e22951b1-d9b2-4a3c-a827-5c512b935be2",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        const code = json.errors![0].extensions.exception.code;

        expect(message).toEqual("Registration matching token was not found.");
        expect(code).toEqual("NTFND");
      }
    );
  });
});
