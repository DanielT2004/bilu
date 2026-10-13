# Bilu purchase infrastructure

This change implements the Discovery Pass and Bilu Pro purchase contracts.
Commerce is disabled by default. It does not create App Store products,
provision Apple credentials, change a live Supabase database, or activate
payments. The Pro purchase UI and server entitlement path remain behind the
same disabled rollout gates until isolated sandbox validation is complete.

## Product contract

| Access | Explore | TikTok venue discovery | Lifetime |
| --- | ---: | ---: | --- |
| Free | 2 | 1 | Each UTC calendar month |
| Discovery Pass | +4 | +1 | Purchased balances never expire |
| Bilu Pro | 6 total | 1 total | Each anchored service month; not additive to Free; loading ads suppressed while active |

The intended US Pass price is $4.99. The production UI reads the actual localized
price from StoreKit. `com.simonsoloman.bilu.discovery_pass` is a consumable.
Existing saved places and preferences remain device-local and available. This
work does not add cloud synchronization or unlimited provider requests.

## Purchase and fulfillment

1. Browsing stays anonymous. Buying or restoring requires a durable Apple-linked
   Supabase account. Guest linking retains its UUID where supported; signing into
   an existing account leaves local saved places untouched.
2. StoreKit receives the account UUID as its `appAccountToken`. Only verified
   StoreKit transactions enter the protected local delivery journal.
3. `purchase-verify` validates the signed Apple chain and current Apple API state,
   account, bundle, product, environment, quantity, and ownership. The database
   grants a transaction once. The client calls `finish()` only after confirmation.
4. A lost response or interrupted app restarts delivery without charging again.
   Restore reconciles available StoreKit history and the authoritative wallet.
5. Refunds revoke only the attributable unspent balance. Receipt ownership
   tombstones survive explicit account deletion to prevent regranting a receipt.
   Verified delayed notifications can update those tombstones without recreating
   an account or granting credits.

Pending deliveries belong to their original Bilu account. A receipt for another
account remains recoverable and does not block checkout on the current account.
Apple approval reminders survive app restarts. Clearing a reminder requires an
explicit user confirmation and purchase reconciliation; it never cancels an
Apple request or starts a replacement purchase automatically.

Wallet balances and included service periods are environment-scoped. A Sandbox
grant cannot become production spending capacity by changing a flag. Sandbox and
production must still use separate backend projects and notification URLs.

## Discovery accounting

The commerce client uses `POST discovery` for the complete Explore or TikTok
venue workflow. The backend reserves a unit atomically, starts one provider job
per UUID, verifies useful final results, then commits or releases the reservation.
Included capacity is used before purchased balances. Provider technical quotas
and global spending caps still apply.

The client persists an account-scoped request ID and input digest, not a raw
prompt. A retry first checks the old job. Its bearer is fixed to the identity used
to fetch the wallet, so switching accounts during a request cannot spend the next
account's allowance. Ambiguous commit responses remain pending rather than being
mistaken for a refund.

Final results are recoverable for 24 hours. Pending reservations expire after
30 minutes; this is a job lease, not purchased-credit expiration. Releases return
capacity to its original grant or period, including across monthly boundaries.
The migration installs five-minute cleanup when `pg_cron` is available. If it is
not available, schedule `purchase_wallet_maintenance()` in the target environment
before launch so expired result payloads are physically removed.

Opening Explore does not spend a commerce discovery on Trending. Raw legacy
provider routes reject direct calls when the backend commerce flag is enabled;
only in-process orchestration may bypass that entry check. Client headers or JSON
cannot assert that privilege. The legacy experience remains in place with the
client commerce flag off. No compatibility fallback is allowed to bypass the
server wallet after the backend cutover.

## HTTP contracts

All user endpoints require a real Supabase user access token; the public anon
project key is not a user credential. Purchase RPCs are service-role only and
purchase tables have RLS without client write access.

| Endpoint | Request | Response |
| --- | --- | --- |
| `purchase-wallet` | `{}` | Account, plan, included/purchased balances, dates, availability |
| `purchase-verify` | `{signedTransaction}` | `{wallet}` after verified delivery/reconciliation |
| `discovery` | `{discoveryId,kind,input,action:"start"}` | Reserved, committed, or terminal job; completed result |
| `discovery` | `{discoveryId,kind,action:"status"}` | Existing owned job without starting provider work |
| `account-delete` | `{authorizationCode}` | Revokes Apple authorization and deletes the verified current account |
| `app-store-notifications` | `{signedPayload}` | Verified Apple V2 notification acknowledgment |

