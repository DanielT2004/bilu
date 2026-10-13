import {
  AppleStoreError,
  type AppleVerifier,
  DISCOVERY_PASS_PRODUCT,
  invalidTransaction,
  isAccountId,
  MAX_SIGNED_NOTIFICATION_BYTES,
  MAX_SIGNED_TRANSACTION_BYTES,
  normalizeAppleTransaction,
  requireSameTransaction,
  timestamp,
  type VerifiedAppleTransaction,
} from "./apple_store.ts";
import {
  type AuthenticatedUser,
  paidAPIAccessErrorResponse,
} from "./paid_api_guard.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export interface AppleWalletSnapshot {
  commerceEnabled: boolean;
  proEnabled: boolean;
}

export interface AppleHandlerDependencies {
  authenticate(request: Request): Promise<AuthenticatedUser>;
  wallet(user: AuthenticatedUser): Promise<AppleWalletSnapshot>;
  apple(): { verifier: AppleVerifier; environment: "Production" | "Sandbox" };
  owner(
    originalTransactionId: string,
    environment: string,
  ): Promise<string | null>;
  apply(
    userId: string,
    transaction: VerifiedAppleTransaction,
    notification?: { id: string; type: string },
  ): Promise<void>;
}

export function purchaseVerifyHandler(dependencies: AppleHandlerDependencies) {
  return async (request: Request): Promise<Response> => {
    const method = methodResponse(request);
    if (method) return method;
    try {
      const body = await readSignedBody(
        request,
        "signedTransaction",
        MAX_SIGNED_TRANSACTION_BYTES,
      );
      const user = await dependencies.authenticate(request);
      if (user.isAnonymous || !isAccountId(user.id)) {
        throw new AppleStoreError(
          403,
          "ACCOUNT_REQUIRED",
          "Sign in to purchase or restore discovery credits",
        );
      }
      const wallet = await dependencies.wallet(user);
      // Sales flags hide offers, but cannot strand a transaction Apple already
      // charged (including one that completed while the storefront was paused).
      // Missing Apple configuration still fails closed in dependencies.apple().
      const { verifier, environment } = dependencies.apple();
      const submitted = normalizeAppleTransaction(
        await verifier.transaction(body),
        environment,
      );
      requireAccount(submitted.appAccountToken, user.id);
      if (
        submitted.productId !== DISCOVERY_PASS_PRODUCT && !wallet.proEnabled
      ) {
        const owner = await dependencies.owner(
          submitted.originalTransactionId,
          environment,
        );
        if (!owner) {
          throw new AppleStoreError(
            422,
            "PRODUCT_UNAVAILABLE",
            "This product is unavailable",
          );
        }
        requireAccount(submitted.appAccountToken, owner);
      }
      // A valid old JWS alone cannot prove a purchase is still unrefunded.
      const current = normalizeAppleTransaction(
        await verifier.currentTransaction(submitted.transactionId),
        environment,
      );
      requireSameTransaction(submitted, current);
      requireAccount(current.appAccountToken, user.id);
      await dependencies.apply(user.id, current);
      return json({ wallet: await dependencies.wallet(user) });
    } catch (error) {
      return errorResponse(error);
    }
  };
}

// Types that may carry transaction state. Unknown future events are acknowledged
// after Apple signature verification without changing entitlements.
const STATE_NOTIFICATIONS = new Set([
  "ONE_TIME_CHARGE",
  "SUBSCRIBED",
  "DID_RENEW",
  "DID_CHANGE_RENEWAL_PREF",
  "DID_CHANGE_RENEWAL_STATUS",
  "OFFER_REDEEMED",
  "EXPIRED",
  "DID_FAIL_TO_RENEW",
  "GRACE_PERIOD_EXPIRED",
  "PRICE_INCREASE",
  "REFUND",
  "REFUND_DECLINED",
  "RENEWAL_EXTENDED",
  "REVOKE",
  "REFUND_REVERSED",
  "METADATA_UPDATE",
]);

