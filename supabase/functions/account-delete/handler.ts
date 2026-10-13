import {
  PaidAPIAccessError,
  paidAPIAccessErrorResponse,
} from "../_shared/paid_api_guard.ts";

export interface DeletionAccount {
  id: string;
  appleSubject: string;
}
export interface AccountDeletionDependencies {
  authenticate(request: Request): Promise<DeletionAccount>;
  revokeApple(code: string, expectedSubject: string): Promise<void>;
  deleteUser(id: string): Promise<void>;
}

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
};

export async function handleAccountDeletion(
  req: Request,
  dependencies: AccountDeletionDependencies,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { headers });
  if (req.method !== "POST") {
    return Response.json({ code: "METHOD_NOT_ALLOWED" }, {
      status: 405,
      headers: { ...headers, Allow: "POST, OPTIONS" },
    });
  }
  try {
    const user = await dependencies.authenticate(req);
    const text = await boundedBody(req);
    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      throw new PaidAPIAccessError(
        400,
        "INVALID_REQUEST",
        "A fresh Apple authorization is required",
      );
    }
    const value = body as { authorizationCode?: unknown } | null;
    if (
      !value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).some((key) => key !== "authorizationCode") ||
      typeof value.authorizationCode !== "string" ||
      value.authorizationCode.length < 1 ||
      value.authorizationCode.length > 4096
    ) {
      throw new PaidAPIAccessError(
        400,
        "INVALID_REQUEST",
        "A fresh Apple authorization is required",
      );
    }
    // Revoke only a token whose verified Apple subject belongs to this account.
    await dependencies.revokeApple(value.authorizationCode, user.appleSubject);
    // No caller-supplied user ID; receipt replay tombstones intentionally survive
    // auth deletion, while wallet balances/reservations are removed by FK cascade.
    await dependencies.deleteUser(user.id);
    return Response.json({ deleted: true }, { headers });
  } catch (error) {
    return paidAPIAccessErrorResponse(error, headers) ?? Response.json({
      code: "ACCOUNT_DELETE_UNAVAILABLE",
      error: "Account deletion couldn’t finish. Please try again.",
    }, { status: 503, headers });
  }
}

async function boundedBody(request: Request): Promise<string> {
  const reader = request.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > 8192) {
        await reader.cancel();
        throw new PaidAPIAccessError(
          413,
          "REQUEST_TOO_LARGE",
          "Request is too large",
        );
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

/** Run only after Supabase /auth/v1/user verified this exact bearer token. */
export function requireRecentAuthentication(
  token: string,
  userID: string,
  nowSeconds = Date.now() / 1000,
): void {
  try {
    const part = token.split(".")[1];
    const normalized = part.replaceAll("-", "+").replaceAll("_", "/");
    const claims = JSON.parse(
      atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=")),
    );
    const recentOAuth = Array.isArray(claims.amr) &&
      claims.amr.some((method: { method?: unknown; timestamp?: unknown }) =>
        method.method === "oauth" && typeof method.timestamp === "number" &&
        method.timestamp <= nowSeconds + 30 &&
        nowSeconds - method.timestamp <= 300
      );
    if (claims.sub === userID && recentOAuth) return;
  } catch { /* Reject malformed, old and refresh-only sessions alike. */ }
  throw new PaidAPIAccessError(
    401,
    "REAUTHENTICATION_REQUIRED",
    "Confirm your identity with Apple again",
  );
}
