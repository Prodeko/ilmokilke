import { Server } from "http";

import * as Sentry from "@sentry/node";
import * as Tracing from "@sentry/tracing";
import express, { Express } from "express";
import { Middleware } from "postgraphile";

import { cloudflareIps } from "./cloudflare";
import * as middleware from "./middleware";
import { makeShutdownActions, ShutdownAction } from "./shutdownActions";
import { sanitizeEnv } from "./utils";

// Server may not always be supplied, e.g. where mounting on a sub-route
export function getHttpServer(app: Express): Server | void {
  return app.get("httpServer");
}

export function getShutdownActions(app: Express): ShutdownAction[] {
  return app.get("shutdownActions");
}

export function getWebsocketMiddlewares(
  app: Express
): Middleware<express.Request, express.Response>[] {
  return app.get("websocketMiddlewares");
}

function initSentry(app: Express) {
  Sentry.init({
    environment: process.env.NODE_ENV,
    dsn: process.env.SENTRY_DSN,
    integrations: [
      // enable HTTP calls tracing
      new Sentry.Integrations.Http({ tracing: true }),
      // enable Express.js middleware tracing
      new Tracing.Integrations.Express({ app }),
      // enable database query tracing
      new Tracing.Integrations.Postgres(),
    ],

    // We recommend adjusting this value in production, or using tracesSampler
    // for finer control
    tracesSampleRate: 1.0,
  });
}

export async function makeApp({
  httpServer,
}: {
  httpServer?: Server;
} = {}): Promise<Express> {
  sanitizeEnv();

  const isTest = process.env.NODE_ENV === "test";
  const isDev = process.env.NODE_ENV === "development";

  const shutdownActions = makeShutdownActions();

  if (isDev) {
    shutdownActions.push(() => {
      require("inspector").close();
    });
  }

  /*
   * Our Express server
   */
  const app = express();
  initSentry(app);

  /*
   * In production, we may need to enable the 'trust proxy' setting so that the
   * server knows it's running in SSL mode, and so the logs can log the true
   * IP address of the client rather than the IP address of our proxy.
   */
  if (process.env.TRUST_PROXY) {
    /*
      We recommend you set TRUST_PROXY to the following:

        loopback,linklocal,uniquelocal

      followed by any other IPs you need to trust. For example for CloudFlare
      you can get the list of IPs from https://www.cloudflare.com/ips-v4; we
      have a script that does this for you (`yarn server cloudflare:import`)
      and a special `TRUST_PROXY=cloudflare` setting you can use to use them.
    */
    app.set(
      "trust proxy",
      process.env.TRUST_PROXY === "1"
        ? true
        : process.env.TRUST_PROXY === "cloudflare"
        ? ["loopback", "linklocal", "uniquelocal", ...cloudflareIps]
        : process.env.TRUST_PROXY.split(",")
    );
  }

  /*
   * Getting access to the HTTP server directly means that we can do things
   * with websockets if we need to (e.g. GraphQL subscriptions).
   */
  app.set("httpServer", httpServer);

  /*
   * For a clean nodemon shutdown, we need to close all our sockets otherwise
   * we might not come up cleanly again (inside nodemon).
   */
  app.set("shutdownActions", shutdownActions);

  /*
   * When we're using websockets, we may want them to have access to
   * sessions/etc for authentication.
   */
  const websocketMiddlewares: Middleware<
    express.Request,
    express.Response
  >[] = [];
  app.set("websocketMiddlewares", websocketMiddlewares);

  /*
   * Middleware is installed from the /server/middleware directory. These
   * helpers may augment the express app with new settings and/or install
   * express middleware. These helpers may be asynchronous, but they should
   * operate very rapidly to enable quick as possible server startup.
   */
  await middleware.installSentryRequestHandler(app);
  await middleware.installDatabasePools(app);
  await middleware.installRedis(app);
  await middleware.installWorkerUtils(app);
  await middleware.installHelmet(app);
  await middleware.installSameOrigin(app);
  await middleware.installSession(app);
  await middleware.installCSRFProtection(app);
  await middleware.installPassport(app);
  await middleware.installLogging(app);
  // These are our assets: images/etc; served out of the /@app/server/public folder (if present)
  await middleware.installSharedStatic(app);
  if (isTest || isDev) {
    await middleware.installCypressServerCommand(app);
  }
  await middleware.installPostGraphile(app);
  await middleware.installSSR(app);

  /*
   * Error handling middleware
   */
  await middleware.installErrorHandler(app);

  return app;
}
