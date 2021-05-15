/// <reference types="Cypress" />

context("Organization page", () => {
  beforeEach(() => cy.serverCommand("clearTestUsers"));
  beforeEach(() => cy.serverCommand("clearTestOrganizations"));

  it("renders for owner", () => {
    // Setup
    cy.login({
      next: "/admin/organization/test-organization",
      verified: true,
      isAdmin: true,
      orgs: [["Test Organization", "test-organization"]],
    });

    // Action

    // Assertions
    cy.url().should(
      "equal",
      Cypress.env("ROOT_URL") + "/admin/organization/test-organization"
    );
  });
});
