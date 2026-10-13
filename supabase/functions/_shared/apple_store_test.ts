import { deepStrictEqual, equal, rejects, throws } from "node:assert/strict";
import { Buffer } from "node:buffer";
import { createHash, generateKeyPairSync, X509Certificate } from "node:crypto";
import {
  APPLE_BUNDLE_ID,
  AppleStoreError,
  assertCompactJWS,
  createAppleVerifier,
  DISCOVERY_PASS_PRODUCT,
  loadAppleStoreConfig,
  MAX_SIGNED_TRANSACTION_BYTES,
  normalizeAppleTransaction,
  PRO_PRODUCTS,
  requireSameTransaction,
} from "./apple_store.ts";
import { APPLE_ROOT_CERTIFICATES } from "./apple_store_roots.ts";
import { appleStoreConfigurationReady } from "./apple_store_config.ts";
import {
  type AppleHandlerDependencies,
  appStoreNotificationHandler,
  purchaseVerifyHandler,
  readSignedBody,
} from "./apple_store_handlers.ts";
import { PaidAPIAccessError } from "./paid_api_guard.ts";
import { PURCHASE_PRODUCTS } from "./purchase_catalog.ts";
import type { JWSTransactionDecodedPayload } from "npm:@apple/app-store-server-library@3.1.0";

const USER = "12345678-1234-4234-8234-123456789012";
const OTHER = "12345678-1234-4234-8234-123456789013";
const NOTIFICATION = "12345678-1234-4234-8234-123456789014";
const now = Date.now();

Deno.test("purchase catalog IDs satisfy App Store Connect's allowed characters", () => {
  for (const productId of Object.values(PURCHASE_PRODUCTS)) {
    equal(/^[A-Za-z0-9._]+$/.test(productId), true);
  }
  equal(DISCOVERY_PASS_PRODUCT, PURCHASE_PRODUCTS.discoveryPass);
  deepStrictEqual(
    [...PRO_PRODUCTS].sort(),
    [PURCHASE_PRODUCTS.proMonthly, PURCHASE_PRODUCTS.proAnnual].sort(),
  );
});

function transaction(
  overrides: Partial<JWSTransactionDecodedPayload> = {},
): JWSTransactionDecodedPayload {
  return {
    transactionId: "20000000001",
    originalTransactionId: "20000000001",
    productId: DISCOVERY_PASS_PRODUCT,
    bundleId: APPLE_BUNDLE_ID,
    environment: "Production",
    appAccountToken: USER,
    quantity: 1,
    type: "Consumable",
    inAppOwnershipType: "PURCHASED",
    signedDate: now,
    purchaseDate: now - 60_000,
    ...overrides,
  };
}

function fixture() {
  const state = {
    submitted: transaction(),
    current: transaction(),
    owner: USER as string | null,
    calls: [] as string[],
    grants: [] as Parameters<AppleHandlerDependencies["apply"]>[],
    wallet: {
      commerceEnabled: true,
      proEnabled: false,
      purchased: { explore: 4, tiktok: 1 },
    },
    user: { id: USER, isAnonymous: false },
    notification: {
      notificationType: "ONE_TIME_CHARGE",
      notificationUUID: NOTIFICATION,
      version: "2.0",
      signedDate: now,
      data: { signedTransactionInfo: "verified-by-test-double" },
    },
  };
  const dependencies: AppleHandlerDependencies = {
    authenticate: async () => {
      state.calls.push("auth");
      return state.user;
    },
    wallet: async () => {
      state.calls.push("wallet");
      return state.wallet;
    },
    apple: () => ({
      environment: "Production",
      verifier: {
        transaction: async () => {
          state.calls.push("signature");
          return state.submitted;
        },
        currentTransaction: async () => {
          state.calls.push("apple-current");
          return state.current;
        },
        notification: async () => {
          state.calls.push("notification");
          return state.notification;
        },
        renewal: async () => {
          throw new Error("unexpected renewal");
        },
      },
    }),
    owner: async () => {
      state.calls.push("owner");
      return state.owner;
    },
    apply: async (...args) => {
      state.calls.push("apply");
      state.grants.push(args);
    },
  };
  return { state, dependencies };
}

