import { IncomingMessage, ServerResponse } from "http";

import { makeWorkerUtils, WorkerUtils } from "graphile-worker";
import { ExecutionResult, graphql, GraphQLSchema } from "graphql";
import Redis from "ioredis";
import { Pool, PoolClient } from "pg";
import {
  createPostGraphileSchema,
  PostGraphileOptions,
  withPostGraphileContext,
} from "postgraphile";

import {
  createEventCategories,
  createEvents,
  createOrganizations,
  createQuotas,
  createRegistrations,
  createRegistrationSecrets,
  createSession,
  createUsers,
  poolFromUrl,
  TEST_DATABASE_URL,
} from "../../__tests__/helpers";
import { getPostGraphileOptions } from "../src/middleware/installPostGraphile";

export * from "../../__tests__/helpers";

const MockReq = require("mock-req");

export async function createUserAndLogIn() {
  const pool = poolFromUrl(TEST_DATABASE_URL!);
  const client = await pool.connect();
  try {
    const [user] = await createUsers(client, 1, true);
    const session = await createSession(client, user.id);

    return { user, session };
  } finally {
    await client.release();
  }
}

interface CreateEventDataAndLogin {
  userOptions?: {
    create: boolean;
    amount?: number;
    isVerified?: boolean;
    isAdmin?: boolean;
  };
  eventOptions?: {
    create: boolean;
    amount?: number;
    signupOpen?: boolean;
  };
  quotaOptions?: { create: boolean; amount?: number };
  registrationOptions?: { create: boolean; amount?: number };
  registrationSecretOptions?: { create: boolean; amount?: number };
}

export async function createEventDataAndLogin(args?: CreateEventDataAndLogin) {
  const {
    userOptions = {
      create: true,
      amount: 1,
      isVerified: false,
      isAdmin: false,
    },
    eventOptions = { create: true, amount: 1, signupOpen: true },
    quotaOptions = { create: true, amount: 1 },
    registrationOptions = { create: true, amount: 1 },
    registrationSecretOptions = { create: true, amount: 1 },
  } = args || {};
  const pool = poolFromUrl(TEST_DATABASE_URL);
  const client = await pool.connect();
  try {
    // Have to begin a transaction here, since we set the third parameter
    // of set_config to 'true' in becomeUser below
    client.query("BEGIN");
    let users;
    if (userOptions.create) {
      users = await createUsers(
        client,
        userOptions.amount,
        userOptions.isVerified,
        userOptions.isAdmin
      );
    }
    const primaryUser = users[0];

    // Use the first user as the one to create the session for. We can
    // then use the other user to test for example RLS policies
    const session = await createSession(client, primaryUser.id);

    await becomeUser(client, session.uuid);

    const [organization] = await createOrganizations(client, 1);
    const [eventCategory] = await createEventCategories(
      client,
      1,
      organization.id
    );

    let events;
    if (eventOptions.create) {
      events = await createEvents(
        client,
        eventOptions.amount,
        organization.id,
        eventCategory.id,
        eventOptions.signupOpen
      );
    }

    // Become root to bypass RLS policy on app_private.registration_secrets
    // and app_public.quotas
    client.query("reset role");

    // An existing quota should not exist for createQuotas.test.ts but
    // other tests such as createRegistration.test.ts need an existing
    // quota.
    let quotas;
    if (quotaOptions.create) {
      quotas = await createQuotas(client, quotaOptions.amount, events[0].id);
    }

    // We need an existing registration for updateRegistration.test.ts but
    // don't want to create a registration for createRegistration.test.ts
    // since that would create another registration__send_confirmation_email
    // task.
    let registrations;
    if (registrationOptions.create) {
      registrations = await createRegistrations(
        client,
        registrationOptions.amount,
        events[0].id,
        quotas[0].id
      );
    }

    let registrationSecrets;
    if (registrationSecretOptions.create) {
      registrationSecrets = await createRegistrationSecrets(
        client,
        1,
        registrations ? registrations[0].id : null,
        events[0].id,
        quotas[0].id
      );
    }

    client.query("COMMIT");
    return {
      users,
      session,
      organization,
      eventCategory,
      events,
      quotas,
      registrationSecrets,
      registrations,
    };
  } finally {
    await client.release();
  }
}

export const becomeUser = async (
  client: PoolClient,
  sessionId: string | null
) => {
  await client.query(
    `select set_config('role', $1::text, true), set_config('jwt.claims.session_id', $2::text, true)`,
    [process.env.DATABASE_VISITOR, sessionId]
  );
};

let known: Record<
  string,
  { counter: number; values: Map<unknown, string> }
> = {};

beforeEach(() => {
  known = {};
});

/*
 * This function replaces values that are expected to change with static
 * placeholders so that our snapshot testing doesn't throw an error
 * every time we run the tests because time has ticked on in it's inevitable
 * march toward the future.
 */
export function sanitize(json: any): any {
  /* This allows us to maintain stable references whilst dealing with variable values */
  function mask(value: unknown, type: string) {
    if (!known[type]) {
      known[type] = { counter: 0, values: new Map() };
    }
    const o = known[type];
    if (!o.values.has(value)) {
      o.values.set(value, `[${type}-${++o.counter}]`);
    }
    return o.values.get(value);
  }

  if (Array.isArray(json)) {
    return json.map((val) => sanitize(val));
  } else if (json && typeof json === "object") {
    const result = { ...json };
    for (const k in result) {
      if (k === "nodeId" && typeof result[k] === "string") {
        result[k] = mask(result[k], "nodeId");
      } else if (
        k === "id" ||
        k === "uuid" ||
        (k.endsWith("Id") &&
          (typeof json[k] === "number" || typeof json[k] === "string")) ||
        (k.endsWith("Uuid") && typeof k === "string") ||
        k.endsWith("Token") ||
        k.endsWith("By")
      ) {
        result[k] = mask(result[k], "id");
      } else if (
        (k.endsWith("At") || k.endsWith("Time") || k === "datetime") &&
        typeof json[k] === "string"
      ) {
        result[k] = mask(result[k], "timestamp");
      } else if (
        k.match(/^deleted[A-Za-z0-9]+Id$/) &&
        typeof json[k] === "string"
      ) {
        result[k] = mask(result[k], "nodeId");
      } else if (k === "email" && typeof json[k] === "string") {
        result[k] = mask(result[k], "email");
      } else if (k === "username" && typeof json[k] === "string") {
        result[k] = mask(result[k], "username");
      } else {
        result[k] = sanitize(json[k]);
      }
    }
    return result;
  } else {
    return json;
  }
}

