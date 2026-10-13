import {
  type AuthenticatedUser,
  paidAPIAccessErrorResponse,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";

export interface RewardedAccessDependencies {
  authenticate(req: Request): Promise<AuthenticatedUser>;
  /** PostgREST call with the service-role key. */
  database(path: string, init?: RequestInit): Promise<Response>;
  env(name: string): string | undefined;
  now(): Date;
}

export const rewardedAccessDependencies: RewardedAccessDependencies = {
  authenticate: requireAuthenticatedUser,
  database: serviceDatabase,
  env: (name) => Deno.env.get(name),
  now: () => new Date(),
};
const KEY_SERVER = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

let cachedKeys: { expiresAt: number; keys: Map<number, string> } | null = null;

export async function handleRewardedAccess(
  req: Request,
  deps: RewardedAccessDependencies = rewardedAccessDependencies,
): Promise<Response> {
  const database = deps.database;
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method === "GET") return await handleSSV(req, deps);
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const user = await deps.authenticate(req);
    const body = await req.json() as { action?: string; token?: string };
    if (body.action === "create") {
      const token = crypto.randomUUID();
      const response = await database("rewarded_ad_sessions", {
        method: "POST",
        headers: { "Prefer": "return=minimal" },
        body: JSON.stringify({ token, user_id: user.id }),
      });
      if (!response.ok) throw new Error("reward session insert failed");
      return json({ token, userId: user.id });
    }

    if (body.action === "status" && isUUID(body.token)) {
      const response = await database(
        `rewarded_ad_sessions?select=verified_at,consumed_at&token=eq.${body.token}&user_id=eq.${user.id}`,
      );
      if (!response.ok) throw new Error("reward session lookup failed");
      const rows = await response.json() as Array<{
        verified_at: string | null;
        consumed_at: string | null;
      }>;
      return json({
        verified: Boolean(rows[0]?.verified_at),
        consumed: Boolean(rows[0]?.consumed_at),
      });
    }

    // Debug builds play Google's sample ad unit, which never sends an SSV
    // callback. Accounts listed in REWARD_DEBUG_USER_IDS may verify their own
    // session instead; it is then consumed exactly like a real reward. Unset
    // means disabled, so production users can never reach this path.
    if (body.action === "debug-verify" && isUUID(body.token)) {
      if (!debugRewardUserIDs(deps).has(user.id.toLowerCase())) {
        return json(
          { error: "Debug rewards are not enabled for this account" },
          403,
        );
      }
      const response = await database(
        `rewarded_ad_sessions?token=eq.${body.token}&user_id=eq.${user.id}&verified_at=is.null&consumed_at=is.null&expires_at=gt.${
          encodeURIComponent(deps.now().toISOString())
        }`,
        {
          method: "PATCH",
          headers: { "Prefer": "return=representation" },
          body: JSON.stringify({
            verified_at: deps.now().toISOString(),
            transaction_id: `debug-${body.token}`,
            reward_amount: 1,
            ad_unit: "debug",
          }),
        },
      );
      if (!response.ok) throw new Error("debug reward update failed");
      const updated = await response.json() as unknown[];
      if (updated.length !== 1) return json({ error: "Unknown reward" }, 404);
      console.log(JSON.stringify({ event: "rewarded_access_debug_verified" }));
      return json({ verified: true });
    }

    return json({ error: "Invalid action" }, 400);
  } catch (error) {
    const authResponse = paidAPIAccessErrorResponse(error, corsHeaders);
    if (authResponse) return authResponse;
    console.error(JSON.stringify({ event: "rewarded_access_error" }));
    return json({ error: "Reward service is temporarily unavailable" }, 503);
  }
}

async function handleSSV(
  req: Request,
  deps: RewardedAccessDependencies,
): Promise<Response> {
  const database = deps.database;
  const url = new URL(req.url);
  const rawQuery = url.search.slice(1);
  const signatureMarker = "&signature=";
  const signatureIndex = rawQuery.indexOf(signatureMarker);
  const params = url.searchParams;
  const signature = params.get("signature");
  const keyID = Number(params.get("key_id"));
  const token = params.get("custom_data");
  const userID = params.get("user_id");
  const transactionID = params.get("transaction_id");
  const timestamp = Number(params.get("timestamp"));
  const rewardAmount = Number(params.get("reward_amount"));
  const adUnit = params.get("ad_unit");

  if (
    signatureIndex < 0 || !signature || !Number.isInteger(keyID) ||
    !isUUID(token) || !isUUID(userID) || !transactionID ||
    !Number.isFinite(timestamp) ||
    Math.abs(Date.now() - timestamp) > 86_400_000 ||
    !Number.isInteger(rewardAmount) || rewardAmount < 1
  ) {
    return new Response("invalid callback", { status: 400 });
  }

  // Fail closed if production has not been configured. Accepting a callback
  // from any valid AdMob unit would let a different publisher's rewarded ad
  // unlock Bilu discoveries.
  const configuredAdUnit = deps.env("ADMOB_REWARDED_AD_UNIT_ID")?.trim();
  if (!configuredAdUnit) {
    console.error(JSON.stringify({ event: "rewarded_ad_unit_not_configured" }));
    return new Response("reward service not configured", { status: 503 });
  }
  // AdMob's SSV callback sends only the numeric ad-unit component, even
  // though the SDK is configured with the full ca-app-pub-…/… identifier.
  const expectedAdUnit = configuredAdUnit.split("/").at(-1);

  const signedContent = rawQuery.slice(0, signatureIndex);
  const verified = await verifySignature(signedContent, signature, keyID);
  if (!verified) return new Response("invalid signature", { status: 400 });

  // AdMob's dashboard verifier signs a callback with this documented sample
  // unit. Acknowledge it only after signature validation, and never grant or
  // mutate a reward session for it.
  if (adUnit === "1234567890") return new Response("ok", { status: 200 });
  if (adUnit !== expectedAdUnit) {
    return new Response("wrong ad unit", { status: 400 });
  }

  const response = await database(
    `rewarded_ad_sessions?token=eq.${token}&user_id=eq.${userID}&consumed_at=is.null&expires_at=gt.${
      encodeURIComponent(new Date().toISOString())
    }`,
    {
      method: "PATCH",
      headers: { "Prefer": "return=representation" },
      body: JSON.stringify({
        verified_at: new Date().toISOString(),
        transaction_id: transactionID,
        reward_amount: rewardAmount,
        ad_unit: adUnit,
      }),
    },
  );
  if (!response.ok) return new Response("reward rejected", { status: 400 });
  const updated = await response.json() as unknown[];
  if (updated.length !== 1) {
    return new Response("unknown reward", { status: 404 });
  }
  return new Response("ok", { status: 200 });
}

