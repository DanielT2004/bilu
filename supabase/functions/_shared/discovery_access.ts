import { PaidAPIAccessError } from "./paid_api_guard.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

export async function consumeDiscoveryAccess(
  userId: string,
  rewardToken: string | null,
): Promise<"free" | "rewarded"> {
  let response: Response;
  try {
    response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/consume_discovery_access`,
      {
        method: "POST",
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          p_user_id: userId,
          p_reward_token: rewardToken || null,
          p_daily_free_limit: 1,
        }),
        signal: AbortSignal.timeout(5_000),
      },
    );
  } catch {
    throw new PaidAPIAccessError(
      503,
      "DISCOVERY_ACCESS_UNAVAILABLE",
      "Discovery access is temporarily unavailable",
    );
  }

  if (!response.ok) {
    console.error(JSON.stringify({
      event: "discovery_access_rpc_failed",
      status: response.status,
    }));
    throw new PaidAPIAccessError(
      503,
      "DISCOVERY_ACCESS_UNAVAILABLE",
      "Discovery access is temporarily unavailable",
    );
  }

  const rows = await response.json() as Array<{
    allowed: boolean;
    access_source: "free" | "rewarded" | "required";
  }>;
  const result = rows[0];
  if (!result?.allowed) {
    throw new PaidAPIAccessError(
      402,
      "REWARDED_AD_REQUIRED",
      "Watch a rewarded ad to unlock another discovery",
    );
  }
  return result.access_source === "rewarded" ? "rewarded" : "free";
}

export async function refundDiscoveryAccess(
  userId: string,
  accessSource: "free" | "rewarded",
  rewardToken: string | null,
  timeoutMs = 5_000,
): Promise<boolean> {
  try {
    const response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/refund_discovery_access`,
      {
        method: "POST",
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          p_user_id: userId,
          p_access_source: accessSource,
          p_reward_token: rewardToken || null,
        }),
        signal: AbortSignal.timeout(timeoutMs),
      },
    );
    if (!response.ok) {
      console.error(JSON.stringify({
        event: "discovery_access_refund_failed",
        status: response.status,
      }));
      return false;
    }
    return await response.json() === true;
  } catch {
    console.error(
      JSON.stringify({ event: "discovery_access_refund_unavailable" }),
    );
    return false;
  }
}
