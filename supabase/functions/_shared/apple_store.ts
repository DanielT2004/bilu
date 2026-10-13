import { Buffer } from "node:buffer";
import { createHash } from "node:crypto";
import {
  AppStoreServerAPIClient,
  Environment,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "npm:@apple/app-store-server-library@3.1.0";
import {
  type AppleStoreConfig,
  AppleStoreError,
  appleUnavailable,
  isAccountId,
} from "./apple_store_config.ts";
export {
  type AppleStoreConfig,
  AppleStoreError,
  appleUnavailable,
  isAccountId,
  loadAppleStoreConfig,
} from "./apple_store_config.ts";
import { APPLE_ROOT_CERTIFICATES } from "./apple_store_roots.ts";

export const APPLE_BUNDLE_ID = "com.simonsoloman.bilu";
export const DISCOVERY_PASS_PRODUCT = `${APPLE_BUNDLE_ID}.discovery_pass`;
export const PRO_PRODUCTS = new Set([
  `${APPLE_BUNDLE_ID}.pro.monthly`,
  `${APPLE_BUNDLE_ID}.pro.annual`,
]);
export const MAX_SIGNED_TRANSACTION_BYTES = 24_000;
export const MAX_SIGNED_NOTIFICATION_BYTES = 96_000;
const CLOCK_SKEW_MS = 60_000;
export function invalidTransaction(): AppleStoreError {
  return new AppleStoreError(
    422,
    "INVALID_TRANSACTION",
    "The App Store transaction could not be verified",
  );
}

export interface AppleVerifier {
  transaction(signed: string): Promise<JWSTransactionDecodedPayload>;
  notification(signed: string): Promise<ResponseBodyV2DecodedPayload>;
  renewal(signed: string): Promise<JWSRenewalInfoDecodedPayload>;
  currentTransaction(
    transactionId: string,
  ): Promise<JWSTransactionDecodedPayload>;
}

export function assertCompactJWS(
  value: unknown,
  maxBytes: number,
): asserts value is string {
  if (
    typeof value !== "string" || value.length > maxBytes ||
    !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(value)
  ) throw invalidTransaction();
  try {
    // Inspect only the header to restrict the algorithm. Claims are never read
    // before SignedDataVerifier authenticates the complete certificate chain.
    const header = JSON.parse(
      Buffer.from(value.split(".")[0], "base64url").toString(),
    );
    if (
      header.alg !== "ES256" || header.crit !== undefined ||
      !Array.isArray(header.x5c) || header.x5c.length !== 3 ||
      header.x5c.some((cert: unknown) =>
        typeof cert !== "string" || cert.length > 8_192 ||
        !/^[A-Za-z0-9+/]+={0,2}$/.test(cert)
      )
    ) throw invalidTransaction();
  } catch {
    throw invalidTransaction();
  }
}

export function createAppleVerifier(config: AppleStoreConfig): AppleVerifier {
  const roots = APPLE_ROOT_CERTIFICATES.map((certificate) => {
    const der = Buffer.from(certificate.derBase64, "base64");
    if (createHash("sha256").update(der).digest("hex") !== certificate.sha256) {
      throw appleUnavailable();
    }
    return der;
  });
  const environment = config.environment === "Production"
    ? Environment.PRODUCTION
    : Environment.SANDBOX;
  const verifier = new SignedDataVerifier(
    roots,
    true, // Check certificate expiry now AND online certificate revocation.
    environment,
    APPLE_BUNDLE_ID,
    config.appAppleId,
  );
  const client = new AppStoreServerAPIClient(
    config.privateKey,
    config.keyId,
    config.issuerId,
    APPLE_BUNDLE_ID,
    environment,
  );
  const verified = async <T>(
    signed: string,
    limit: number,
    decode: () => Promise<T>,
  ): Promise<T> => {
    assertCompactJWS(signed, limit);
    try {
      return await bounded(decode(), 35_000);
    } catch (error) {
      if (error instanceof AppleStoreError) throw error;
      if (
        error instanceof VerificationException &&
        error.status !== VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
      ) throw invalidTransaction();
      throw appleUnavailable();
    }
  };
  const transaction = (signed: string) =>
    verified(
      signed,
      MAX_SIGNED_TRANSACTION_BYTES,
      () => verifier.verifyAndDecodeTransaction(signed),
    );
  return {
    transaction,
    notification: (signed) =>
      verified(
        signed,
        MAX_SIGNED_NOTIFICATION_BYTES,
        () => verifier.verifyAndDecodeNotification(signed),
      ),
    renewal: (signed) =>
      verified(
        signed,
        MAX_SIGNED_TRANSACTION_BYTES,
        () => verifier.verifyAndDecodeRenewalInfo(signed),
      ),
    currentTransaction: async (id) => {
      let response;
      try {
        response = await bounded(client.getTransactionInfo(id), 15_000);
      } catch {
        // Don't expose Apple's response, signed data, credentials or identifiers.
        throw appleUnavailable();
      }
      if (!response.signedTransactionInfo) throw appleUnavailable();
      return await transaction(response.signedTransactionInfo);
    },
  };
}

async function bounded<T>(work: Promise<T>, milliseconds: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      work,
      new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(appleUnavailable()), milliseconds);
      }),
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

