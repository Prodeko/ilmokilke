/// <reference types="Cypress" />

context("Create organizations", () => {
  beforeEach(() => cy.serverCommand("clearTestUsers"));
  beforeEach(() => cy.serverCommand("clearTestOrganizations"));

  it("can create an organization", () => {
    // Setup
    cy.login({ verified: true, isAdmin: true });

    // Action
    cy.getCy("layout-dropdown-user").click();
    cy.getCy("layout-link-admin").click();
    cy.url().should("equal", Cypress.env("ROOT_URL") + "/admin");
    cy.getCy("admin-sider-organizations").click();
    cy.getCy("admin-sider-create-organization").click();
    cy.url().should(
      "equal",
      Cypress.env("ROOT_URL") + "/admin/organization/create"
    );
    cy.getCy("createorganization-input-name").type("Test Organization");
    cy.getCy("createorganization-slug-value").contains("test-organization");
    cy.getCy("createorganization-button-create").click();

    // Assertion
    cy.url().should(
      "equal",
      Cypress.env("ROOT_URL") + "/admin/organization/test-organization"
    );
  });

  it("handles conflicting organization name", () => {
    // Setup
    cy.login({
      verified: true,
      isAdmin: true,
      orgs: [["Test Organization", "test-organization"]],
    });

    // Action
    cy.getCy("layout-dropdown-user").click();
    cy.getCy("layout-link-admin").click();
    cy.url().should("equal", Cypress.env("ROOT_URL") + "/admin");
    cy.getCy("admin-sider-organizations").click();
    cy.getCy("admin-sider-create-organization").click();
    cy.url().should(
      "equal",
      Cypress.env("ROOT_URL") + "/admin/organization/create"
    );
    cy.getCy("createorganization-input-name").type("Test Organization");
    cy.getCy("createorganization-slug-value").contains("test-organization");

    // Assertion
    cy.getCy("createorganization-hint-nameinuse").should("exist");
    cy.getCy("createorganization-button-create").click();
    cy.getCy("createorganization-alert-nuniq").should("exist");
  });
});
