# Durable Bilu accounts

Commerce remains off by default. No Apple Developer, Supabase or production settings
were changed. Complete this setup and the real-device/Sandbox checks before
turning purchases on. The app's public Supabase key cannot delete accounts or fund
wallets; all administrative credentials stay on the server.

## Sign in with Apple

1. Enable Sign in with Apple for the existing App ID `com.simonsoloman.bilu` in
   Apple Developer and regenerate the app's provisioning profile. The app now
   declares `com.apple.developer.applesignin = [Default]`.
2. Enable the Apple provider in Supabase Auth, with the native bundle ID as an
   allowed client ID. Keep nonce validation enabled. Configure an Apple Services
   ID only if a web sign-in flow is separately implemented; this app uses native
   AuthenticationServices and ID-token exchange.
3. Enable **manual identity linking** in Supabase Auth settings. A live guest
   calls `POST /auth/v1/token?grant_type=id_token` with the guest JWT and
   `link_identity: true`, Apple ID token and original random nonce. The Apple
   request receives SHA-256 of that nonce. If Supabase specifically returns
   `identity_already_exists`, the app signs into that original Bilu account.
   Configuration/network errors never silently replace the guest. An explicit
   **Use an existing Bilu account** choice can recover an account even when a
   guest refresh token has expired; normal guest upgrade still preserves its UUID.
4. Verify first sign-in preserves the existing guest UUID and wallet, and that
   signing into an existing Apple identity recovers its existing UUID. Device
   SwiftData saves and preferences are kept on upgrade and sign-out. Local saved
   places are device data; this feature does not claim cloud synchronization.
5. Keep Apple and Supabase provider credentials current. Test credential
   revocation and expired refresh tokens; an invalid stored session must show
   recovery rather than silently creating a new anonymous identity.

The original Keychain service/account identifiers are retained for migration.
Refresh, sign-in and sign-out serialize across suspension; refresh failures keep
stored tokens and identity. Explicit sign-out clears the Keychain only after
server logout succeeds (or the server says the session is already invalid).
A pending receipt keeps its original account token even after sign-out, and the
server rejects delivery to another account.

## Account deletion

Deploy `account-delete` with gateway JWT verification enabled, alongside its
shared `paid_api_guard.ts`. Its dependencies include pinned `npm:jose@6.1.3`.
Configure these **server-only** secrets using a Sign in with Apple key, which is
separate from the App Store purchase key:

| Secret | Value |
| --- | --- |
| `BILU_SIGN_IN_APPLE_TEAM_ID` | Apple Developer Team ID |
| `BILU_SIGN_IN_APPLE_KEY_ID` | Key ID of the Sign in with Apple private key |
| `BILU_SIGN_IN_APPLE_PRIVATE_KEY` | P-256 PKCS#8 `.p8` key with real or escaped newlines |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | Existing trusted Supabase server configuration |

The app's **Discoveries & account → Delete account** warns about permanent loss
of remaining discoveries, then requests fresh Apple authentication. Supabase must
return the same account UUID before the client persists that session. The endpoint
validates the JWT with Supabase Auth, requires a nonanonymous UUID and an OAuth
AMR within five minutes, exchanges the fresh authorization code with Apple,
verifies the returned ID token against Apple's public keys and the account's
Apple subject, revokes the token, then deletes only the authenticated Supabase
user. It never accepts a user ID from the request. It logs no tokens or account
claims. If verification, revocation or deletion fails, the app offers a retry.

Apply the purchase migration before enabling this endpoint. Auth deletion
cascades wallet balances and discovery results. The minimum transaction ownership
and replay tombstones deliberately remain, so deleting/recreating an account
cannot redeem the same purchase again. The privacy policy must disclose that
retention. Device-local saves remain, as the deletion confirmation explains.

If a customer cannot complete the normal fresh-Apple flow, support must still
fulfill an authenticated deletion request and direct them to manually revoke
Bilu's Apple access, following Apple's deletion guidance; revocation failure must
not become an indefinite barrier to account deletion.

## Local verification and release gates

- `AccountSessionTests`: concurrent refresh, no anonymous fallback, Keychain
  failure, guest linking, existing-account recovery, failed link isolation,
  same-account deletion reauthentication, explicit recovery past an expired
  guest refresh token, and old Keychain schema.
- `account-delete/handler_test.ts`: auth/method/body/size gates, matching fresh
  OAuth claims, no caller-selected account, revocation ordering and retry safety.
- Debug-only launch arguments `-BILUPurchasePreview signed-out`, `ready`,
  `unavailable`, `pending`, `pending-sync`, `restored`, `error` show injected
  in-memory purchase/account fixtures. These never use live purchase APIs,
  StoreKit or the auth Keychain. Fixture tokens are never accepted by a server.
- On a signed device, verify Apple signup/link, existing account recovery,
  restart/refresh, purchase then sign-out/same-account restoration, and full
  deletion with Apple revocation. Repeat with denied/cancelled Apple UI, network
  interruption and a wrong Apple account. Simulator fixture checks are not proof
  of these production contracts.

Official references checked October 9, 2026:
[Supabase native identity linking](https://supabase.com/docs/guides/auth/auth-identity-linking),
[Supabase Swift ID-token sign-in](https://supabase.com/docs/reference/swift/auth-signinwithidtoken),
[Supabase native ID-token linking implementation](https://github.com/supabase/auth-js/blob/master/src/GoTrueClient.ts),
[Apple account deletion and revocation](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple),
[Apple token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens),
[Apple token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens).
