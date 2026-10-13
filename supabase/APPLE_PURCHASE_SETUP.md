# App Store purchase verification setup

This is an inactive server implementation. No App Store products, keys, server
notifications, Supabase secrets, migrations, or deployments were created by this
change. Keep commerce and Pro disabled until the checks below pass in an isolated
sandbox deployment. Xcode `.storekit` purchases cannot fund a server wallet.

## App Store Connect

- App bundle ID: `com.simonsoloman.bilu`. Record the numeric Apple app ID from
  App Information; this is different from the bundle ID and the developer team ID.
- Create `com.simonsoloman.bilu.discovery_pass` as a **consumable**. One verified
  transaction grants four Explore credits and one TikTok credit. Those purchased
  credits have no expiration; the server ledger tracks consumption and refunds.
  Use the approved storefront price and localized StoreKit display price.
- When deliberate isolated sandbox validation begins, create
  `com.simonsoloman.bilu.pro.monthly` and `com.simonsoloman.bilu.pro.annual` as
  auto-renewable subscriptions in the same subscription group. Each active Pro
  service month includes six Explore discoveries and one TikTok discovery; it is
  not additive to Free. Keep the products unavailable in production and keep
  `BILU_PRO_ENABLED` and the database `pro_enabled` flag false until the sandbox
  checklist has passed.
- An Admin creates an **In-App Purchase** key under **Users and Access →
  Integrations → In-App Purchase**. Record its key ID and issuer ID and download
  its `.p8` private key. Store it only as an Edge Function secret. Never add the
  private key to the app, repository, StoreKit configuration, logs, or screenshots.
- Under the app's **App Information → App Store Server Notifications**, select
  **Version 2** and configure separate HTTPS URLs for the production and sandbox
  projects:
  `https://<project-ref>.supabase.co/functions/v1/app-store-notifications`.
  Explicitly set both environments; do not let sandbox notifications fall back to
  the production URL. TLS 1.2 or later is required.

