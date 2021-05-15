import { makeWrapResolversPlugin } from "graphile-utils";
import { Redis } from "ioredis";

import { OurGraphQLContext } from "../middleware/installPostGraphile";

if (!process.env.NODE_ENV) {
  throw new Error("No NODE_ENV envvar! Try `export NODE_ENV=development`");
}

// 30 minutes timeout
const RATE_LIMIT_TIMEOUT = 30;

function constructRateLimitKey(
  fieldName: string,
  id: string,
  ipAddress: string
) {
  return `rate-limit:${fieldName}:${id}:${ipAddress}`;
}
class RateLimitException extends Error {
  code: string;
  constructor(message: string) {
    super(message);
    this.code = "RLIMIT";
  }
}

async function rateLimitResolver(
  limit: number,
  rateLimitId: string,
  ipAddress: string,
  fieldName: string,
  resolve: any,
  redisClient: Redis
) {
  try {
    // First run the resolver, if it throws an error we don't want
    // to set a rate limit key to redis
    const result = await resolve();

    const key = constructRateLimitKey(fieldName, rateLimitId, ipAddress);
    const current = Number(await redisClient.get(key));

    if (current >= limit) {
      throw new RateLimitException(
        `Too many requests. You have been rate-limited for ${RATE_LIMIT_TIMEOUT} minutes.`
      );
    }

    if (current < limit) {
      await redisClient.incr(key);
      await redisClient.expire(key, RATE_LIMIT_TIMEOUT * 60);
    }

    return result;
  } catch (e) {
    throw e;
  }
}

const RateLimitPlugin = makeWrapResolversPlugin({
  Mutation: {
    // TODO: Delete registration if the user is rate limited.
    // Currently, a registration is created even if the user is rate limited.
    claimRegistrationToken: async (
      resolve,
      _source,
      args,
      context: OurGraphQLContext,
      resolveInfo
    ) => {
      const { ipAddress, redisClient } = context;
      const { eventId, quotaId } = args.input;
      const { fieldName } = resolveInfo;
      const rateLimitId = `${eventId}:${quotaId}`;
      return await rateLimitResolver(
        3,
        rateLimitId,
        ipAddress,
        fieldName,
        resolve,
        redisClient
      );
    },
    // If more resolvers need rate limiting in the future
    // they can be added here.
  },
});

export default RateLimitPlugin;
