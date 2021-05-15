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

const updateRegistrationMutation = `
mutation UpdateEventRegistration(
  $updateToken: String!
  $firstName: String!
  $lastName: String!
) {
  updateRegistration(
    input: {
      updateToken: $updateToken
      firstName: $firstName
      lastName: $lastName
    }
  ) {
    registration {
      id
      fullName
    }
  }
}`;

describe("UpdateRegistration", () => {
  it("can update a registration with a valid updateToken", async () => {
    const { registrationSecrets } = await createEventDataAndLogin();
    const { update_token: updateToken } = registrationSecrets[0];

    await runGraphQLQuery(
      updateRegistrationMutation,

      // GraphQL variables:
      {
        updateToken,
        firstName: "Päivi",
        lastName: "Tetty",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {
        user: {},
      },

      // This function runs all your test assertions:
      async (json, { pgClient }) => {
        expect(json.errors).toBeFalsy();
        expect(json.data).toBeTruthy();

        const updatedRegistration = json.data!.updateRegistration.registration;
        expect(updatedRegistration).toBeTruthy();

        expect(sanitize(updatedRegistration)).toMatchInlineSnapshot(`
          Object {
            "fullName": "Päivi Tetty",
            "id": "[id-1]",
          }
        `);

        const { rows } = await asRoot(pgClient, () =>
          pgClient.query(
            `SELECT * FROM app_public.registrations WHERE id = $1`,
            [updatedRegistration.id]
          )
        );

        if (rows.length !== 1) {
          throw new Error("Registration not found!");
        }
        expect(rows[0].id).toEqual(updatedRegistration.id);
        expect(rows[0].first_name).toEqual("Päivi");
        expect(rows[0].last_name).toEqual("Tetty");
      }
    );
  });

  it("can't update registration if registration token is not valid", async () => {
    await runGraphQLQuery(
      updateRegistrationMutation,

      // GraphQL variables:
      {
        // Invalid updateToken
        updateToken: "a7def7b2-1687-48d8-839e-55e57f6ade85",
        firstName: "Päivi",
        lastName: "Tetty",
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
