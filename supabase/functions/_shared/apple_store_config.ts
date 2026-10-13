import { createPrivateKey } from "node:crypto";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class AppleStoreError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "AppleStoreError";
  }
}

export interface AppleStoreConfig {
  environment: "Production" | "Sandbox";
  appAppleId: number;
  issuerId: string;
  keyId: string;
  privateKey: string;
}

export function appleUnavailable(): AppleStoreError {
  return new AppleStoreError(
    503,
    "PURCHASE_VERIFICATION_UNAVAILABLE",
    "Purchase verification is temporarily unavailable",
  );
}

export function isAccountId(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

// No default environment and no Xcode/LocalTesting option: Apple's library
// deliberately skips signatures for those environments, so never select them.
export function loadAppleStoreConfig(
  read: (key: string) => string | undefined = Deno.env.get,
): AppleStoreConfig {
  const environment = read("BILU_APP_STORE_ENVIRONMENT");
  const appId = read("BILU_APPLE_APP_ID") ?? "";
  const issuerId = read("APP_STORE_ISSUER_ID") ?? "";
  const keyId = read("APP_STORE_KEY_ID") ?? "";
  const privateKey = (read("APP_STORE_PRIVATE_KEY_P8") ?? "").replace(
    /\\n/g,
    "\n",
  );
  if (
    (environment !== "Production" && environment !== "Sandbox") ||
    !/^[1-9][0-9]{0,15}$/.test(appId) ||
    !Number.isSafeInteger(Number(appId)) || !isAccountId(issuerId) ||
    !/^[A-Z0-9]{10}$/.test(keyId) || privateKey.length > 8_192
  ) throw appleUnavailable();
  try {
    const key = createPrivateKey(privateKey);
    if (
      key.asymmetricKeyType !== "ec" ||
      key.asymmetricKeyDetails?.namedCurve !== "prime256v1"
    ) throw appleUnavailable();
  } catch {
    throw appleUnavailable();
  }
  return {
    environment,
    appAppleId: Number(appId),
    issuerId,
    keyId,
    privateKey,
  };
}

/** Configuration readiness has no network calls and never exposes secret values. */
export function appleStoreConfigurationReady(
  read: (key: string) => string | undefined = Deno.env.get,
): boolean {
  try {
    loadAppleStoreConfig(read);
    return true;
  } catch {
    return false;
  }
}
