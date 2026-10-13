import {
  type AccountDeletionDependencies,
  handleAccountDeletion,
  requireRecentAuthentication,
} from "./handler.ts";
import { PaidAPIAccessError } from "../_shared/paid_api_guard.ts";

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
const userID = "11111111-1111-4111-8111-111111111111";
function fixture() {
  const events: string[] = [];
  const deps: AccountDeletionDependencies = {
    authenticate: () =>
      Promise.resolve({ id: userID, appleSubject: "apple-subject" }),
    revokeApple: (code, subject) => {
      events.push(`revoke:${code}:${subject}`);
      return Promise.resolve();
    },
    deleteUser: (id) => {
      events.push(`delete:${id}`);
      return Promise.resolve();
    },
  };
  return { events, deps };
}
function request(body: unknown) {
  return new Request("https://local.test/account-delete", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

Deno.test("deletion revokes matching Apple identity before deleting authenticated own user", async () => {
  const { events, deps } = fixture();
  const response = await handleAccountDeletion(
    request({ authorizationCode: "fresh-code" }),
    deps,
  );
  assert(response.status === 200);
  assert(
    events.join("|") === `revoke:fresh-code:apple-subject|delete:${userID}`,
  );
});
Deno.test("deletion never accepts a caller selected account", async () => {
  const { events, deps } = fixture();
  const response = await handleAccountDeletion(
    request({ authorizationCode: "fresh-code", userId: userID }),
    deps,
  );
  assert(response.status === 400);
  assert(events.length === 0);
});
Deno.test("failed authentication cannot revoke or delete", async () => {
  const { events, deps } = fixture();
  deps.authenticate = () => {
    throw new PaidAPIAccessError(401, "AUTH_REQUIRED", "sign in");
  };
  assert(
    (await handleAccountDeletion(request({ authorizationCode: "code" }), deps))
      .status === 401,
  );
  assert(events.length === 0);
});
Deno.test("Apple account mismatch leaves the Bilu account intact", async () => {
  const { events, deps } = fixture();
  deps.revokeApple = () => {
    throw new PaidAPIAccessError(
      403,
      "ACCOUNT_MISMATCH",
      "wrong Apple account",
    );
  };
  assert(
    (await handleAccountDeletion(request({ authorizationCode: "code" }), deps))
      .status === 403,
  );
  assert(events.length === 0);
});
Deno.test("unavailable Apple revocation leaves account intact for retry", async () => {
  const { events, deps } = fixture();
  deps.revokeApple = () => {
    throw new Error("offline");
  };
  assert(
    (await handleAccountDeletion(request({ authorizationCode: "code" }), deps))
      .status === 503,
  );
  assert(events.length === 0);
});
Deno.test("unsupported methods and oversized requests never delete", async () => {
  const { events, deps } = fixture();
  assert(
    (await handleAccountDeletion(new Request("https://local.test"), deps))
      .status === 405,
  );
  assert(
    (await handleAccountDeletion(
      request({ authorizationCode: "x".repeat(9000) }),
      deps,
    )).status === 413,
  );
  assert(events.length === 0);
});
Deno.test("recent auth requires matching subject and fresh OAuth AMR, not a freshly refreshed JWT", () => {
  function token(sub: string, timestamp: number, method = "oauth") {
    return `header.${
      btoa(JSON.stringify({ sub, iat: 1000, amr: [{ method, timestamp }] }))
    }.signature`;
  }
  requireRecentAuthentication(token(userID, 900), userID, 1000);
  for (
    const value of [
      token(userID, 600),
      token("other", 999),
      token(userID, 999, "refresh_token"),
      token(userID, 1100),
      "bad",
    ]
  ) {
    let rejected = false;
    try {
      requireRecentAuthentication(value, userID, 1000);
    } catch {
      rejected = true;
    }
    assert(rejected);
  }
});
