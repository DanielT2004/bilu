import {
  type AuthenticatedUser,
  PaidAPIAccessError,
} from "./paid_api_guard.ts";
import {
  commerceEnvironmentEnabled,
  type DiscoveryKind,
  proEnvironmentEnabled,
} from "./purchase_catalog.ts";
import { appleStoreConfigurationReady } from "./apple_store_config.ts";

export type { DiscoveryKind } from "./purchase_catalog.ts";

export interface PurchaseWallet {
  accountId: string;
  requiresSignIn: boolean;
  appAccountToken: string;
  plan: "free" | "pro";
  periodStart: string;
  periodEnd: string;
  included: { explore: number; tiktok: number };
  purchased: { explore: number; tiktok: number };
  commerceEnabled: boolean;
  proEnabled: boolean;
}

export interface DiscoveryReservation {
  discoveryId: string;
  kind: DiscoveryKind;
  status:
    | "reserved"
    | "committed"
    | "released"
    | "expired"
    | "revoked"
    | "missing";
  source: "included" | "purchased" | null;
  acquired: boolean;
  result?: unknown;
  expiresAt?: string;
  resultExpiresAt?: string;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function unavailable(): PaidAPIAccessError {
  return new PaidAPIAccessError(
    503,
    "WALLET_UNAVAILABLE",
    "Discovery access is temporarily unavailable",
  );
}

/** Service-role RPCs only; no client token, arbitrary account, or quantity is
 * forwarded by any public wallet endpoint. Callers establish identity first. */
export async function purchaseWalletRPC<T>(
  name: string,
  params: Record<string, unknown>,
): Promise<T> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) throw unavailable();
  let response: Response;
  try {
    response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(params),
      signal: AbortSignal.timeout(5_000),
    });
  } catch {
    throw unavailable();
  }
  if (!response.ok) {
    // Never log account IDs, purchase tokens, transaction claims, or DB bodies.
    console.error(JSON.stringify({
      event: "purchase_wallet_rpc_failed",
      rpc: name,
      status: response.status,
    }));
    throw unavailable();
  }
  try {
    return await response.json() as T;
  } catch {
    throw unavailable();
  }
}

function validBalance(
  value: unknown,
): value is { explore: number; tiktok: number } {
  const balance = value as { explore?: unknown; tiktok?: unknown } | null;
  return balance !== null && typeof balance === "object" &&
    typeof balance.explore === "number" &&
    Number.isSafeInteger(balance.explore) &&
    balance.explore >= 0 && typeof balance.tiktok === "number" &&
    Number.isSafeInteger(balance.tiktok) && balance.tiktok >= 0;
}

export async function getPurchaseWallet(
  user: AuthenticatedUser,
): Promise<PurchaseWallet> {
  const wallet = await purchaseWalletRPC<
    PurchaseWallet & { appleEnvironment?: string }
  >(
    "purchase_wallet_snapshot",
    { p_user_id: user.id },
  );
  if (
    !wallet || wallet.accountId !== user.id ||
    wallet.appAccountToken !== user.id ||
    !["free", "pro"].includes(wallet.plan) ||
    typeof wallet.requiresSignIn !== "boolean" ||
    typeof wallet.commerceEnabled !== "boolean" ||
    typeof wallet.proEnabled !== "boolean" ||
    !Number.isFinite(Date.parse(wallet.periodStart)) ||
    !Number.isFinite(Date.parse(wallet.periodEnd)) ||
    !validBalance(wallet.included) || !validBalance(wallet.purchased)
  ) throw unavailable();
  const { appleEnvironment, ...publicWallet } = wallet;
  const commerceEnabled = commerceEnvironmentEnabled() &&
    wallet.commerceEnabled &&
    appleStoreConfigurationReady() &&
    appleEnvironment === Deno.env.get("BILU_APP_STORE_ENVIRONMENT");
  return {
    ...publicWallet,
    periodStart: new Date(wallet.periodStart).toISOString(),
    periodEnd: new Date(wallet.periodEnd).toISOString(),
    requiresSignIn: user.isAnonymous || wallet.requiresSignIn,
    commerceEnabled,
    proEnabled: commerceEnabled && proEnvironmentEnabled() && wallet.proEnabled,
  };
}

async function discoveryAction(
  userId: string,
  discoveryId: string,
  kind: DiscoveryKind,
  action: "reserve" | "read" | "commit" | "release",
  result?: unknown,
): Promise<DiscoveryReservation> {
  if (
    !UUID_PATTERN.test(userId) || !UUID_PATTERN.test(discoveryId) ||
    (kind !== "explore" && kind !== "tiktok")
  ) {
    throw new PaidAPIAccessError(
      400,
      "INVALID_DISCOVERY",
      "A valid discovery identifier and kind are required",
    );
  }
  if (action === "reserve" && !commerceEnvironmentEnabled()) {
    throw new PaidAPIAccessError(
      503,
      "COMMERCE_UNAVAILABLE",
      "Discovery purchases are not available yet",
    );
  }
  const reservation = await purchaseWalletRPC<
    Omit<DiscoveryReservation, "status"> & {
      status:
        | DiscoveryReservation["status"]
        | "exhausted"
        | "environment_mismatch";
    }
  >("purchase_discovery", {
    p_user_id: userId,
    p_discovery_id: discoveryId,
    p_kind: kind,
    p_action: action,
    ...(action === "commit" ? { p_result: result } : {}),
  });
  if (
    !reservation || reservation.discoveryId !== discoveryId ||
    reservation.kind !== kind || typeof reservation.acquired !== "boolean" ||
    ![
      "reserved",
      "committed",
      "released",
      "expired",
      "revoked",
      "missing",
      "exhausted",
      "environment_mismatch",
    ].includes(reservation.status) ||
    !["included", "purchased", null].includes(reservation.source)
  ) throw unavailable();
  if (reservation.status === "environment_mismatch") {
    throw new PaidAPIAccessError(
      409,
      "DISCOVERY_ENVIRONMENT_MISMATCH",
      "This discovery belongs to a different App Store environment",
    );
  }
  if (reservation.status === "exhausted") {
    throw new PaidAPIAccessError(
      402,
      "DISCOVERY_CREDITS_REQUIRED",
      "This discovery needs an available allowance or a Discovery Pass",
    );
  }
  return reservation as DiscoveryReservation;
}

export function reserveDiscovery(
  userId: string,
  discoveryId: string,
  kind: DiscoveryKind,
): Promise<DiscoveryReservation> {
  return discoveryAction(userId, discoveryId, kind, "reserve");
}

export function readDiscovery(
  userId: string,
  discoveryId: string,
  kind: DiscoveryKind,
): Promise<DiscoveryReservation> {
  return discoveryAction(userId, discoveryId, kind, "read");
}

export function commitDiscovery(
  userId: string,
  discoveryId: string,
  kind: DiscoveryKind,
  result: unknown,
): Promise<DiscoveryReservation> {
  return discoveryAction(userId, discoveryId, kind, "commit", result);
}

export function releaseDiscovery(
  userId: string,
  discoveryId: string,
  kind: DiscoveryKind,
): Promise<DiscoveryReservation> {
  return discoveryAction(userId, discoveryId, kind, "release");
}