export function appStoreNotificationHandler(
  dependencies: AppleHandlerDependencies,
) {
  return async (request: Request): Promise<Response> => {
    const method = methodResponse(request);
    if (method) return method;
    try {
      const body = await readSignedBody(
        request,
        "signedPayload",
        MAX_SIGNED_NOTIFICATION_BYTES,
      );
      const { verifier, environment } = dependencies.apple();
      const notification = await verifier.notification(body);
      if (
        notification.version !== "2.0" ||
        !isAccountId(notification.notificationUUID) ||
        typeof notification.notificationType !== "string"
      ) throw invalidTransaction();
      timestamp(notification.signedDate, Date.now());
      // TEST and informational notifications still require a verified Apple JWS.
      if (!STATE_NOTIFICATIONS.has(notification.notificationType)) {
        return json({ received: true });
      }
      const data = notification.data;
      if (!data?.signedTransactionInfo) throw invalidTransaction();
      const transaction = normalizeAppleTransaction(
        await verifier.transaction(data.signedTransactionInfo),
        environment,
      );
      if (
        (notification.notificationType === "REFUND" ||
          notification.notificationType === "REVOKE") &&
        transaction.revokedAt === null
      ) throw invalidTransaction();
      if (data.signedRenewalInfo) {
        const renewal = await verifier.renewal(data.signedRenewalInfo);
        if (
          renewal.environment !== environment ||
          renewal.originalTransactionId !== transaction.originalTransactionId ||
          renewal.productId !== transaction.productId ||
          (renewal.appAccountToken !== undefined &&
            renewal.appAccountToken.toLowerCase() !==
              transaction.appAccountToken)
        ) throw invalidTransaction();
        timestamp(renewal.signedDate, Date.now());
      }
      const owner = await dependencies.owner(
        transaction.originalTransactionId,
        environment,
      );
      if (!owner) {
        // The authenticated purchase endpoint establishes ownership. A signed
        // token in an unsolicited notification cannot bind a new account.
        return json({ received: true });
      }
      requireAccount(transaction.appAccountToken, owner);
      // Independent of the purchase rollout flag: refunds and expiry must keep
      // working during a storefront outage or after purchases are disabled.
      await dependencies.apply(owner, transaction, {
        id: notification.notificationUUID,
        type: notification.notificationType,
      });
      return json({ received: true });
    } catch (error) {
      return errorResponse(error);
    }
  };
}

function requireAccount(token: string, userId: string): void {
  if (!isAccountId(userId) || token.toLowerCase() !== userId.toLowerCase()) {
    throw new AppleStoreError(
      403,
      "PURCHASE_ACCOUNT_MISMATCH",
      "This purchase belongs to another account",
    );
  }
}

function methodResponse(request: Request): Response | null {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json(
      { error: "Use POST for this endpoint", code: "METHOD_NOT_ALLOWED" },
      405,
      { Allow: "POST, OPTIONS" },
    );
  }
  return null;
}

export async function readSignedBody(
  request: Request,
  key: string,
  limit: number,
): Promise<string> {
  const invalid = () =>
    new AppleStoreError(
      400,
      "INVALID_REQUEST",
      `A ${key} JSON string is required`,
    );
  const oversized = () =>
    new AppleStoreError(413, "PAYLOAD_TOO_LARGE", "The request is too large");
  const type = request.headers.get("content-type")?.split(";")[0].trim()
    .toLowerCase();
  if (type !== "application/json" || request.headers.has("content-encoding")) {
    throw invalid();
  }
  const contentLength = request.headers.get("content-length");
  const bodyLimit = limit + 256;
  if (contentLength !== null) {
    if (!/^[0-9]+$/.test(contentLength)) throw invalid();
    if (Number(contentLength) > bodyLimit) throw oversized();
  }
  if (!request.body) throw invalid();
  const reader = request.body.getReader();
  let length = 0;
  const chunks: Uint8Array[] = [];
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => {
        void reader.cancel().catch(() => {});
        reject(
          new AppleStoreError(408, "REQUEST_TIMEOUT", "The request timed out"),
        );
      }, 5_000);
    });
    for (;;) {
      const { done, value } = await Promise.race([reader.read(), timeout]);
      if (done) break;
      length += value.byteLength;
      if (length > bodyLimit) {
        void reader.cancel().catch(() => {});
        throw oversized();
      }
      chunks.push(value);
    }
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    reader.releaseLock();
  }
  try {
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    const body = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (
      !body || typeof body !== "object" || Array.isArray(body) ||
      Object.keys(body).length !== 1 || typeof body[key] !== "string" ||
      !body[key]
    ) throw invalid();
    if (body[key].length > limit) throw oversized();
    return body[key];
  } catch (error) {
    if (error instanceof AppleStoreError) throw error;
    throw invalid();
  }
}

function json(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      ...extraHeaders,
    },
  });
}

function errorResponse(error: unknown): Response {
  if (error instanceof AppleStoreError) {
    return json({ error: error.message, code: error.code }, error.status);
  }
  const authOrWallet = paidAPIAccessErrorResponse(error, corsHeaders, {
    "Cache-Control": "no-store",
  });
  if (authOrWallet) return authOrWallet;
  // Never log exception messages: library/API errors can contain signed payloads.
  console.error(JSON.stringify({ event: "apple_store_request_failed" }));
  return json({
    error: "Purchase verification is temporarily unavailable",
    code: "PURCHASE_VERIFICATION_UNAVAILABLE",
  }, 503);
}
