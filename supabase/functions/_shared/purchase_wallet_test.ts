import { deepStrictEqual, equal, rejects } from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import {
  commitDiscovery,
  getPurchaseWallet,
  purchaseWalletRPC,
  readDiscovery,
  releaseDiscovery,
  reserveDiscovery,
} from "./purchase_wallet.ts";
import { handlePurchaseWallet } from "../purchase-wallet/index.ts";
import { PaidAPIAccessError } from "./paid_api_guard.ts";

const USER = "12345678-1234-4234-8234-123456789012";
const DISCOVERY = "12345678-1234-4234-8234-123456789013";
const privateKey = generateKeyPairSync("ec", { namedCurve: "prime256v1" })
  .privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const environment = {
  SUPABASE_URL: "https://wallet.invalid",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-role-only",
  BILU_COMMERCE_ENABLED: "true",
  BILU_PRO_ENABLED: "false",
  BILU_APP_STORE_ENVIRONMENT: "Production",
  BILU_APPLE_APP_ID: "123456789",
  APP_STORE_ISSUER_ID: USER,
  APP_STORE_KEY_ID: "ABC123DE45",
  APP_STORE_PRIVATE_KEY_P8: privateKey,
};

function snapshot(overrides: Record<string, unknown> = {}) {
  return {
    accountId: USER,
    appAccountToken: USER,
    requiresSignIn: false,
    plan: "free",
    periodStart: "2026-09-30T17:00:00-07:00",
    periodEnd: "2026-10-31T17:00:00-07:00",
    included: { explore: 2, tiktok: 1 },
    purchased: { explore: 4, tiktok: 1 },
    commerceEnabled: true,
    proEnabled: false,
    appleEnvironment: "Production",
    ...overrides,
  };
}

