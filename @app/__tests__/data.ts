import dayjs from "dayjs";
import * as faker from "faker";
import { PoolClient } from "pg";
import slugify from "slugify";

export type User = {
  id: string;
  username: string;
  _email: string;
  _password: string;
};

let userCreationCounter = 0;
if (process.env.IN_TESTS) {
  // Enables multiple calls to `createUsers` within the same test to still have
  // deterministic results without conflicts.
  beforeEach(() => {
    userCreationCounter = 0;
  });
}

/**
 * The utility functions below are used to prepopulate the database with objects
 * that might be needed by other tests or scripts.
 */

export const createUsers = async (
  client: PoolClient,
  count: number = 1,
  verified: boolean = true,
  isAdmin: boolean = false
) => {
  const users = [];
  if (userCreationCounter > 25) {
    throw new Error("Too many users created!");
  }
  for (let i = 0; i < count; i++) {
    const userLetter = "abcdefghijklmnopqrstuvwxyz"[userCreationCounter];
    userCreationCounter++;
    const password = userLetter.repeat(12);
    const email = `${userLetter}${i || ""}@b.c`;
    const user = (
      await client.query(
        `select * from app_private.really_create_user(
        username := $1,
        email := $2,
        name := $3,
        avatar_url := $4,
        password := $5,
        email_is_verified := $6,
        is_admin := $7
      )`,
        [
          `testuser_${userLetter}`,
          email,
          `User ${userLetter}`,
          null,
          password,
          verified,
          isAdmin,
        ]
      )
    ).rows[0];
    user._email = email;
    user._password = password;
    users.push(user);
  }
  return users;
};

/******************************************************************************/
// Organizations

export const createOrganizations = async (
  client: PoolClient,
  count: number = 1
) => {
  const organizations = [];
  for (let i = 0; i < count; i++) {
    const random = faker.lorem.word();
    const slug = `organization-${random}`;
    const name = `Organization ${random}`;
    const {
      rows: [organization],
    } = await client.query(
      `select * from app_public.create_organization($1, $2)`,
      [slug, name]
    );
    organizations.push(organization);
  }

  return organizations;
};

/******************************************************************************/
// Sessions

export const createSession = async (
  client: PoolClient,
  userId: string
): Promise<{ uuid: string }> => {
  const {
    rows: [session],
  } = await client.query(
    `insert into app_private.sessions(user_id)
      values ($1::uuid)
      returning *
    `,
    [userId]
  );
  return session;
};

/******************************************************************************/
// Events

export const createEventCategories = async (
  client: PoolClient,
  count: number = 1,
  organizationId: string
) => {
  const categories = [];
  for (let i = 0; i < count; i++) {
    const name = { fi: `Kategoria ${i}`, en: `Category ${i}` };
    const description = {
      fi: faker.lorem.paragraph(),
      en: faker.lorem.paragraph(),
    };
    const {
      rows: [category],
    } = await client.query(
      `insert into app_public.event_categories(name, description, owner_organization_id)
        values ($1, $2, $3)
        returning *
      `,
      [name, description, organizationId]
    );
    categories.push(category);
  }

  return categories;
};

export const createEvents = async (
  client: PoolClient,
  count: number = 1,
  organizationId: string,
  categoryId: string,
  signupOpen: boolean = true
) => {
  const events = [];
  for (let i = 0; i < count; i++) {
    const name = {
      fi: `Tapahtuma ${faker.lorem.words()} ${i}`,
      en: `Event ${faker.lorem.words()} ${i}`,
    };
    const description = {
      fi: faker.lorem.paragraph(),
      en: faker.lorem.paragraph(),
    };

    const now = new Date();
    const dayAdjustment = signupOpen ? -1 : 1;
    const registrationStartTime = dayjs(now).add(dayAdjustment, "day").toDate();
    const registrationEndTime = faker.date.between(
      dayjs(registrationStartTime).add(1, "day").toDate(),
      dayjs(registrationStartTime).add(7, "day").toDate()
    );

    const eventStartTime = faker.date.between(
      registrationEndTime,
      dayjs(registrationEndTime).add(7, "day").toDate()
    );
    const eventEndTime = faker.date.between(
      eventStartTime,
      dayjs(eventStartTime).add(1, "day").toDate()
    );

    const eventCategoryId = categoryId;
    const headerImageFile = faker.image.imageUrl(
      851,
      315,
      `nature?random=${Math.round(Math.random() * 1000)}`
    );

    const daySlug = dayjs(eventStartTime).format("YYYY-M-D");
    const slug = slugify(`${daySlug}-${name["fi"]}`, {
      lower: true,
    });
    const isDraft = false;

    const {
      rows: [event],
    } = await client.query(
      `insert into app_public.events(
        name,
        slug,
        description,
        event_start_time,
        event_end_time,
        registration_start_time,
        registration_end_time,
        is_draft,
        header_image_file,
        owner_organization_id,
        category_id
      )
      values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      returning *
      `,
      [
        name,
        slug,
        description,
        eventStartTime,
        eventEndTime,
        registrationStartTime,
        registrationEndTime,
        isDraft,
        headerImageFile,
        organizationId,
        eventCategoryId,
      ]
    );
    events.push(event);
  }

  return events;
};

/******************************************************************************/
// Quotas

export const createQuotas = async (
  client: PoolClient,
  count: number = 1,
  eventId: string
) => {
  const quotas = [];
  for (let i = 0; i < count; i++) {
    const title = { fi: `Kiintiö ${i}`, en: `Quota ${i}` };
    const size = faker.datatype.number({
      min: 1,
      max: 20,
    });
    const {
      rows: [quota],
    } = await client.query(
      `insert into app_public.quotas(event_id, position, title, size)
        values ($1, $2, $3, $4)
        returning *
      `,
      [eventId, i, title, size]
    );
    quotas.push(quota);
  }

  return quotas;
};

/******************************************************************************/
// Registration secrets

export const createRegistrationSecrets = async (
  client: PoolClient,
  count: number = 1,
  registrationId: string,
  eventId: string,
  quotaId: string
) => {
  const registrationSecrets = [];
  for (let i = 0; i < count; i++) {
    const {
      rows: [secret],
    } = await client.query(
      `insert into app_private.registration_secrets(event_id, quota_id, registration_id)
        values ($1, $2, $3)
        returning *
      `,
      [eventId, quotaId, registrationId]
    );
    registrationSecrets.push(secret);
  }

  return registrationSecrets;
};

/******************************************************************************/
// Registrations

export const createRegistrations = async (
  client: PoolClient,
  count: number = 1,
  eventId: string,
  quotaId: string
) => {
  const registrations = [];
  for (let i = 0; i < count; i++) {
    const firstName = faker.name.firstName();
    const lastName = faker.name.lastName();
    const email = faker.internet.email();
    const {
      rows: [registration],
    } = await client.query(
      `insert into app_public.registrations(event_id, quota_id, first_name, last_name, email)
        values ($1, $2, $3, $4, $5)
        returning *
      `,
      [eventId, quotaId, firstName, lastName, email]
    );
    registrations.push(registration);
  }

  return registrations;
};
