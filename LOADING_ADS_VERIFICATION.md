# Loading advertisement implementation — 2026-10-09

Implemented in the existing dirty working tree; existing purchase/account changes
were preserved. No production deployment, paid AI request, or real ad click was
used for verification. The follow-up production configuration created the
dedicated AdMob banner unit described below.

## Changed files owned by this task

| Files | Purpose |
| --- | --- |
| `bilu/Config/AdvertisingConfiguration.swift`, `bilu/Info.plist` | Banner test/production configuration, persisted request caps, ad-free eligibility |
| `bilu/Services/AdPrivacyService.swift`, `RewardedAdService.swift`, `bilu/biluApp.swift` | Shared UMP/SDK lifecycle; preserve voluntary rewarded flow |
| `bilu/Services/LoadingAdController.swift`, `LoadingBannerAd.swift` | Cancellable passive-ad lifecycle, adaptive SDK wrapper, impressions/revenue |
| `bilu/ViewModels/HomeViewModel.swift`, `bilu/Views/HomeView.swift` | Independent discovery/ad work, duplicate/stale-request guards, actual result arrival, no automatic allowance-spending Trending request |
| `bilu/Views/Components/DiscoveryLoadingView.swift`, `LoadingPulseView.swift` | Cream/red loading layout, reserved inline banner space, Dynamic Type/Reduce Motion support |
| `bilu/Config/Config.swift`, `bilu/Views/UserView.swift` | Ad privacy controls available in both commerce modes, support/report route, diagnostics disclosure |
| `bilu/PrivacyInfo.xcprivacy` | Advertising/interaction analytics declarations; required elapsed-time API reason (only in-app durations leave the device) |
| `bilu/Services/DiscoveryAnalytics.swift`, `AppDiagnosticsReporter.swift` | Typed opt-in events, bounded asynchronous upload, immediate opt-out purge |
| `supabase/functions/discovery-telemetry/`, `supabase/migrations/20261009010000_discovery_ad_diagnostics.sql`, `supabase/config.toml` | Authenticated diagnostics ingestion, quota, private tables/aggregate views, 30-day purge |
| `supabase/functions/privacy-policy/index.ts`, `supabase/MONITORING.md`, `ADMOB_SETUP.md` | Accurate disclosures, aggregation and release setup |
| `biluTests/LoadingAdTests.swift`, `DiscoveryAnalyticsTests.swift` | Controlled timing/lifecycle/allowance/entitlement/analytics regressions |
| `bilu/Services/LoadingAdPreview.swift`, `biluUITests/LoadingAdvertisementUITests.swift` | DEBUG-only deterministic UI fixtures and opt-in Google test-banner smoke |
| `supabase/functions/discovery-telemetry/handler_test.ts`, `supabase/tests/discovery_diagnostics.sql`, `scripts/test_discovery_diagnostics.py` | Endpoint and disposable local SQL verification |
| `AppStore/review-assets/loading-ads/` | Simulator screenshot evidence |

## Behavioral evidence

- Controlled quick AI response ends loading before the ad grace; no request is made.
- AI completion while the ad is unresolved reaches results and releases the banner.
- Slow AI continues after no-fill/ad failure. AI failure preserves discovery access
  and suppresses ads on rapid retries.
- The preexisting enrichment readiness timeout now returns when its timer wins,
  without waiting for a losing provider observer; only verified late results may
  update the same discovery. Cancellation ends the race promptly.
- Cancelled/stale callbacks cannot alter a newer discovery. Old grace/view cleanup
  cannot cancel the newer banner. Backgrounding permanently suppresses that search's ad.
- Passive ad events leave both free allowance and reward token untouched. Rewarded
  credit searches suppress the banner and consume their token only via discovery.
- Free wallets are eligible; Pro is excluded even with sales flags disabled.
  Unknown entitlements and unsettled purchases fail closed.
- Request spacing, UTC daily cap, error cooldown, layout-width changes, opt-in
  analytics, bounded retries, and decimal revenue are covered locally.
- Actual Google test ads rendered through UMP + Google Mobile Ads 13.10.0 on
  [iPhone](AppStore/review-assets/loading-ads/google-test-banner-iphone.png) and
  [iPad](AppStore/review-assets/loading-ads/google-test-banner-ipad.png).
- [iPhone layout screenshot](AppStore/review-assets/loading-ads/loading-layout-iphone-fixture.png)
  uses a visibly marked ad fixture, not live AdMob fill.

## Scope of verification

Tests use iOS 26.5 simulators, iPhone 17 Pro Max and iPad (A16). The final run
passed **91 unit tests and seven iPhone UI tests** (98 total, zero skipped or
failed), including 28 focused loading/ad/entitlement/enrichment tests and seven
analytics tests. The Google test-banner smoke test was explicitly enabled.
Three iPad tests passed: actual Google test banner, default layout, and
accessibility text size. The smoke test remains opt-in for deterministic CI.

Result bundles from this session:

- `/tmp/bilu-loading-ads-final.xcresult` — final 98-test run.
- `/tmp/bilu-loading-ads-ipad.xcresult` — three iPad checks.
- `/tmp/bilu-loading-ads-packaged-debug.log` — final Debug packaging.
- `/tmp/bilu-loading-ads-packaged-release.log` — final unsigned Release packaging.

Six diagnostics endpoint Deno tests and 26 existing discovery/wallet backend
tests passed. Rewarded-access and new telemetry TypeScript checks passed.
Disposable local PostgreSQL diagnostics migration tests passed, including
permissions, deduplication, caps, aggregation, and decimal revenue. Cron was
stubbed locally; it was not exercised against a hosted project.

Debug simulator builds and unsigned Release device builds succeeded. Xcode
emitted its non-blocking AppIntents metadata warning and simulator automation
reported debugger/accessibility framework warnings. The first UI run failed two
heading lookups because a parent accessibility identifier overrode child IDs;
the identifier was corrected and the complete affected UI suite passed.

## Production work remaining

The dedicated “Explore Loading Banner” production unit
`ca-app-pub-2845173126212624/8124864538` is configured in `Info.plist`.
AdMob's saved settings confirm Banner format, automatic refresh **disabled**,
and Google optimized (All prices) eCPM floor. Debug continues to use Google's
test unit. This configuration does not establish production fill or revenue.

Enable paid-event reporting and verify AdMob/UMP content controls and app
verification. Deploy the optional
analytics migration/function and updated hosted policy; check App Store privacy
answers. See [ADMOB_SETUP.md](ADMOB_SETUP.md) for the full list and official sources.

The authoritative purchase wallet must return a confirmed free plan before ads
serve; a missing wallet endpoint or offline/unknown state intentionally shows no ad.

Existing release rewarded SSV code was audited and type-checked; local allowance
and backend-boundary tests passed. Google's Debug rewarded unit bypasses live SSV,
so production reward issuance still needs an AdMob SSV tool/TestFlight/device test.
No claim is made about production fill, finalized revenue, live AI recommendation
quality, App Store approval, or hosted analytics deployment.