export interface VerifiedAppleTransaction {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  environment: "Production" | "Sandbox";
  appAccountToken: string;
  signedAt: string;
  purchasedAt: string;
  expiresAt: string | null;
  revokedAt: string | null;
}

export function normalizeAppleTransaction(
  transaction: JWSTransactionDecodedPayload,
  environment: "Production" | "Sandbox",
  now = Date.now(),
): VerifiedAppleTransaction {
  const isPass = transaction.productId === DISCOVERY_PASS_PRODUCT;
  if (!isPass && !PRO_PRODUCTS.has(transaction.productId ?? "")) {
    throw new AppleStoreError(
      422,
      "PRODUCT_UNAVAILABLE",
      "This product is unavailable",
    );
  }
  if (
    transaction.bundleId !== APPLE_BUNDLE_ID ||
    transaction.environment !== environment ||
    !/^[0-9]{1,64}$/.test(transaction.transactionId ?? "") ||
    !/^[0-9]{1,64}$/.test(transaction.originalTransactionId ?? "") ||
    !isAccountId(transaction.appAccountToken) ||
    transaction.inAppOwnershipType !== "PURCHASED" ||
    transaction.quantity !== 1 ||
    transaction.type !==
      (isPass ? "Consumable" : "Auto-Renewable Subscription") ||
    transaction.advancedCommerceInfo !== undefined ||
    transaction.billingPlanType !== undefined ||
    transaction.commitmentInfo !== undefined
  ) throw invalidTransaction();
  const signedAt = timestamp(transaction.signedDate, now);
  const purchasedAt = timestamp(transaction.purchaseDate, now);
  if (transaction.purchaseDate! > transaction.signedDate! + CLOCK_SKEW_MS) {
    throw invalidTransaction();
  }
  let expiresAt: string | null = null;
  if (isPass) {
    if (
      transaction.expiresDate !== undefined || transaction.isUpgraded === true
    ) {
      throw invalidTransaction();
    }
  } else {
    expiresAt = timestamp(transaction.expiresDate, Number.MAX_SAFE_INTEGER);
    if (transaction.expiresDate! <= transaction.purchaseDate!) {
      throw invalidTransaction();
    }
    if (transaction.isUpgraded) {
      expiresAt = new Date(
        Math.min(transaction.expiresDate!, transaction.signedDate!),
      ).toISOString();
    }
  }
  const revokedAt = transaction.revocationDate === undefined
    ? null
    : timestamp(transaction.revocationDate, now);
  if (
    transaction.revocationDate !== undefined &&
    (transaction.revocationDate < transaction.purchaseDate! ||
      transaction.revocationDate > transaction.signedDate! + CLOCK_SKEW_MS)
  ) throw invalidTransaction();
  if (transaction.revocationReason !== undefined && revokedAt === null) {
    throw invalidTransaction();
  }
  if (transaction.revocationType !== undefined && revokedAt === null) {
    throw invalidTransaction();
  }
  return {
    transactionId: transaction.transactionId!,
    originalTransactionId: transaction.originalTransactionId!,
    productId: transaction.productId!,
    environment,
    appAccountToken: transaction.appAccountToken!.toLowerCase(),
    signedAt,
    purchasedAt,
    expiresAt,
    revokedAt,
  };
}

export function timestamp(value: unknown, latest: number): string {
  if (
    typeof value !== "number" || !Number.isSafeInteger(value) || value <= 0 ||
    value > latest + CLOCK_SKEW_MS || value > 8_640_000_000_000_000
  ) throw invalidTransaction();
  return new Date(value).toISOString();
}

export function requireSameTransaction(
  submitted: VerifiedAppleTransaction,
  current: VerifiedAppleTransaction,
): void {
  for (
    const key of [
      "transactionId",
      "originalTransactionId",
      "productId",
      "environment",
      "appAccountToken",
      "purchasedAt",
    ] as const
  ) {
    if (submitted[key] !== current[key]) throw invalidTransaction();
  }
  // A lagging API response must not erase newer signed revocation information.
  // Refund reversals need a separate restoration policy; never silently grant.
  if (
    Date.parse(current.signedAt) < Date.parse(submitted.signedAt) ||
    (submitted.revokedAt !== null && current.revokedAt === null)
  ) throw appleUnavailable();
}
