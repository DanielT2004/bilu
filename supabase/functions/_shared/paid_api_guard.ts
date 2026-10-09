export interface PaidAPIQuotaPolicy {
  service: string;
  minuteLimit: number;
  dailyLimit: number;
  globalDailyLimit: number;
}

export interface AuthenticatedUser {
  id: string;
  isAnonymous: boolean;
}

export interface QuotaResult {
  allowed: boolean;
  retryAfterSeconds: number;
  minuteRemaining: number;
  dailyRemaining: number;
  globalDailyRemaining: number;
}

export class PaidAPIAccessError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly retryAfterSeconds = 0,
  ) {
    super(message);
    this.name = "PaidAPIAccessError";
  }
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  "";

export function quotaPolicy(
  service: string,
  environmentPrefix: string,
  defaultMinuteLimit: number,
  defaultDailyLimit: number,
  defaultGlobalDailyLimit: number,
): PaidAPIQuotaPolicy {
  return {
    service,
    minuteLimit: positiveIntegerEnvironment(
      `${environmentPrefix}_PER_MINUTE`,
      defaultMinuteLimit,
    ),
    dailyLimit: positiveIntegerEnvironment(
      `${environmentPrefix}_PER_DAY`,
      defaultDailyLimit,
    ),
    globalDailyLimit: positiveIntegerEnvironment(
      `${environmentPrefix}_GLOBAL_PER_DAY`,
      defaultGlobalDailyLimit,
    ),
  };
}

export async function requireAuthenticatedUser(
  req: Request,
): Promise<AuthenticatedUser> {
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    throw new PaidAPIAccessError(
      503,
      "AUTH_UNAVAILABLE",
      "Authentication is temporarily unavailable",
    );
  }

  const authorization = req.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) {
    throw new PaidAPIAccessError(
      401,
      "AUTH_REQUIRED",
      "A signed-in user session is required",
    );
  }

  // Validate with Supabase Auth instead of trusting decoded client claims. This
  // explicitly rejects the public project key, which is not a user session.
  let response: Response;
  try {
    response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: {
        "apikey": SUPABASE_SERVICE_ROLE_KEY,
        "Authorization": `Bearer ${match[1]}`,
      },
      signal: AbortSignal.timeout(5_000),
    });
  } catch {
    throw new PaidAPIAccessError(
      503,
      "AUTH_UNAVAILABLE",
      "Authentication is temporarily unavailable",
    );
  }

  if (!response.ok) {
    throw new PaidAPIAccessError(
      401,
      "INVALID_SESSION",
      "The user session is invalid or expired",
    );
  }

  const user = await response.json() as {
    id?: string;
    is_anonymous?: boolean;
  };
  if (!user.id) {
    throw new PaidAPIAccessError(
      401,
      "INVALID_SESSION",
      "The user session is invalid or expired",
    );
  }

  return { id: user.id, isAnonymous: user.is_anonymous === true };
}

export async function consumePaidAPIQuota(
  userId: string,
  policy: PaidAPIQuotaPolicy,
  costUnits = 1,
): Promise<QuotaResult> {
  const normalizedCost = Math.max(1, Math.ceil(costUnits));
  let response: Response;
  try {
    response = await fetch(
      `${SUPABASE_URL}/rest/v1/rpc/consume_paid_api_quota`,
      {
        method: "POST",
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          p_user_id: userId,
          p_service: policy.service,
          p_cost_units: normalizedCost,
          p_minute_limit: policy.minuteLimit,
          p_daily_limit: policy.dailyLimit,
          p_global_daily_limit: policy.globalDailyLimit,
        }),
        signal: AbortSignal.timeout(5_000),
      },
    );
  } catch {
    throw new PaidAPIAccessError(
      503,
      "QUOTA_UNAVAILABLE",
      "Usage limits are temporarily unavailable",
    );
  }

  if (!response.ok) {
    // The PostgREST body may contain database details. Keep production logs to
    // non-sensitive status metadata only.
    console.error(JSON.stringify({
      event: "paid_api_quota_rpc_failed",
      status: response.status,
    }));
    throw new PaidAPIAccessError(
      503,
      "QUOTA_UNAVAILABLE",
      "Usage limits are temporarily unavailable",
    );
  }

  const payload = await response.json() as Array<{
    allowed: boolean;
    retry_after_seconds: number;
    minute_remaining: number;
    daily_remaining: number;
    global_daily_remaining: number;
  }>;
  const row = payload[0];
  if (!row) {
    throw new PaidAPIAccessError(
      503,
      "QUOTA_UNAVAILABLE",
      "Usage limits are temporarily unavailable",
    );
  }

  const result: QuotaResult = {
    allowed: row.allowed,
    retryAfterSeconds: row.retry_after_seconds,
    minuteRemaining: row.minute_remaining,
    dailyRemaining: row.daily_remaining,
    globalDailyRemaining: row.global_daily_remaining,
  };
  if (!result.allowed) {
    const globallyExhausted = result.globalDailyRemaining === 0;
    console.warn(JSON.stringify({
      event: globallyExhausted
        ? "paid_api_budget_exhausted"
        : "paid_api_user_limit_reached",
      service: policy.service,
      globalDailyRemaining: result.globalDailyRemaining,
    }));
    throw new PaidAPIAccessError(
      429,
      globallyExhausted ? "GLOBAL_BUDGET_EXCEEDED" : "USAGE_LIMIT_EXCEEDED",
      globallyExhausted
        ? "The service has reached its daily budget"
        : "This account has reached its usage limit",
      result.retryAfterSeconds,
    );
  }
  logBudgetThresholdCrossing(policy, normalizedCost, result);
  return result;
}

function logBudgetThresholdCrossing(
  policy: PaidAPIQuotaPolicy,
  costUnits: number,
  result: QuotaResult,
) {
  const previousRemaining = result.globalDailyRemaining + costUnits;
  for (const percentage of [20, 10, 5]) {
    const threshold = Math.ceil(policy.globalDailyLimit * percentage / 100);
    if (
      previousRemaining > threshold && result.globalDailyRemaining <= threshold
    ) {
      console.warn(JSON.stringify({
        event: "paid_api_budget_warning",
        service: policy.service,
        percentageRemaining: percentage,
        globalDailyRemaining: result.globalDailyRemaining,
        globalDailyLimit: policy.globalDailyLimit,
      }));
    }
  }
}

export function quotaHeaders(result: QuotaResult): Record<string, string> {
  return {
    "X-RateLimit-Remaining": String(result.minuteRemaining),
    "X-Daily-Budget-Remaining": String(result.dailyRemaining),
    "X-Global-Daily-Budget-Remaining": String(result.globalDailyRemaining),
  };
}

export function paidAPIAccessErrorResponse(
  error: unknown,
  corsHeaders: Record<string, string>,
  responseHeaders: Record<string, string> = {},
): Response | null {
  if (!(error instanceof PaidAPIAccessError)) return null;
  const headers: Record<string, string> = {
    ...corsHeaders,
    ...responseHeaders,
    "Content-Type": "application/json",
  };
  if (error.retryAfterSeconds > 0) {
    headers["Retry-After"] = String(error.retryAfterSeconds);
  }
  return new Response(
    JSON.stringify({ error: error.message, code: error.code }),
    { status: error.status, headers },
  );
}

function positiveIntegerEnvironment(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name) ?? fallback);
  return Number.isInteger(value) && value > 0 ? value : fallback;
}
