# AdMob setup and loading-screen advertising

Bilu uses an **inline adaptive banner** in the Explore loading screen's reserved
100-point ad area. It has a neutral “Advertisement” label, sits away from the
Back button, and never covers restaurant results. The screen retains the
existing animated food/location loader and includes the user's search summary
and guidance for choosing a restaurant. Google reviews actual placement/content;
this implementation does not guarantee ad serving or policy approval.

## Runtime behavior

`HomeViewModel.submitSurvey` starts AI work immediately and gives a random local
session ID to `LoadingAdController`. The SwiftUI banner host supplies its actual
width; after a one-second quick-response grace, the controller can issue one
Google request. AI never awaits consent, an ad, an impression, or revenue.
Results remove the banner before the reveal transition. No minimum ad exposure,
interstitial, app-open ad, or automatic rewarded playback is introduced.

`AdPrivacyService` owns UMP and SDK startup for both formats. It updates consent
at launch, disables publisher first-party ID before SDK startup, and provides
non-personalized requests (`npa=1`). UMP permission is required even for these
requests. Ad privacy choices remain reachable in Profile in both commerce modes.
Profile also links to Bilu support for reporting inappropriate advertisements.
Do not obscure the SDK's AdChoices/ad-information controls.

The controller discards its view/delegates on completion, cancellation,
navigation, background/inactivity, changed privacy choices, or uncertain/Pro
entitlement. An inactive search may finish in the background; its banner never
reappears on return. Identity checks reject old responses. Rotation can keep a
creative that still fits; shrinking below its width drops it until the next
eligible discovery. iPad/split-view widths are measured, not taken from the
main screen. There is no banner prefetch outside an active search and no retry
loop after no-fill.

`AdvertisingConfiguration.frequency` defaults:

- At most one request per discovery, at least 120 seconds between requests.
- At most three requests per UTC day, persisted across app launches.
- Ten-minute cooldown after an ad failure; five minutes after discovery error.
- One-second grace skips ads for near-instant recommendations without delaying AI.
- Suppress banners on rewarded-credit searches and while reward verification is busy.

`PurchaseStore.wallet.plan == "free"` is required. Pro, missing/stale wallets,
unknown plan names, and pending purchase synchronization suppress ads, regardless
of the commerce sales flag. The wallet backend must therefore be available to
confirm a free entitlement before production banners can serve. `proEnabled`
controls selling Pro; it is not used to revoke a purchased ad-free entitlement.

## Identifiers and dashboard steps

Production identifiers:

- App: `ca-app-pub-2845173126212624~6002912892`
- Rewarded unit: `ca-app-pub-2845173126212624/6016275205`
- Explore Loading Banner: `ca-app-pub-2845173126212624/8124864538`