async function fixture(
  run: () => Promise<void>,
  fetcher: typeof fetch = () => Promise.resolve(Response.json(snapshot())),
) {
  const oldEnvironment = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries(environment)) {
    oldEnvironment.set(key, Deno.env.get(key));
    Deno.env.set(key, value);
  }
  const oldFetch = globalThis.fetch;
  globalThis.fetch = fetcher;
  try {
    await run();
  } finally {
    globalThis.fetch = oldFetch;
    for (const [key, value] of oldEnvironment) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

function isCode(code: string) {
  return (error: unknown) =>
    error instanceof PaidAPIAccessError && error.code === code;
}

Deno.test("wallet returns canonical UTC snapshot and strips internal Apple environment", async () => {
  await fixture(async () => {
    const wallet = await getPurchaseWallet({ id: USER, isAnonymous: false });
    equal(wallet.commerceEnabled, true);
    equal(wallet.proEnabled, false);
    equal(wallet.periodStart, "2026-10-01T00:00:00.000Z");
    equal(wallet.periodEnd, "2026-11-01T00:00:00.000Z");
    equal("appleEnvironment" in wallet, false);
    deepStrictEqual(wallet.purchased, { explore: 4, tiktok: 1 });
  });
});

Deno.test("wallet purchase offers fail closed without complete Apple configuration", async () => {
  await fixture(async () => {
    Deno.env.delete("APP_STORE_PRIVATE_KEY_P8");
    const wallet = await getPurchaseWallet({ id: USER, isAnonymous: false });
    equal(wallet.commerceEnabled, false);
    deepStrictEqual(wallet.purchased, { explore: 4, tiktok: 1 });
  });
});

Deno.test("wallet requires both feature gates and a matching Apple environment", async () => {
  for (
    const [envFlag, dbFlag, appleEnvironment] of [
      ["false", true, "Production"],
      ["true", false, "Production"],
      ["true", true, "Sandbox"],
      ["true", true, undefined],
    ] as const
  ) {
    await fixture(
      async () => {
        Deno.env.set("BILU_COMMERCE_ENABLED", envFlag);
        equal(
          (await getPurchaseWallet({ id: USER, isAnonymous: false }))
            .commerceEnabled,
          false,
        );
      },
      () =>
        Promise.resolve(
          Response.json(
            snapshot({ commerceEnabled: dbFlag, appleEnvironment }),
          ),
        ),
    );
  }
});

Deno.test("authenticated anonymous identity always requires durable sign in", async () => {
  await fixture(async () => {
    equal(
      (await getPurchaseWallet({ id: USER, isAnonymous: true })).requiresSignIn,
      true,
    );
  });
});

Deno.test("wallet rejects malformed balances, dates, and cross-account snapshots", async () => {
  for (
    const override of [
      { accountId: DISCOVERY },
      { appAccountToken: DISCOVERY },
      { included: { explore: -1, tiktok: 1 } },
      { purchased: { explore: "4", tiktok: 1 } },
      { periodStart: "invalid" },
      { commerceEnabled: "true" },
    ]
  ) {
    await fixture(async () => {
      await rejects(
        () => getPurchaseWallet({ id: USER, isAnonymous: false }),
        isCode("WALLET_UNAVAILABLE"),
      );
    }, () => Promise.resolve(Response.json(snapshot(override))));
  }
});

Deno.test("wallet RPC sends service credentials and server parameters only", async () => {
  await fixture(async () => {
    await purchaseWalletRPC("purchase_wallet_snapshot", { p_user_id: USER });
  }, (_input, init) => {
    const headers = new Headers(init?.headers);
    equal(headers.get("authorization"), "Bearer test-service-role-only");
    equal(headers.get("apikey"), "test-service-role-only");
    deepStrictEqual(JSON.parse(String(init?.body)), { p_user_id: USER });
    return Promise.resolve(Response.json(snapshot()));
  });
});

Deno.test("wallet RPC fails closed on transport, database, and response errors", async () => {
  for (
    const fetcher of [
      () => Promise.reject(new Error("offline")),
      () =>
        Promise.resolve(
          new Response("database-private-details", { status: 500 }),
        ),
      () => Promise.resolve(new Response("malformed-json")),
    ]
  ) {
    await fixture(async () => {
      await rejects(
        () => purchaseWalletRPC("purchase_wallet_snapshot", {}),
        isCode("WALLET_UNAVAILABLE"),
      );
    }, fetcher);
  }
});

Deno.test("fresh reservation is blocked before RPC when disabled or invalid", async () => {
  await fixture(async () => {
    Deno.env.set("BILU_COMMERCE_ENABLED", "false");
    await rejects(
      () => reserveDiscovery(USER, DISCOVERY, "explore"),
      isCode("COMMERCE_UNAVAILABLE"),
    );
    await rejects(
      () => reserveDiscovery(USER, "bad", "explore"),
      isCode("INVALID_DISCOVERY"),
    );
  }, () => {
    throw new Error("RPC must not run");
  });
});

Deno.test("exhausted discovery returns stable402 recovery code", async () => {
  await fixture(
    async () => {
      await rejects(
        () => reserveDiscovery(USER, DISCOVERY, "explore"),
        (error) =>
          error instanceof PaidAPIAccessError && error.status === 402 &&
          error.code === "DISCOVERY_CREDITS_REQUIRED",
      );
    },
    () =>
      Promise.resolve(
        Response.json({
          discoveryId: DISCOVERY,
          kind: "explore",
          status: "exhausted",
          source: null,
          acquired: false,
        }),
      ),
  );
});

Deno.test("existing read commit and release remain available while sales are paused", async () => {
  await fixture(
    async () => {
      Deno.env.set("BILU_COMMERCE_ENABLED", "false");
      for (
        const action of [
          () => readDiscovery(USER, DISCOVERY, "explore"),
          () =>
            commitDiscovery(USER, DISCOVERY, "explore", { restaurants: [] }),
          () => releaseDiscovery(USER, DISCOVERY, "explore"),
        ]
      ) {
        const result = await action();
        equal(result.status, "committed");
        equal(result.acquired, false);
      }
    },
    () =>
      Promise.resolve(
        Response.json({
          discoveryId: DISCOVERY,
          kind: "explore",
          status: "committed",
          source: "included",
          acquired: false,
          result: { restaurants: [] },
        }),
      ),
  );
});

Deno.test("cross-environment discovery access maps to a stable409", async () => {
  await fixture(
    async () => {
      for (
        const action of [
          () => reserveDiscovery(USER, DISCOVERY, "explore"),
          () => readDiscovery(USER, DISCOVERY, "explore"),
          () =>
            commitDiscovery(USER, DISCOVERY, "explore", { restaurants: [] }),
        ]
      ) {
        await rejects(action, (error) =>
          error instanceof PaidAPIAccessError &&
          error.status === 409 &&
          error.code === "DISCOVERY_ENVIRONMENT_MISMATCH");
      }
    },
    () =>
      Promise.resolve(
        Response.json({
          discoveryId: DISCOVERY,
          kind: "explore",
          status: "environment_mismatch",
          source: null,
          acquired: false,
        }),
      ),
  );
});

Deno.test("wallet endpoint OPTIONS and method rejection do not call auth or accounting", async () => {
  await fixture(async () => {
    equal(
      (await handlePurchaseWallet(
        new Request("https://wallet.invalid", { method: "OPTIONS" }),
      )).status,
      200,
    );
    equal(
      (await handlePurchaseWallet(
        new Request("https://wallet.invalid", { method: "GET" }),
      )).status,
      405,
    );
  }, () => {
    throw new Error("no network expected");
  });
});
