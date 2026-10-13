import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handleRewardedAccess,
  type RewardedAccessDependencies,
} from "./handler.ts";
import { PaidAPIAccessError } from "../_shared/paid_api_guard.ts";

const DEBUG_USER = "11111111-1111-4111-8111-111111111111";
const OTHER_USER = "22222222-2222-4222-8222-222222222222";
const TOKEN = "33333333-3333-4333-8333-333333333333";
const NOW = new Date("2026-10-13T20:00:00.000Z");

interface SessionRow {
  token: string;
  user_id: string;
  verified_at: string | null;
  consumed_at: string | null;
  expires_at: string;
  transaction_id?: string;
}

/** A tiny PostgREST stand-in for rewarded_ad_sessions that applies the
 * eq / is.null / gt filters the function sends, so the tests check the
 * filters themselves rather than trusting them. */
function fakeDatabase(rows: SessionRow[], log: string[] = []) {
  return (path: string, init: RequestInit = {}): Promise<Response> => {
    log.push(`${init.method ?? "GET"} ${path}`);
    const [table, query = ""] = path.split("?");
    if (table !== "rewarded_ad_sessions") {
      return Promise.resolve(new Response("[]", { status: 404 }));
    }
    const filters = query.split("&").filter((part) =>
      part && !part.startsWith("select=")
    ).map((part) => {
      const [column, rest] = part.split("=");
      const [op, ...value] = rest.split(".");
      return { column, op, value: decodeURIComponent(value.join(".")) };
    });
    const matches = rows.filter((row) =>
      filters.every(({ column, op, value }) => {
        const field = (row as unknown as Record<string, string | null>)[column];
        if (op === "eq") return field === value;
        if (op === "is" && value === "null") return field === null;
        if (op === "gt") return field !== null && field > value;
        throw new Error(`unsupported filter ${column}=${op}.${value}`);
      })
    );
    if (init.method === "PATCH") {
      const patch = JSON.parse(String(init.body));
      for (const row of matches) Object.assign(row, patch);
    }
    return Promise.resolve(
      new Response(JSON.stringify(matches), { status: 200 }),
    );
  };
}

function deps(
  rows: SessionRow[],
  options: { allowlist?: string; userId?: string; log?: string[] } = {},
): RewardedAccessDependencies {
  return {
    authenticate: () =>
      Promise.resolve({ id: options.userId ?? DEBUG_USER, isAnonymous: true }),
    database: fakeDatabase(rows, options.log),
    env: (name) =>
      name === "REWARD_DEBUG_USER_IDS" ? options.allowlist : undefined,
    now: () => NOW,
  };
}

function session(overrides: Partial<SessionRow> = {}): SessionRow {
  return {
    token: TOKEN,
    user_id: DEBUG_USER,
    verified_at: null,
    consumed_at: null,
    expires_at: "2026-10-13T20:10:00.000Z",
    ...overrides,
  };
}

function debugVerify(token = TOKEN): Request {
  return new Request("https://local.test/rewarded-access", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ action: "debug-verify", token }),
  });
}

Deno.test("debug-verify is refused when the allowlist is unset", async () => {
  const rows = [session()];
  const log: string[] = [];
  const res = await handleRewardedAccess(debugVerify(), deps(rows, { log }));
  assertEquals(res.status, 403);
  assertEquals(rows[0].verified_at, null);
  assertEquals(log, []);
});

Deno.test("debug-verify is refused for an account not on the allowlist", async () => {
  const rows = [session({ user_id: OTHER_USER })];
  const res = await handleRewardedAccess(
    debugVerify(),
    deps(rows, { allowlist: DEBUG_USER, userId: OTHER_USER }),
  );
  assertEquals(res.status, 403);
  assertEquals(rows[0].verified_at, null);
});

Deno.test("an allowlisted account verifies its own session exactly once", async () => {
  const rows = [session()];
  const options = { allowlist: ` ${DEBUG_USER.toUpperCase()} , not-a-uuid` };

  const first = await handleRewardedAccess(debugVerify(), deps(rows, options));
  assertEquals(first.status, 200);
  assertEquals(await first.json(), { verified: true });
  assertEquals(rows[0].verified_at, NOW.toISOString());
  assertEquals(rows[0].transaction_id, `debug-${TOKEN}`);

  const second = await handleRewardedAccess(debugVerify(), deps(rows, options));
  assertEquals(second.status, 404);
});

Deno.test("debug-verify cannot verify a consumed session", async () => {
  const rows = [session({ consumed_at: "2026-10-13T19:59:00.000Z" })];
  const res = await handleRewardedAccess(
    debugVerify(),
    deps(rows, { allowlist: DEBUG_USER }),
  );
  assertEquals(res.status, 404);
  assertEquals(rows[0].verified_at, null);
});

Deno.test("debug-verify cannot verify an expired session", async () => {
  const rows = [session({ expires_at: "2026-10-13T19:59:59.000Z" })];
  const res = await handleRewardedAccess(
    debugVerify(),
    deps(rows, { allowlist: DEBUG_USER }),
  );
  assertEquals(res.status, 404);
  assertEquals(rows[0].verified_at, null);
});

Deno.test("debug-verify cannot verify another user's session", async () => {
  const rows = [session({ user_id: OTHER_USER })];
  const res = await handleRewardedAccess(
    debugVerify(),
    deps(rows, { allowlist: DEBUG_USER }),
  );
  assertEquals(res.status, 404);
  assertEquals(rows[0].verified_at, null);
});

Deno.test("a malformed token is rejected before any database call", async () => {
  const log: string[] = [];
  const res = await handleRewardedAccess(
    debugVerify("not-a-token"),
    deps([session()], { allowlist: DEBUG_USER, log }),
  );
  assertEquals(res.status, 400);
  assertEquals(log, []);
});

Deno.test("an unauthenticated caller gets the auth error, not a reward", async () => {
  const rows = [session()];
  const res = await handleRewardedAccess(debugVerify(), {
    ...deps(rows, { allowlist: DEBUG_USER }),
    authenticate: () =>
      Promise.reject(new PaidAPIAccessError(401, "UNAUTHENTICATED", "Sign in")),
  });
  assertEquals(res.status, 401);
  assertEquals(rows[0].verified_at, null);
});