The dedicated **Banner** unit, “Explore Loading Banner,” was created in Bilu's
AdMob iOS app on 2026-10-09. Its saved **automatic refresh is disabled** and its
eCPM floor uses Google optimized (All prices). The production ID is configured
in `BILULoadingBannerAdUnitIdentifier` in `bilu/Info.plist`; Release builds use it.
Keep refresh disabled so the short-lived placement requests once per discovery.
[AdMob unit settings](https://admob.google.com/v2/apps/6002912892/adunits/8124864538/edit)

Remaining release checks:

1. Enable impression-level ad revenue in AdMob. SDK decimal values are currency
   units, not micros. AdMob finalized reports remain the revenue authority.
2. Verify consent messages, age-appropriate content controls/blocking, app
   verification/app-ads.txt, and the current SKAdNetwork list for enabled demand.
3. Update App Store Connect privacy disclosures and the hosted privacy policy
   for passive banners and optional discovery/ad metrics. Reassess ATT before
   introducing cross-company tracking or mediation; this change does neither.
4. Deploy the optional diagnostics migration/endpoint and policy update described
   in `supabase/MONITORING.md`. Without that deployment, uploads fail harmlessly;
   AI and ads do not depend on telemetry.
5. Confirm the authoritative purchase wallet endpoint works, including Pro,
   restore/account changes and offline entitlement behavior.

Debug uses Google's inline/adaptive banner unit
`ca-app-pub-3940256099942544/2435281174` and rewarded unit
`ca-app-pub-3940256099942544/1712485313`. Release rejects Google's sample banner
publisher. These are public identifiers, not API credentials. Never test clicks
or impressions on production units during development.

## Existing rewarded access

One free guided discovery per UTC day remains the legacy rule. Rewarded ads
remain explicitly voluntary and use their existing signed server callback:

`https://yysxjtexwlnvoptxcxlp.supabase.co/functions/v1/rewarded-access`

Retain migrations `20260918000000_rewarded_discovery_access.sql` and
`20260923000000_refund_discovery_access.sql`, plus secret
`ADMOB_REWARDED_AD_UNIT_ID` matching the rewarded unit. `rewarded-access` uses
`--no-verify-jwt` because Google's GET callback is signed rather than JWT-authenticated;
POST actions validate the user's JWT internally. The callback checks Google's
signature, ad unit, user, session expiry, and unique transaction ID. Consumption
remains atomic and server-authorized. Passive banners never create, verify,
grant, or consume reward tokens.

Debug rewarded ads can't use live SSV, because Google's sample unit can't be
assigned Bilu's callback. Instead, Debug builds call `rewarded-access` with
`action: "debug-verify"` after the ad finishes (`RewardedAdService.verifyDebugReward`,
`#if DEBUG` only). The server accepts it only for accounts listed in the
`REWARD_DEBUG_USER_IDS` secret (comma-separated account UUIDs); unset means
disabled, which is the production setting. A debug-verified session is consumed
exactly like a real reward: once, for its own account, before it expires
(`supabase/functions/rewarded-access/handler_test.ts` covers each case).
Debug tests do **not** verify production SSV. Use AdMob's SSV testing tool and a
controlled TestFlight/device run before release.

### Debug reward allowlist

- If a Debug reward is refused, the Xcode console prints
  `add <account UUID> to REWARD_DEBUG_USER_IDS`. Add that UUID to the secret.
- The account UUID lives in the Keychain under a service chosen by the
  Supabase project (`Config.supabase.sessionKeychainService`). From the code:
  reinstalling the same build on the same device keeps the UUID, because
  nothing clears the Keychain on first launch; pointing a build at a different
  Supabase project, a new simulator, or erasing the device gives a new UUID,
  which must be added again. (Read from the code, not yet confirmed on a
  device.)

The automatic Trending request was found to consume the legacy backend free
allowance. It is now disabled; there is no separate allowance-free Trending
endpoint. Intentional discovery still uses the original allowance gate. Commerce
mode's separate monthly/purchased-wallet behavior is preserved.

## Analytics and verification

Diagnostics are opt-in through Profile → Share Diagnostics. Events cover starts,
completion/failure/cancellation, loading duration, actual result arrival, banner
requests, SDK impressions/failures/clicks, paid values, and backgrounding. Payloads
contain no prompts, food selections, locations, account IDs, reward tokens, or
advertising IDs. The random session ID is unrelated to backend discovery IDs.
See `supabase/MONITORING.md` for aggregation views, sample bias, 30-day retention,
and why abandonment after an impression is correlation rather than proof of harm.

`LoadingAdTests` uses fake SDK callbacks and controlled AI completions for races,
frequency, quick/slow responses, failure, cancellation, backgrounding, and reward
separation. `DiscoveryAnalyticsTests` checks consent, queue bounds and revenue.
`LoadingAdvertisementUITests` uses DEBUG-only fixture AI and an explicitly marked
layout fixture, never paid provider calls. The optional Google smoke test requires
`BILU_RUN_ADMOB_SMOKE=1` in the test runner environment and uses Google's test unit;
it may fail with unavailable consent, network, or ad fill.

Official implementation/policy references checked for this change:

- [Inline adaptive banners](https://developers.google.com/admob/ios/banner/inline-adaptive)
- [Banner lifecycle and test IDs](https://developers.google.com/admob/ios/banner)
- [UMP consent](https://developers.google.com/admob/ios/privacy)
- [Impression-level revenue](https://developers.google.com/admob/ios/impression-level-ad-revenue)
- [Banner placement](https://support.google.com/admob/answer/6275335?hl=en)
- [Ad request frequency](https://support.google.com/admob/answer/2936217?hl=en)
- [Publisher-content requirements](https://support.google.com/publisherpolicies/answer/11112688?hl=en)
- [Apple App Review 2.5.18](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

The app privacy manifest declares System Boot Time reason `35F9.1` for monotonic
in-app duration measurements; raw uptime is never uploaded. It also declares
product interaction/advertising analytics and the analytics purposes of
performance/error metrics. See [Apple required-reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