function request(
  body: unknown = { signedTransaction: "signed-test-value" },
  method = "POST",
) {
  return new Request("https://example.invalid", {
    method,
    headers: { "Content-Type": "application/json" },
    ...(method === "POST" ? { body: JSON.stringify(body) } : {}),
  });
}
async function code(response: Response) {
  return (await response.json()).code;
}
function isCode(expected: string) {
  return (error: unknown) =>
    error instanceof AppleStoreError && error.code === expected;
}

Deno.test("configuration fails closed for missing secrets and local/Xcode environments", () => {
  for (
    const environment of [
      undefined,
      "",
      "Xcode",
      "LocalTesting",
      "Sandbox,Production",
      "production",
    ]
  ) {
    throws(
      () =>
        loadAppleStoreConfig((key) =>
          key === "BILU_APP_STORE_ENVIRONMENT" ? environment : undefined
        ),
      isCode("PURCHASE_VERIFICATION_UNAVAILABLE"),
    );
  }
  const { privateKey } = generateKeyPairSync("ec", {
    namedCurve: "prime256v1",
  });
  const values: Record<string, string> = {
    BILU_APP_STORE_ENVIRONMENT: "Sandbox",
    BILU_APPLE_APP_ID: "123456789",
    APP_STORE_ISSUER_ID: USER,
    APP_STORE_KEY_ID: "ABC123DE45",
    APP_STORE_PRIVATE_KEY_P8: privateKey.export({
      type: "pkcs8",
      format: "pem",
    }).toString(),
  };
  equal(loadAppleStoreConfig((key) => values[key]).environment, "Sandbox");
  equal(appleStoreConfigurationReady((key) => values[key]), true);
  delete values.APP_STORE_PRIVATE_KEY_P8;
  equal(appleStoreConfigurationReady((key) => values[key]), false);
  throws(
    () => loadAppleStoreConfig((key) => values[key]),
    isCode("PURCHASE_VERIFICATION_UNAVAILABLE"),
  );
});

Deno.test("pinned Apple roots parse and match reviewed public fingerprints", () => {
  equal(APPLE_ROOT_CERTIFICATES.length, 3);
  for (const root of APPLE_ROOT_CERTIFICATES) {
    const bytes = Buffer.from(root.derBase64, "base64");
    equal(createHash("sha256").update(bytes).digest("hex"), root.sha256);
    const cert = new X509Certificate(bytes);
    equal(cert.ca, true);
    equal(cert.verify(cert.publicKey), true);
  }
});

Deno.test("real official verifier rejects a forged chain without network access", async () => {
  const verifier = createAppleVerifier({
    environment: "Production",
    appAppleId: 1234,
    issuerId: USER,
    keyId: "ABC123DE45",
    privateKey: "unused-until-api-call",
  });
  const header = Buffer.from(
    JSON.stringify({
      alg: "ES256",
      x5c: Array(3).fill(APPLE_ROOT_CERTIFICATES[2].derBase64),
    }),
  ).toString("base64url");
  const payload = Buffer.from(JSON.stringify(transaction())).toString(
    "base64url",
  );
  await rejects(
    () =>
      verifier.transaction(
        `${header}.${payload}.${Buffer.alloc(64).toString("base64url")}`,
      ),
    isCode("INVALID_TRANSACTION"),
  );
});

Deno.test("algorithm confusion, unsigned local payloads and oversized JWS are rejected", () => {
  for (
    const value of [
      "a.b",
      "a.b.",
      "abc",
      "x".repeat(MAX_SIGNED_TRANSACTION_BYTES + 1),
    ]
  ) {
    throws(
      () => assertCompactJWS(value, MAX_SIGNED_TRANSACTION_BYTES),
      isCode("INVALID_TRANSACTION"),
    );
  }
  for (const alg of ["none", "HS256", "ES384"]) {
    const header = Buffer.from(
      JSON.stringify({ alg, x5c: ["YQ==", "YQ==", "YQ=="] }),
    ).toString("base64url");
    throws(
      () =>
        assertCompactJWS(`${header}.e30.c2ln`, MAX_SIGNED_TRANSACTION_BYTES),
      isCode("INVALID_TRANSACTION"),
    );
  }
});

