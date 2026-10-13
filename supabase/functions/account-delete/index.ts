import {
  createRemoteJWKSet,
  importPKCS8,
  jwtVerify,
  SignJWT,
} from "npm:jose@6.1.3";
import { PaidAPIAccessError } from "../_shared/paid_api_guard.ts";
import {
  type AccountDeletionDependencies,
  handleAccountDeletion,
  requireRecentAuthentication,
} from "./handler.ts";

const APPLE_CLIENT_ID = "com.simonsoloman.bilu";
const appleKeys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
  { timeoutDuration: 5000 },
);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function serverConfiguration() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) {
    throw new PaidAPIAccessError(
      503,
      "AUTH_UNAVAILABLE",
      "Account services are unavailable",
    );
  }
  return { url, key };
}

const dependencies: AccountDeletionDependencies = {
  async authenticate(request) {
    const { url, key } = serverConfiguration();
    const match = request.headers.get("Authorization")?.match(
      /^Bearer\s+(.+)$/i,
    );
    if (!match) {
      throw new PaidAPIAccessError(
        401,
        "AUTH_REQUIRED",
        "Sign in to delete your account",
      );
    }
    const response = await fetch(`${url}/auth/v1/user`, {
      headers: { apikey: key, Authorization: `Bearer ${match[1]}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) {
      throw new PaidAPIAccessError(
        401,
        "INVALID_SESSION",
        "Sign in again to delete your account",
      );
    }
    const user = await response.json();
    if (
      typeof user.id !== "string" || !UUID.test(user.id) ||
      user.is_anonymous !== false
    ) {
      throw new PaidAPIAccessError(
        401,
        "SIGN_IN_REQUIRED",
        "Sign in with Apple to delete your account",
      );
    }
    requireRecentAuthentication(match[1], user.id);
    const apple = Array.isArray(user.identities)
      ? user.identities.find((identity: { provider?: string }) =>
        identity.provider === "apple"
      )
      : undefined;
    const subject = apple?.identity_data?.sub;
    if (typeof subject !== "string" || subject.length === 0) {
      throw new PaidAPIAccessError(
        401,
        "APPLE_ACCOUNT_REQUIRED",
        "Confirm your Apple account",
      );
    }
    return { id: user.id, appleSubject: subject };
  },

  async revokeApple(code, expectedSubject) {
    const teamID = Deno.env.get("BILU_SIGN_IN_APPLE_TEAM_ID");
    const keyID = Deno.env.get("BILU_SIGN_IN_APPLE_KEY_ID");
    const privateKey = Deno.env.get("BILU_SIGN_IN_APPLE_PRIVATE_KEY");
    if (!teamID || !keyID || !privateKey) {
      throw new PaidAPIAccessError(
        503,
        "APPLE_AUTH_UNAVAILABLE",
        "Account services are unavailable",
      );
    }
    const signingKey = await importPKCS8(
      privateKey.replaceAll("\\n", "\n"),
      "ES256",
    );
    const secret = await new SignJWT({}).setProtectedHeader({
      alg: "ES256",
      kid: keyID,
    })
      .setIssuer(teamID).setSubject(APPLE_CLIENT_ID).setAudience(
        "https://appleid.apple.com",
      )
      .setIssuedAt().setExpirationTime("5m").sign(signingKey);
    const response = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_CLIENT_ID,
        client_secret: secret,
        code,
        grant_type: "authorization_code",
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) {
      throw new PaidAPIAccessError(
        401,
        "APPLE_REAUTHENTICATION_REQUIRED",
        "Confirm your identity with Apple again",
      );
    }
    const tokens = await response.json();
    if (
      typeof tokens.id_token !== "string" ||
      typeof tokens.refresh_token !== "string"
    ) throw new Error("invalid_apple_response");
    const { payload } = await jwtVerify(tokens.id_token, appleKeys, {
      issuer: "https://appleid.apple.com",
      audience: APPLE_CLIENT_ID,
      algorithms: ["RS256"],
      clockTolerance: 30,
    });
    if (payload.sub !== expectedSubject) {
      throw new PaidAPIAccessError(
        403,
        "ACCOUNT_MISMATCH",
        "Use the Apple account linked to this Bilu account",
      );
    }
    const revoked = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: APPLE_CLIENT_ID,
        client_secret: secret,
        token: tokens.refresh_token,
        token_type_hint: "refresh_token",
      }),
      signal: AbortSignal.timeout(8000),
    });
    if (!revoked.ok) throw new Error("apple_revocation_unavailable");
  },

  async deleteUser(id) {
    const { url, key } = serverConfiguration();
    const response = await fetch(
      `${url}/auth/v1/admin/users/${encodeURIComponent(id)}`,
      {
        method: "DELETE",
        headers: { apikey: key, Authorization: `Bearer ${key}` },
        signal: AbortSignal.timeout(8000),
      },
    );
    if (!response.ok) throw new Error("account_deletion_unavailable");
  },
};

if (import.meta.main) {
  Deno.serve((request) => handleAccountDeletion(request, dependencies));
}
