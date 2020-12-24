import { makeWrapResolversPlugin } from "graphile-utils";
import { GraphQLResolveInfo } from "graphql";
import { createNodeRedisClient } from "handy-redis";

import { OurGraphQLContext } from "../middleware/installPostGraphile";

if (!process.env.NODE_ENV) {
  throw new Error("No NODE_ENV envvar! Try `export NODE_ENV=development`");
}

const isDev = process.env.NODE_ENV === "development";

const client = createNodeRedisClient({ url: process.env.REDIS_URL });

type AugmentedGraphQLFieldResolver<
  TSource,
  TContext,
  TArgs = { [argName: string]: any }
> = (
  resolve: any,
  source: TSource,
  args: TArgs,
  context: TContext,
  resolveInfo: GraphQLResolveInfo
) => any;

// 30 minutes timeout
const RATE_LIMIT_TIMEOUT = 60 * 30;

function constructRateLimitKey(
  fieldName: string,
  id: string,
  ipAddress: string
) {
  return `rate-limit:${fieldName}:${id}:${ipAddress}`;
}

function rateLimitResolver(
  limit: number
): AugmentedGraphQLFieldResolver<{}, OurGraphQLContext, any> {
  return async (
    resolve,
    _source,
    { input: { eventId } },
    { ipAddress },
    { fieldName }
  ) => {
    // By default rate limiting is disabled in dev mode.
    // To work on rate limiting, invert the following if statement.
    if (!isDev) {
      const key = constructRateLimitKey(fieldName, eventId, ipAddress);
      const current = await client.incr(key);

      if (current > limit) {
        throw new Error("Too many requests.");
      } else {
        await client.expire(key, RATE_LIMIT_TIMEOUT);
      }
    }
    return await resolve();
  };
}

const RateLimitPlugin = makeWrapResolversPlugin({
  Mutation: {
    claimRegistrationToken: rateLimitResolver(1),
    // If more resolvers need rate limiting in the future
    // they can be added here.
  },
});

export default RateLimitPlugin;