Deno.test("transaction checks reject wrong identity, environment, product and invalid state", () => {
  const invalid: Partial<JWSTransactionDecodedPayload>[] = [
    { bundleId: "com.attacker.app" },
    { environment: "Sandbox" },
    { environment: "Xcode" },
    { appAccountToken: undefined },
    { appAccountToken: "not-uuid" },
    { transactionId: "../100" },
    { originalTransactionId: "" },
    { quantity: 0 },
    { quantity: 2 },
    { type: "Non-Consumable" },
    { inAppOwnershipType: "FAMILY_SHARED" },
    { signedDate: NaN },
    { purchaseDate: now + 120_000 },
    { signedDate: now + 120_000 },
    { expiresDate: now + 60_000 },
    { revocationReason: 1 },
  ];
  for (const fields of invalid) {
    throws(
      () => normalizeAppleTransaction(transaction(fields), "Production", now),
      isCode("INVALID_TRANSACTION"),
    );
  }
  throws(
    () =>
      normalizeAppleTransaction(
        transaction({ productId: "arbitrary" }),
        "Production",
        now,
      ),
    isCode("PRODUCT_UNAVAILABLE"),
  );
  const valid = normalizeAppleTransaction(transaction(), "Production", now);
  equal(valid.expiresAt, null);
  equal(valid.revokedAt, null);
  equal(
    normalizeAppleTransaction(
      transaction({ appAccountToken: USER.toUpperCase(), revocationDate: now }),
      "Production",
      now,
    ).revokedAt,
    new Date(now).toISOString(),
  );
});

Deno.test("subscription expiry and upgrade state never become consumable credits", () => {
  const subscription = transaction({
    productId: [...PRO_PRODUCTS][0],
    type: "Auto-Renewable Subscription",
    expiresDate: now + 86_400_000,
  });
  equal(
    normalizeAppleTransaction(subscription, "Production", now).expiresAt,
    new Date(now + 86_400_000).toISOString(),
  );
  equal(
    normalizeAppleTransaction(
      { ...subscription, isUpgraded: true },
      "Production",
      now,
    ).expiresAt,
    new Date(now).toISOString(),
  );
  throws(
    () =>
      normalizeAppleTransaction(
        { ...subscription, expiresDate: undefined },
        "Production",
        now,
      ),
    isCode("INVALID_TRANSACTION"),
  );
});

Deno.test("fresh API response must represent precisely the submitted transaction", () => {
  const submitted = normalizeAppleTransaction(transaction(), "Production", now);
  for (
    const changed of [{ transactionId: "2" }, { originalTransactionId: "3" }, {
      appAccountToken: OTHER,
    }, { purchasedAt: new Date(now).toISOString() }]
  ) {
    throws(
      () => requireSameTransaction(submitted, { ...submitted, ...changed }),
      isCode("INVALID_TRANSACTION"),
    );
  }
  throws(
    () =>
      requireSameTransaction(submitted, {
        ...submitted,
        signedAt: new Date(now - 1).toISOString(),
      }),
    isCode("PURCHASE_VERIFICATION_UNAVAILABLE"),
  );
  throws(
    () =>
      requireSameTransaction({
        ...submitted,
        revokedAt: new Date(now).toISOString(),
      }, submitted),
    isCode("PURCHASE_VERIFICATION_UNAVAILABLE"),
  );
});

Deno.test("nested renewal signature and subscription linkage are required", async () => {
  for (
    const mismatch of [
      "signature",
      "environment",
      "original",
      "token",
      "product",
      "none",
    ]
  ) {
    const { state, dependencies } = fixture();
    state.submitted = transaction({
      productId: [...PRO_PRODUCTS][0],
      type: "Auto-Renewable Subscription",
      expiresDate: now + 86_400_000,
    });
    state.notification.notificationType = "DID_RENEW";
    const original = dependencies.apple();
    dependencies.apple = () => ({
      ...original,
      verifier: {
        ...original.verifier,
        notification: async () => ({
          ...state.notification,
          data: {
            ...state.notification.data,
            signedRenewalInfo: "signed-renewal",
          },
        }),
        renewal: async () => {
          if (mismatch === "signature") {
            throw new AppleStoreError(422, "INVALID_TRANSACTION", "Invalid");
          }
          return {
            environment: mismatch === "environment" ? "Sandbox" : "Production",
            originalTransactionId: mismatch === "original"
              ? "2"
              : state.submitted.originalTransactionId,
            productId: mismatch === "product"
              ? DISCOVERY_PASS_PRODUCT
              : state.submitted.productId,
            appAccountToken: mismatch === "token" ? OTHER : USER,
            signedDate: now,
          };
        },
      },
    });
    const response = await appStoreNotificationHandler(dependencies)(
      request({ signedPayload: "signed" }),
    );
    equal(response.status, mismatch === "none" ? 200 : 422);
    equal(state.grants.length, mismatch === "none" ? 1 : 0);
  }
});