Apple references: [server library and key setup](https://github.com/apple/app-store-server-library-node),
[notification configuration](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications),
[notification lifecycle types](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype).

## Server settings

Use separate Supabase projects for sandbox and production. The same account UUID
must never spend sandbox credits against production providers. The migration also
pins each database to a single environment through
`public.purchase_wallet_configuration.apple_environment`.

| Setting | Required value |
| --- | --- |
| `BILU_APP_STORE_ENVIRONMENT` | Exactly `Production` or `Sandbox`; no default, automatic fallback, `Xcode`, or `LocalTesting` |
| `BILU_APPLE_APP_ID` | The numeric Apple app ID, required in both deployments |
| `APP_STORE_ISSUER_ID` | The App Store Connect issuer UUID |
| `APP_STORE_KEY_ID` | The 10-character In-App Purchase key ID |
| `APP_STORE_PRIVATE_KEY_P8` | The matching P-256 PKCS#8 PEM private key; real newlines or escaped `\n` are accepted |
| `BILU_COMMERCE_ENABLED` | Default absent/false. Set exactly `true` only after sandbox verification and database setup |
| `BILU_PRO_ENABLED` | Leave absent/false in this release |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | Supabase's server-only settings; never substitute an anon key |

In the database singleton, `commerce_enabled` defaults to false,
`pro_enabled` defaults to false, and `apple_environment` defaults to `Production`.
The sandbox database must be set to `Sandbox` before any receipt is processed.
Only privileged deployment tooling may change this configuration. Do not expose
these settings or the purchase RPCs through client RLS permissions.

The commerce flag controls new offers. It does **not** reject fulfillment of a
valid Pass that Apple already charged, including a purchase that completed just
after sales were paused. Receipt verification still requires complete valid Apple
configuration, the correct environment, a nonanonymous authenticated account,
matching signed account token, and current Apple API verification. Existing Pro
original-transaction mappings can likewise reconcile during a sales pause; new
unknown Pro originals remain disabled. Removing credentials would interrupt
recovery and refunds, so pause new sales with the flags while retaining keys.

Keep Supabase gateway JWT verification enabled for `purchase-verify`; the handler
also validates the session with Supabase Auth and rejects anonymous users. For
`app-store-notifications` only, set `verify_jwt = false`: Apple does not send a
Supabase JWT. That handler authenticates the outer V2 JWS and each nested
transaction/renewal JWS using Apple's certificate chain before updating anything.

The public Apple roots are pinned in
[`_shared/apple_store_roots.ts`](functions/_shared/apple_store_roots.ts), with source
URLs and SHA-256 fingerprints from [Apple PKI](https://www.apple.com/certificateauthority/).
They are public certificates, not secrets. Updating the official server library
or roots requires review and rerunning the verification suite. Root certificates
supplied by clients or environment variables are never trusted. Certificate
expiration and online OCSP revocation checks are always enabled.

## Request and ledger behavior

The client sends `POST purchase-verify` with a valid user access token and exactly
`{"signedTransaction":"<StoreKit JWS>"}`. It must pass the current account UUID
as StoreKit's `appAccountToken` at purchase time. A successful response is
`{"wallet":<canonical wallet snapshot>}`; StoreKit `finish()` happens only after
that response. Transport failures leave the transaction pending for retry.

The server checks bundle, product, purchase type, quantity, ownership, environment,
account token and timestamps. It verifies the submitted JWS with Apple's official
`@apple/app-store-server-library@3.1.0`, then calls Apple's
[Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info)
and verifies that fresh signed transaction before granting. It grants no credit
when Apple or the database is unavailable. Signed payloads, account tokens,
locations and private keys are never logged.

The server accepts only one item per purchase; clients cannot submit credit
amounts, user IDs, prices, environments or product overrides. Transactions with
revocation information reconcile successfully to the reduced wallet. Repeated
requests return the current wallet without creating another grant. Database
transaction/original-transaction ownership is immutable and environment scoped.

Notifications require exactly `{"signedPayload":"<Apple V2 JWS>"}`. A notification
can update an existing original-transaction/account mapping but cannot establish
one, even when the signed payload has a valid-looking account token. Unknown
ownership and informational/unknown notification types receive HTTP 200 without
granting. The authenticated purchase flow subsequently fetches current Apple state
and establishes ownership. Database notification UUIDs and transaction IDs make
replays idempotent. Refunds remove remaining credits, preserve transaction
tombstones and are processed even when the commerce rollout flag is off.

The subscription contract verifies renewal payload linkage, records transaction
expiry, clamps upgraded transactions to their signed date, and prevents stale
updates from replacing newer state. Expired and refunded transactions cannot
produce an active Pro wallet. The implementation remains disabled: before
enabling it, validate billing-grace behavior, annual/monthly allowance periods,
subscription changes, and refund-reversal policy against Apple's sandbox.
Currently refunds are permanent tombstones; `REFUND_REVERSED` does not
automatically reinstate credits. Consumption requests are acknowledged without
sharing user consumption information with Apple. No consumption-data API
submission or customer-consent flow is implemented here.

## Local checks and launch evidence

These checks do not need credentials or make real purchases:

```sh
npx --yes deno test --allow-env supabase/functions/_shared/apple_store_test.ts
npx --yes deno check supabase/functions/purchase-verify/index.ts supabase/functions/app-store-notifications/index.ts
```

Before enabling commerce, apply the reviewed migration to an isolated local or
sandbox database and run its wallet concurrency/idempotency tests. Validate the
deployed Edge runtime against Apple's sandbox with a sandbox tester and an actual
Apple-signed transaction, including a genuine OCSP success. Local negative
signature tests prove rejection but cannot prove the deployed network/runtime or
live key permissions work. Verify valid purchase + finish, replay, interrupted
verification/retry, another-account restore rejection, anonymous rejection,
revocation/refund and out-of-order notifications, production/sandbox rejection,
and an Apple `TEST` notification. Confirm each notification retry returns success
only after the database operation succeeds. Apple API and database outages must
leave the client transaction unfinished for later reconciliation.

Run Apple's Request a Test Notification / Get Test Notification Status only after
the endpoint has been deliberately deployed and configured. Review non-2xx
notification responses and arrange operational recovery with Apple's notification
history API; this patch does not install a background history-recovery scheduler.
Keep paid products unavailable until these external launch gates are complete.