async function verifySignature(
  content: string,
  encodedSignature: string,
  keyID: number,
): Promise<boolean> {
  const keys = await admobKeys();
  const base64Key = keys.get(keyID);
  if (!base64Key) return false;
  try {
    const key = await crypto.subtle.importKey(
      "spki",
      asArrayBuffer(decodeBase64(base64Key)),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["verify"],
    );
    return await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      asArrayBuffer(derToP1363(decodeBase64URL(encodedSignature), 32)),
      new TextEncoder().encode(content),
    );
  } catch {
    return false;
  }
}

async function admobKeys(): Promise<Map<number, string>> {
  if (cachedKeys && cachedKeys.expiresAt > Date.now()) return cachedKeys.keys;
  const response = await fetch(KEY_SERVER, {
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) throw new Error("AdMob key fetch failed");
  const payload = await response.json() as {
    keys?: Array<{ keyId: number; base64: string }>;
  };
  const keys = new Map(
    (payload.keys ?? []).map((key) => [key.keyId, key.base64]),
  );
  cachedKeys = { expiresAt: Date.now() + 23 * 60 * 60 * 1_000, keys };
  return keys;
}

function derToP1363(der: Uint8Array, size: number): Uint8Array {
  let offset = 0;
  if (der[offset++] !== 0x30) throw new Error("invalid DER sequence");
  const sequenceLength = readDERLength(der, offset);
  offset = sequenceLength.offset;
  if (der[offset++] !== 0x02) throw new Error("invalid DER integer");
  const rLength = readDERLength(der, offset);
  offset = rLength.offset;
  const r = der.slice(offset, offset + rLength.length);
  offset += rLength.length;
  if (der[offset++] !== 0x02) throw new Error("invalid DER integer");
  const sLength = readDERLength(der, offset);
  offset = sLength.offset;
  const s = der.slice(offset, offset + sLength.length);

  const output = new Uint8Array(size * 2);
  copyInteger(r, output, 0, size);
  copyInteger(s, output, size, size);
  return output;
}

function readDERLength(data: Uint8Array, offset: number) {
  const first = data[offset++];
  if ((first & 0x80) === 0) return { length: first, offset };
  const count = first & 0x7f;
  if (count < 1 || count > 2) throw new Error("invalid DER length");
  let length = 0;
  for (let i = 0; i < count; i++) length = (length << 8) | data[offset++];
  return { length, offset };
}

function copyInteger(
  value: Uint8Array,
  output: Uint8Array,
  start: number,
  size: number,
) {
  let normalized = value;
  while (normalized.length > 1 && normalized[0] === 0) {
    normalized = normalized.slice(1);
  }
  if (normalized.length > size) throw new Error("DER integer too large");
  output.set(normalized, start + size - normalized.length);
}

function decodeBase64(value: string): Uint8Array {
  return Uint8Array.from(
    atob(value.replace(/\s/g, "")),
    (char) => char.charCodeAt(0),
  );
}

function decodeBase64URL(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/") +
    "=".repeat((4 - value.length % 4) % 4);
  return decodeBase64(base64);
}

function asArrayBuffer(value: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return copy.buffer;
}

function debugRewardUserIDs(deps: RewardedAccessDependencies): Set<string> {
  return new Set(
    (deps.env("REWARD_DEBUG_USER_IDS") ?? "")
      .split(",")
      .map((id) => id.trim().toLowerCase())
      .filter(isUUID),
  );
}

function isUUID(value: string | null | undefined): value is string {
  return Boolean(
    value &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(value),
  );
}

function serviceDatabase(path: string, init: RequestInit = {}) {
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const headers = new Headers(init.headers);
  headers.set("apikey", serviceKey);
  headers.set("Authorization", `Bearer ${serviceKey}`);
  headers.set("Content-Type", "application/json");
  return fetch(`${supabaseURL}/rest/v1/${path}`, { ...init, headers });
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