Deno.test("purchase authenticates nonanonymous account before signature/API/application", async () => {
  for (const isAnonymous of [true, false]) {
    const { state, dependencies } = fixture();
    state.user.isAnonymous = isAnonymous;
    if (!isAnonymous) {
      dependencies.authenticate = async () => {
        throw new PaidAPIAccessError(401, "INVALID_SESSION", "Invalid session");
      };
    }
    const response = await purchaseVerifyHandler(dependencies)(request());
    equal(response.status, isAnonymous ? 403 : 401);
    equal(
      await code(response),
      isAnonymous ? "ACCOUNT_REQUIRED" : "INVALID_SESSION",
    );
    equal(state.calls.includes("signature"), false);
    equal(state.grants.length, 0);
  }
});

Deno.test("missing Apple configuration still rejects fulfillment while sales are paused", async () => {
  const { state, dependencies } = fixture();
  state.wallet.commerceEnabled = false;
  dependencies.apple = () => {
    throw new AppleStoreError(
      503,
      "PURCHASE_VERIFICATION_UNAVAILABLE",
      "Unavailable",
    );
  };
  equal(
    await code(await purchaseVerifyHandler(dependencies)(request())),
    "PURCHASE_VERIFICATION_UNAVAILABLE",
  );
  equal(state.calls.includes("signature"), false);
  equal(state.grants.length, 0);
});

Deno.test("paid in-flight and restored Passes fulfill while sales are paused", async () => {
  for (const owner of [null, USER]) {
    const { state, dependencies } = fixture();
    state.wallet.commerceEnabled = false;
    state.owner = owner;
    const response = await purchaseVerifyHandler(dependencies)(request());
    equal(response.status, 200);
    equal(state.grants.length, 1);
    equal(state.calls.includes("apple-current"), true);
    equal(state.grants[0][0], USER);
  }
});

Deno.test("disabled Pro rejects new original ownership before calling Apple's API", async () => {
  const { state, dependencies } = fixture();
  state.wallet.commerceEnabled = false;
  state.owner = null;
  state.submitted = transaction({
    productId: [...PRO_PRODUCTS][0],
    type: "Auto-Renewable Subscription",
    expiresDate: now + 1_000,
  });
  equal(
    await code(await purchaseVerifyHandler(dependencies)(request())),
    "PRODUCT_UNAVAILABLE",
  );
  equal(state.calls.includes("apple-current"), false);
  equal(state.grants.length, 0);
});

Deno.test("established Pro transactions reconcile while sales and Pro offers are paused", async () => {
  const { state, dependencies } = fixture();
  state.wallet.commerceEnabled = false;
  state.submitted = transaction({
    productId: [...PRO_PRODUCTS][0],
    type: "Auto-Renewable Subscription",
    expiresDate: now + 86_400_000,
  });
  state.current = { ...state.submitted };
  equal((await purchaseVerifyHandler(dependencies)(request())).status, 200);
  equal(state.grants.length, 1);
  equal(state.calls.includes("owner"), true);
  equal(state.calls.includes("apple-current"), true);
});

Deno.test("account mismatch is rejected before the Apple API and wallet mutation", async () => {
  const { state, dependencies } = fixture();
  state.submitted.appAccountToken = OTHER;
  equal(
    await code(await purchaseVerifyHandler(dependencies)(request())),
    "PURCHASE_ACCOUNT_MISMATCH",
  );
  equal(state.calls.includes("apple-current"), false);
  equal(state.grants.length, 0);
});

Deno.test("verified current state is applied before returning the canonical wallet", async () => {
  const { state, dependencies } = fixture();
  state.current.revocationDate = now;
  const response = await purchaseVerifyHandler(dependencies)(request());
  equal(response.status, 200);
  deepStrictEqual(await response.json(), { wallet: state.wallet });
  deepStrictEqual(state.calls, [
    "auth",
    "wallet",
    "signature",
    "apple-current",
    "apply",
    "wallet",
  ]);
  equal(state.grants[0][1].revokedAt, new Date(now).toISOString());
});