// Contains the PostGraphile schema and rootPgPool
interface ICtx {
  rootPgPool: Pool;
  redisClient: Redis.Redis;
  workerUtils: WorkerUtils;
  options: PostGraphileOptions<IncomingMessage, ServerResponse>;
  schema: GraphQLSchema;
}
let ctx: ICtx | null = null;

export const setup = async () => {
  const rootPgPool = new Pool({
    connectionString: TEST_DATABASE_URL,
  });
  const redisClient = new Redis(process.env.TEST_REDIS_URL);
  const workerUtils = await makeWorkerUtils({
    connectionString: TEST_DATABASE_URL,
  });
  const options = getPostGraphileOptions({
    rootPgPool,
    redisClient,
    workerUtils,
  });
  const schema = await createPostGraphileSchema(
    rootPgPool,
    "app_public",
    options
  );

  // Store the context
  ctx = {
    rootPgPool,
    redisClient,
    workerUtils,
    options,
    schema,
  };
};

export const teardown = async () => {
  try {
    if (!ctx) {
      return null;
    }
    const { rootPgPool, redisClient, workerUtils } = ctx;
    ctx = null;
    rootPgPool.end();
    workerUtils.release();
    // Flush redis after testa have run
    await redisClient.flushdb();
    redisClient.quit();
    return null;
  } catch (e) {
    console.error(e);
    return null;
  }
};

export const runGraphQLQuery = async (
  query: string, // The GraphQL query string
  variables: { [key: string]: any } | null, // The GraphQL variables
  reqOptions: { [key: string]: any } | null, // Any additional items to set on `req` (e.g. `{user: {id: 17}}`)
  checker: (
    result: ExecutionResult,
    context: {
      pgClient: PoolClient;
      redisClient: Redis.Redis;
      req: any;
    }
  ) => void | ExecutionResult | Promise<void | ExecutionResult> = () => {}, // Place test assertions in this function
  rollback = true
) => {
  if (!ctx) throw new Error("No ctx!");
  const { schema, rootPgPool, options } = ctx;
  const req = new MockReq({
    ip: "127.1.1.1",
    url: options.graphqlRoute || "/graphql",
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    ...reqOptions,
  });
  const res: any = { req };
  req.res = res;

  const {
    pgSettings: pgSettingsGenerator,
    additionalGraphQLContextFromRequest,
  } = options;
  const pgSettings =
    (typeof pgSettingsGenerator === "function"
      ? await pgSettingsGenerator(req)
      : pgSettingsGenerator) || {};

  // Because we're connected as the database owner, we should manually switch to
  // the authenticator role
  if (!pgSettings.role) {
    pgSettings.role = process.env.DATABASE_AUTHENTICATOR;
  }

  // Pass callback = false to have the result available from running this
  // function. Used by createRegistration test to first run the claimRegistrationToken
  // mutation and use its result in the actual test.
  const result = await withPostGraphileContext(
    {
      ...options,
      pgPool: rootPgPool,
      pgSettings,
      pgForceTransaction: true,
    },
    async (context) => {
      let checkResult;
      const { pgClient } = context;
      try {
        // This runs our GraphQL query, passing the replacement client
        const additionalContext = additionalGraphQLContextFromRequest
          ? await additionalGraphQLContextFromRequest(req, res)
          : null;
        const { redisClient } = additionalContext;
        const result = await graphql(
          schema,
          query,
          null,
          {
            ...context,
            ...additionalContext,
            __TESTING: true,
          },
          variables
        );
        // Expand errors
        if (result.errors) {
          if (options.handleErrors) {
            result.errors = options.handleErrors(result.errors, req, res);
          } else {
            // This does a similar transform that PostGraphile does to errors.
            // It's not the same. Sorry.
            result.errors = result.errors.map((rawErr) => {
              const e = Object.create(rawErr);
              Object.defineProperty(e, "originalError", {
                value: rawErr.originalError,
                enumerable: false,
              });

              if (e.originalError) {
                Object.keys(e.originalError).forEach((k) => {
                  try {
                    e[k] = e.originalError[k];
                  } catch (err) {
                    // Meh.
                  }
                });
              }
              return e;
            });
          }
        }

        // This is were we call the `checker` so you can do your assertions.
        // Also note that we pass the `replacementPgClient` so that you can
        // query the data in the database from within the transaction before it
        // gets rolled back. RedisClient is also passed to run assertions against
        // redis.
        checkResult = await checker(result, {
          pgClient,
          redisClient,
          req,
        });

        // You don't have to keep this, I just like knowing when things change!
        expect(sanitize(result)).toMatchSnapshot();

        return checkResult == null ? result : checkResult;
      } finally {
        if (rollback) {
          // Rollback the transaction so no changes are written to the DB - this
          // makes our tests fairly deterministic.
          await pgClient.query("rollback");
        }
      }
    }
  );
  return result;
};
