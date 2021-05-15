/// <reference types="Cypress" />

import dayjs from "dayjs";
import slugify from "slugify";

context("Create event", () => {
  beforeEach(() => cy.serverCommand("clearTestUsers"));
  beforeEach(() => cy.serverCommand("clearTestEventData"));
  beforeEach(() => cy.serverCommand("clearTestOrganizations"));

  it("admin user can create an event", () => {
    // Setup
    cy.serverCommand("createTestEventData", {
      eventSignupUpcoming: true,
      userIsAdmin: true,
    }).as("createEventDataResult");
    cy.login({
      username: "testuser_events",
      password: "DOESNT MATTER",
      existingUser: true,
    });

    // Action
    cy.get("@createEventDataResult").then(() => {
      cy.getCy("layout-dropdown-user").click();
      cy.getCy("layout-link-admin").click();
      cy.url().should("equal", Cypress.env("ROOT_URL") + "/admin");
      cy.getCy("admin-sider-events").click();
      cy.getCy("admin-sider-create-event").click();
      cy.url().should("equal", Cypress.env("ROOT_URL") + "/admin/event/create");

      cy.get(".ant-tabs-tab").as("tabs");

      cy.getCy("eventform-select-language").click();
      // Both languages are selected by default. Click twice to make sure
      // the select works.

      // General tab
      cy.getCy("eventform-select-language-option-en").click();
      cy.getCy("eventform-select-language-option-en").click();
      cy.getCy("eventform-select-language").click();

      cy.getCy("eventform-select-organization-id").click();
      cy.getCy("eventform-select-organization-id-option-0").click();

      cy.getCy("eventform-select-category-id").click();
      cy.getCy("eventform-select-category-id-option-0").click();

      cy.getCy("eventform-input-name-fi").type("Testitapahtuma");
      cy.getCy("eventform-input-name-en").type("Test event");

      cy.getCy("eventform-input-description-fi").type("Testikuvaus");
      cy.getCy("eventform-input-description-en").type("Test description");

      const format = "YYYY-MM-DD HH:MM";
      const today = dayjs();

      cy.getCy("eventform-input-event-time").eq(0).click();
      cy.getCy("eventform-input-event-time").within(() => {
        cy.get("input[id='eventTime']").type(
          today.add(2, "day").format(format),
          {
            force: true,
          }
        );
        cy.get("input")
          .eq(1)
          .click()
          .type(today.add(3, "day").format(format), { force: true });
      });
      cy.get(".ant-picker-footer button").click();

      cy.getCy("eventform-input-registration-time").eq(0).click();
      cy.getCy("eventform-input-registration-time").within(() => {
        cy.get("input[id='registrationTime']").type(
          today.add(-1, "day").format(format),
          {
            force: true,
          }
        );
        cy.get("input")
          .eq(1)
          .click()
          .type(today.add(1, "day").format(format), { force: true });
      });
      cy.get(".ant-picker-footer button").eq(1).click();

      cy.getCy("eventform-switch-highlight").click();
      cy.getCy("eventform-switch-save-as-draft").click();

      cy.getCy("eventform-header-image-upload").attachFile("kitten.jpg");
      cy.get(".antd-img-crop-modal button").contains("OK").click();

      // Quotas tab
      cy.get("@tabs").eq(1).click();
      cy.getCy("eventform-quotas-add-quota").click();
      cy.getCy("eventform-input-quotas-title-fi-0").type("Testikiintiö 1");
      cy.getCy("eventform-input-quotas-title-en-0").type("Test quota 1");
      cy.getCy("eventform-input-quotas-size-0").type("0");

      cy.getCy("eventform-quotas-add-quota").click();
      cy.getCy("eventform-input-quotas-title-fi-1").type("Testikiintiö 2");
      cy.getCy("eventform-input-quotas-title-en-1").type("Test quota 2");
      cy.getCy("eventform-input-quotas-size-1").type("2");

      cy.getCy("eventform-quotas-add-quota").click();
      cy.getCy("eventform-input-quotas-title-fi-2").type("Testikiintiö 3");
      cy.getCy("eventform-input-quotas-title-en-2").type("Test quota 3");
      cy.getCy("eventform-input-quotas-size-2").type("3");

      // Email tab
      cy.get("@tabs").eq(2).click();

      // Back to general tab
      cy.get("@tabs").eq(0).click();

      cy.getCy("eventform-button-submit").click();

      const daySlug = dayjs(today.add(2, "day")).format("YYYY-M-D");
      const slug = slugify(`${daySlug}-testitapahtuma}`, {
        lower: true,
      });

      // Assertion
      cy.url().should("equal", Cypress.env("ROOT_URL") + "/admin/event/list");
      cy.getCy("adminpage-events").should("contain", "Testitapahtuma");
      cy.visit(Cypress.env("ROOT_URL"));
      cy.getCy("homepage-signup-open-events").should(
        "contain",
        "Testitapahtuma"
      );

      cy.getCy(`eventcard-eventpage-link-${slug}`).click();

      cy.url().should("equal", Cypress.env("ROOT_URL") + `/event/${slug}`);

      // Header image should exist and be visible
      cy.getCy("eventpage-header-image").should("be.visible");
      cy.get('img[src$="kitten.jpg"]').should("have.length", 1);

      // Quotas should exist and be ordered correctly
      cy.getCy("eventpage-quotas-card")
        .children()
        .eq(1) // Get the card body
        .children()
        .first()
        .should("contain", "Testikiintiö 1")
        .next()
        .should("contain", "Testikiintiö 2")
        .next()
        .should("contain", "Testikiintiö 3");
    });
  });

  it("redirects to index if user is not admin", () => {
    // Setup
    cy.serverCommand("createTestEventData", {
      eventSignupUpcoming: true,
      eventSignupClosed: false,
    }).as("createEventDataResult");

    // Action
    cy.get("@createEventDataResult").then(() => {
      cy.login({
        verified: true,
      });
      cy.visit(Cypress.env("ROOT_URL") + "/admin/event/create");
    });

    // Assertion
    cy.url().should("equal", Cypress.env("ROOT_URL") + "/");
  });

  it("redirects to index if user is not part of any organization", () => {
    // Setup
    cy.serverCommand("createTestEventData").as("createEventDataResult");
    cy.login({
      verified: true,
      isAdmin: true,
    });

    // Action
    cy.get("@createEventDataResult").then(() => {
      cy.visit(Cypress.env("ROOT_URL") + "/admin/event/create");
    });

    // Assertion
    cy.url().should("equal", Cypress.env("ROOT_URL") + "/");
  });
});
