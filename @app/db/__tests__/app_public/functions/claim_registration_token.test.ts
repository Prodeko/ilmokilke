import { PoolClient } from "pg";

import {
  asRoot,
  assertJobComplete,
  createEventCategories,
  createEvents,
  createOrganizations,
  getJobs,
  runJobs,
  withUserDb,
} from "../../helpers";

async function claimToken(client: PoolClient, eventId: string) {
  const {
    rows: [row],
  } = await client.query(
    `select * from app_public.claim_registration_token($1)`,
    [eventId]
  );
  return row;
}

async function getRegistrationToken(client: PoolClient, token: string) {
  const {
    rows: [row],
  } = await asRoot(client, () =>
    client.query(
      "select * from app_private.registration_secrets where id = $1",
      [token]
    )
  );
  return row;
}

it("can claim registration token and token expires", () =>
  withUserDb(async (client, _user) => {
    // "modern" can be removed in Jest 27, it is opt-in in version 26
    jest.useFakeTimers("modern");

    const [organization] = await createOrganizations(client, 1);
    const [eventCategory] = await createEventCategories(
      client,
      1,
      organization.id
    );
    const [event] = await createEvents(
      client,
      1,
      organization.id,
      eventCategory.id
    );

    // Action
    await claimToken(client, event.id);

    // Assertions
    const { rows: registrationSecrets } = await asRoot(client, () =>
      client.query(
        "select * from app_private.registration_secrets where event_id = $1",
        [event.id]
      )
    );

    expect(registrationSecrets).toHaveLength(1);
    const [registrationSecret] = registrationSecrets;
    expect(registrationSecret.event_id).toEqual(event.id);

    const jobs = await getJobs(
      client,
      "registration__delete_registration_token"
    );
    expect(jobs).toHaveLength(1);
    const [job] = jobs;
    expect(job.payload).toMatchObject({
      token: registrationSecret.registration_token,
    });

    // Assert that the job can run correctly
    // Run the job
    await runJobs(client);
    await assertJobComplete(client, job);

    const THIRTY_MINUTES = 1000 * 30 * 60;

    // Token should exist in the database after creating it
    const t1 = await getRegistrationToken(client, registrationSecret.id);
    expect(t1).toBeTruthy();

    // Token should still be in the database 1ms before expiration
    jest.advanceTimersByTime(THIRTY_MINUTES - 1);
    const t2 = await getRegistrationToken(client, registrationSecret.id);
    expect(t2).toBeTruthy();

    // Token should be deleted from db at expiration
    jest.advanceTimersByTime(1);
    const t3 = await getRegistrationToken(client, registrationSecret.id);
    expect(t3).toBeUndefined();
  }));
