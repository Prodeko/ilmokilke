import dayjs from "dayjs";

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

describe("UpdateEvent", () => {
  it("can update an existing event", async () => {
    const {
      events,
      organization,
      eventCategory,
      session,
    } = await createEventDataAndLogin();
    const event = events[0];

    const day = dayjs("2021-02-20T12:00:00+02:00");

    await runGraphQLQuery(
      `mutation UpdateEvent(
        $eventId: UUID!
        $name: JSON!
        $description: JSON!
        $ownerOrganizationId: UUID!
        $categoryId: UUID!
        $isHighlighted: Boolean
        $isDraft: Boolean
        $eventStartTime: Datetime!
        $eventEndTime: Datetime!
        $registrationStartTime: Datetime!
        $registrationEndTime: Datetime!
      ) {
        updateEvent(
          input: {
            id: $eventId
            patch: {
              name: $name
              description: $description
              ownerOrganizationId: $ownerOrganizationId
              categoryId: $categoryId
              isHighlighted: $isHighlighted
              isDraft: $isDraft
              eventStartTime: $eventStartTime
              eventEndTime: $eventEndTime
              registrationStartTime: $registrationStartTime
              registrationEndTime: $registrationEndTime
            }
          }
        ) {
          event {
            id
            name
            description
            ownerOrganizationId
            categoryId
            isHighlighted
            isDraft
            eventStartTime
            eventEndTime
            registrationStartTime
            registrationEndTime
            createdBy
            updatedBy
            createdAt
            updatedAt
          }
        }
      }`,

      // GraphQL variables:
      {
        eventId: event.id,
        slug: event.slug,
        name: { fi: "Päivitetty testitapahtuma", en: "Updated test event" },
        description: {
          fi: "Päivitetty testikuvaus",
          en: "Updated test description",
        },
        ownerOrganizationId: organization.id,
        categoryId: eventCategory.id,
        isHighlighted: true,
        isDraft: false,
        eventStartTime: day.add(2, "hour").toISOString(),
        eventEndTime: day.add(3, "hour").toISOString(),
        registrationStartTime: day.toISOString(),
        registrationEndTime: day.add(1, "hour").toISOString(),
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {
        user: { session_id: session.uuid },
      },

      // This function runs all your test assertions:
      async (json, { pgClient }) => {
        expect(json.errors).toBeFalsy();
        expect(json.data).toBeTruthy();

        const updatedEvent = json.data!.updateEvent.event;

        expect(updatedEvent).toBeTruthy();
        expect(updatedEvent.ownerOrganizationId).toEqual(organization.id);

        expect(sanitize(updatedEvent)).toMatchInlineSnapshot(`
          Object {
            "categoryId": "[id-3]",
            "createdAt": "[timestamp-5]",
            "createdBy": "[id-4]",
            "description": Object {
              "en": "Updated test description",
              "fi": "Päivitetty testikuvaus",
            },
            "eventEndTime": "[timestamp-2]",
            "eventStartTime": "[timestamp-1]",
            "id": "[id-1]",
            "isDraft": false,
            "isHighlighted": true,
            "name": Object {
              "en": "Updated test event",
              "fi": "Päivitetty testitapahtuma",
            },
            "ownerOrganizationId": "[id-2]",
            "registrationEndTime": "[timestamp-4]",
            "registrationStartTime": "[timestamp-3]",
            "updatedAt": "[timestamp-6]",
            "updatedBy": "[id-4]",
          }
        `);

        const { rows } = await asRoot(pgClient, () =>
          pgClient.query(`SELECT * FROM app_public.events WHERE id = $1`, [
            updatedEvent.id,
          ])
        );

        if (rows.length !== 1) {
          throw new Error("Event not found!");
        }
        expect(rows[0].id).toEqual(updatedEvent.id);
      }
    );
  });

  it("can't update an event while logged out (RLS policy)", async () => {
    const { events } = await createEventDataAndLogin({
      registrationOptions: { create: false },
    });
    const eventId = events[0].id;

    await runGraphQLQuery(
      `mutation UpdateEvent(
        $eventId: UUID!
        $description: JSON!
      ) {
        updateEvent(
          input: {
            id: $eventId
            patch: {
              description: $description
            }
          }
        ) {
          event {
            id
          }
        }
      }`,

      // GraphQL variables:
      {
        eventId,
        description: "Test",
      },

      // Additional props to add to `req` (e.g. `user: {session_id: '...'}`)
      {},

      // This function runs all your test assertions:
      async (json) => {
        expect(json.errors).toBeTruthy();

        const message = json.errors![0].message;
        expect(message).toEqual(
          "No values were updated in collection 'events' because no values you can update were found matching these criteria."
        );
      }
    );
  });
});