Deno.test("bad signature and unavailable current state never grant", async () => {
  for (const failure of ["signature", "api"]) {
    const { state, dependencies } = fixture();
    const original = dependencies.apple();
    dependencies.apple = () => ({
      ...original,
      verifier: {
        ...original.verifier,
        ...(failure === "signature"
          ? {
            transaction: async () => {
              throw new AppleStoreError(422, "INVALID_TRANSACTION", "Invalid");
            },
          }
          : {
            currentTransaction: async () => {
              throw new AppleStoreError(
                503,
                "PURCHASE_VERIFICATION_UNAVAILABLE",
                "Unavailable",
              );
            },
          }),
      },
    });
    equal(
      (await purchaseVerifyHandler(dependencies)(request())).status,
      failure === "signature" ? 422 : 503,
    );
    equal(state.grants.length, 0);
  }
});

Deno.test("notifications cannot create ownership from an appAccountToken", async () => {
  const { state, dependencies } = fixture();
  state.owner = null;
  const response = await appStoreNotificationHandler(dependencies)(
    request({ signedPayload: "signed" }),
  );
  equal(response.status, 200);
  equal(state.grants.length, 0);
  equal(state.calls.includes("auth"), false);
});

Deno.test("notifications reject mismatched established owners and unsigned revocations", async () => {
  const { state, dependencies } = fixture();
  state.owner = OTHER;
  equal(
    await code(
      await appStoreNotificationHandler(dependencies)(
        request({ signedPayload: "signed" }),
      ),
    ),
    "PURCHASE_ACCOUNT_MISMATCH",
  );
  state.owner = USER;
  state.notification.notificationType = "REFUND";
  equal(
    await code(
      await appStoreNotificationHandler(dependencies)(
        request({ signedPayload: "signed" }),
      ),
    ),
    "INVALID_TRANSACTION",
  );
  equal(state.grants.length, 0);
});

Deno.test("refunds still apply while purchases are disabled and preserve replay identity", async () => {
  const { state, dependencies } = fixture();
  state.wallet.commerceEnabled = false;
  state.notification.notificationType = "REFUND";
  state.submitted.revocationDate = now;
  const handler = appStoreNotificationHandler(dependencies);
  equal((await handler(request({ signedPayload: "signed" }))).status, 200);
  equal((await handler(request({ signedPayload: "signed" }))).status, 200);
  equal(state.grants.length, 2);
  deepStrictEqual(state.grants[0], state.grants[1]);
  deepStrictEqual(state.grants[0][2], { id: NOTIFICATION, type: "REFUND" });
  equal(state.calls.includes("wallet"), false);
});

Deno.test("TEST and future notification types are verified and acknowledged without mutation", async () => {
  for (const notificationType of ["TEST", "FUTURE_TYPE"]) {
    const { state, dependencies } = fixture();
    state.notification.notificationType = notificationType;
    equal(
      (await appStoreNotificationHandler(dependencies)(
        request({ signedPayload: "signed" }),
      )).status,
      200,
    );
    deepStrictEqual(state.calls, ["notification"]);
    equal(state.grants.length, 0);
  }
});

Deno.test("methods, malformed and oversized payloads fail before any dependency", async () => {
  const { state, dependencies } = fixture();
  const handler = purchaseVerifyHandler(dependencies);
  equal((await handler(request(undefined, "GET"))).status, 405);
  equal((await handler(request(undefined, "OPTIONS"))).status, 204);
  for (
    const body of [null, [], {}, { signedTransaction: 4 }, {
      signedTransaction: "x",
      userId: USER,
    }]
  ) {
    equal((await handler(request(body))).status, 400);
  }
  equal(
    (await handler(
      request({
        signedTransaction: "x".repeat(MAX_SIGNED_TRANSACTION_BYTES + 1),
      }),
    )).status,
    413,
  );
  const malformed = new Request("https://example.invalid", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{",
  });
  equal((await handler(malformed)).status, 400);
  equal(state.calls.length, 0);
});

Deno.test("streaming payload limit does not trust missing or false Content-Length", async () => {
  for (const contentLength of [undefined, "1"]) {
    const bytes = new TextEncoder().encode("x".repeat(300));
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(bytes);
        controller.close();
      },
    });
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (contentLength) headers["Content-Length"] = contentLength;
    const input = new Request("https://example.invalid", {
      method: "POST",
      headers,
      body: stream,
    });
    await rejects(
      () => readSignedBody(input, "signedTransaction", 10),
      isCode("PAYLOAD_TOO_LARGE"),
    );
  }
});