Only the notification endpoint disables gateway JWT verification; it validates
Apple's signed payload instead. Account deletion requires recent Apple
authentication and verifies the authorization-code subject before deleting the
authenticated user's account. Requests cannot supply a target user ID.

## Activation gates

Use [Apple server setup](supabase/APPLE_PURCHASE_SETUP.md),
[Apple account setup](supabase/APPLE_ACCOUNT_SETUP.md), and
[StoreKit testing](Configuration/StoreKit-Testing.md) for exact product, secret,
certificate, and local test details. Keep all gates off until sandbox validation:

- App `BILUCommerceEnabled` remains false until release configuration is approved.
- Server `BILU_COMMERCE_ENABLED` and database `commerce_enabled` default false.
- Storefront availability additionally requires valid Apple configuration and
  matching database/verification environments.
- `BILUProEnabled`, `BILU_PRO_ENABLED`, and database `pro_enabled` remain false.

Sales pauses never prevent verification of a legitimate paid Pass that was
already charged, including a payment that completed during a flag change.
Refunds and existing job recovery continue. Retain verification credentials when
pausing offers. New discovery reservations are paused by the backend commerce
gate; already-owned balances are preserved.

Before rollout, register the consumable and Sign in with Apple capability, enable
the required Supabase Apple/linking settings, apply the reviewed migration,
configure secrets and isolated notification endpoints, and deploy the functions.
Then verify actual Apple sandbox signing/OCSP/API delivery, guest linking,
reinstallation/restore, refund, notification retry, account deletion/revocation,
and deployment-runtime compatibility. Local mocks cannot prove those external
integrations. Give existing daily-free users notice and the planned transition
before switching the production allowance policy.

## Local verification

These commands do not perform live purchases or call paid discovery providers:

```sh
python3 scripts/test_purchase_wallet.py
npx --yes deno test --allow-env supabase/functions/_shared/apple_store_test.ts supabase/functions/_shared/purchase_wallet_test.ts supabase/functions/_shared/discovery_normalization_test.ts supabase/functions/_shared/discovery_boundary_test.ts supabase/functions/_shared/discovery_fulfillment_test.ts supabase/functions/discovery/handler_test.ts supabase/functions/account-delete/handler_test.ts
```

The SQL runner creates and stops a disposable loopback PostgreSQL cluster. Its
minimal `auth.users` fixture tests wallet SQL, not live Supabase Auth. It covers
idempotency, concurrency, refund races, period rollover, environment isolation,
deleted-account replay and delayed notifications, ACLs, and result cleanup. Evidence is written under
`build/purchase-wallet-tests/`.

Run the Xcode `bilu` scheme's unit tests on an installed simulator, including
PurchaseStoreTests, DiscoveryJobServiceTests, and AccountSessionTests. Use the
purchase preview fixtures for UI inspection without a backend; local `.storekit`
transactions must never be accepted by a deployed verifier.

### Verification recorded October 9, 2026

- 67 backend tests passed: Apple signatures/delivery, wallet HTTP contracts,
  discovery accounting and fulfillment, legacy route isolation, normalization,
  and account deletion. All nine affected Edge Function entry points type-check.
- Three disposable PostgreSQL suites passed, including concurrent reservations
  and delayed notifications after account deletion. Evidence:
  `build/purchase-wallet-tests/20261009-173003/`.
- The integrated Xcode unit suite passed 56 tests with zero failures and zero
  reported runtime warnings. Result bundle:
  `/tmp/bilu-account-derived/Logs/Test/Test-bilu-2026.10.09_17-32-14--0700.xcresult`.
- Realm simulator checks covered the iPhone offer, signed-out state, pending
  approval controls/confirmation, largest accessibility text size, and restored
  iPad layout. These are dependency-injected fixtures, not Apple transactions.
- Real StoreKit approval/decline, deployed Apple verification and Supabase Auth
  remain explicit release gates. Local tests do not establish production readiness.

The DEBUG fixture can also read the simulator-only `BILUPurchasePreview` user
default; explicit launch arguments take precedence. Remove that preference after
inspection. The fixture implementation is excluded from Release builds.

Before enabling Pro, independently verify billing grace, subscription changes,
renewal retention, expiry, refunds, and the deliberate refund-reversal policy.
Existing refund tombstones do not automatically regrant a `REFUND_REVERSED`
purchase. Operational notification-history reconciliation and live cost/quality
measurements remain launch work, not claims made by local tests.
