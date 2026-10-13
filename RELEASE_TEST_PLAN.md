## Optional ads and bug audit — October 7, 2026

Owner clarification: retain ads, remove the one-per-day limit. Home offers normal discovery and an optional “Watch an ad & discover” button. Ad failure never blocks normal discovery. Legacy SSV remains configured but is not needed to grant unrestricted discoveries. Validate real production ad delivery separately; Debug uses Google test ads.

## Current scope update — October 7, 2026

The owner removed the daily free discovery/rewarded-ad requirement. Historical rewarded-ad notes below remain evidence of previous work, but ad unlock and SSV are no longer release gates for this app flow. Verify repeated discoveries instead.

# Bilu Release-Preparation Test Plan

Use this checklist before TestFlight submission and again before App Store release. Record the build number, device, OS, tester, date, and evidence link for every manual run.

Latest automated validation: 2026-10-01. The 55-test suite passes under Xcode 27.0 on iPhone 17 Pro / iOS 26.5, with 54 applicable tests passing and one expected device-family skip. The earlier 51-test suite also passed on iPad Pro 13-inch (M5) / iOS 26.5. Release static analysis passes under Xcode 27.0, and all 12 Edge Function files pass current Deno formatting and type checks. Earlier launch smoke tests passed on iPhone 17e and iPhone 17 Pro Max / iOS 26.5 and iPhone 17 Pro / iOS 26.2, and an unsigned Release archive was produced. The latest broader manual run remains the [2026-09-16 simulator and production-backend result](MANUAL_TEST_RESULTS_2026-09-16.md); physical-device, TestFlight, production rewarded-ad configuration and end-to-end verification, controlled fault-injection, deployment, and performance gates remain outstanding.

## October 7 search regression validation

The current working tree (base commit `c02aeb3`, with existing uncommitted changes preserved) passed 40 unit tests and two focused UI tests on iPhone 17 Pro / iOS 26.5 using Xcode 27.0 (27A266a). Three new unit tests cover late video results after Clear, overlapping searches completing out of order, and pending location extraction invalidated by a missing-city query. Clear also resets loading and location-filter state. Launch and missing-city/clear UI smoke checks passed. `git diff --check` passed.

Result bundles: `/tmp/bilu-oct7-search-fixes.xcresult` and `/tmp/bilu-oct7-search-ui.xcresult`. These are local temporary artifacts. The full UI suite, live paid providers, production rewarded ads, and physical-device testing were not rerun in this session. No backend or App Store changes were published. See [the review preparation packet](review/APP_REVIEW_PACKET_2026-10-07.md) for Apple's six requested items and unresolved submission dependencies.

## October 7 AdMob configuration validation

The production App ID and rewarded-unit ID supplied by the owner are configured in the app target's Release build settings. Debug resolves to Google's test identifiers. An unsigned Release build for generic iOS completed successfully, and the resulting app bundle's Info.plist was inspected to confirm both production IDs expanded correctly. Plist/project validation and `git diff --check` passed. This does not verify live ad serving, consent configuration, backend deployment, SSV callbacks, signing, or physical-device behavior.

## October 7 production SSV setup

Updated Supabase `ADMOB_REWARDED_AD_UNIT_ID` to `ca-app-pub-2845173126212624/2728696496` with owner authorization. AdMob's signed callback verifier reported success for `https://yysxjtexwlnvoptxcxlp.supabase.co/functions/v1/rewarded-access`. Selected “Use verified url,” saved the setting on **Bilu Extra Discovery**, and confirmed the URL appeared in the saved ad-unit settings. Reward settings show **1 Discovery**. This validates the dashboard callback, not an actual earned reward or token consumption.

Read-only deployment inspection found `rewarded-access` ACTIVE at version 5 (gateway JWT verification off for signed Google callbacks; handler authentication remains required for client POSTs). No function deployment or migration was performed. AdMob's account page reports missing payment information, and Bilu is marked **Requires review**. Account readiness and a physical-device test in test-device mode remain outstanding.

## October 7 broader simulator QA

The full baseline suite passed on iPhone 17 Pro / iOS 26.5: 57 passed and one expected iPad-only skip. Manual iPhone 17e inspection found undersized results/detail touch targets; these were expanded, map-pin labels were clarified, and detail tabs now announce selection. Final focused verification passed four checks on iPhone 17e and three on iPad Pro 13-inch (M5), including landscape navigation. An initial directions test assumed a Cancel button existed in every system chooser; the corrected test supports outside-tap dismissal. An iPad runner stall was resolved by a fresh sequential test run.

See [the simulator QA report](review/SIMULATOR_QA_2026-10-07.md) for result bundles, a screenshot, exact coverage, and the remaining live-service and physical-device limits. The populated results screen used a debug fixture. No new physical-device or production reward verification gate is closed by this run.

## Release gates

A candidate is ready only when all of the following are true:

- [x] Clean Xcode build completes with zero errors and zero Swift compiler warnings. Xcode emits only its tool-level notice that App Intents metadata extraction is skipped for targets that do not link App Intents.
- [x] All platform-applicable tests in the 55-test suite pass on iPhone 17 Pro / iOS 26.5 (54 passed and one expected device-family skip). The earlier 51-test suite also passed on iPad Pro 13-inch (M5) / iOS 26.5.
- [ ] No open P0 or P1 defects; accepted P2 defects have an owner and release note.
- [ ] Release AdMob identifiers configured October 7; still configure/verify the production SSV callback and matching server ad unit, and verify rewarded discovery end to end on a physical device.
- [ ] Production health check succeeds without exposing tokens, personal data, or server internals.
- [ ] Crash-free smoke run completes on at least one current physical iPhone.
- [ ] VoiceOver, Dynamic Type, Reduce Motion, light appearance, and minimum tap targets are checked.
- [ ] Privacy policy, diagnostics consent, location permission, and account/session behavior match the release configuration.

## Automated test inventory

### Models, migration, and persistence

- [x] Missing or unknown parking data displays `Parking not confirmed`.
- [x] Verified parking guidance is trimmed and preserved.
- [x] Recommendation identity prefers Google Place ID and has a deterministic fallback.
- [x] Legacy saved-vibe JSON receives migration-safe defaults.
- [x] Current saved-vibe JSON round-trips every active field.
- [x] Vibe equality ignores ordering and non-identity fine-tune fields.
- [x] Vibe equality detects location, selected vibe, and sub-occasion changes.
- [x] Saved-vibe summaries handle full, partial, and empty selections.
- [x] Saved places survive an in-memory SwiftData round trip.
- [x] Recommendation → SavedPlace → Recommendation preserves user-visible fields.
- [x] Unknown future list values fall back safely.
- [x] Duplicate saves are rejected and toggling removes the existing save.
- [x] Moving a place between lists does not duplicate it.
- [x] Equivalent saved vibes toggle the existing record rather than creating a duplicate.

### Prompt and preference logic

- [x] Typed location wins over coordinates; coordinates win over the generic fallback.
- [x] Radius and coordinates appear only when radius search is enabled.
- [x] Fine-tune price, party size, open-now, parking, outdoor, and accessibility constraints appear after confirmation.
- [x] Unconfirmed fine-tune settings do not leak into the prompt.
- [x] Dietary constraints are stable, sorted, and included in recommendation prompts.
- [x] Dietary encoding ignores unknown future values without losing known values.
- [x] Profile IDs remain stable across view-model recreation.
- [x] Display names are trimmed, avatars persist, and handles are sanitized.
- [x] Cuisine classification recognizes supported cuisines and counts distinct values.

### Search state and filtering

- [x] A query without a city stops locally and does not spend a backend request.
- [x] Clearing search restores the initial query, results, filter, and view-mode state.
- [x] Open-now and neighborhood filters compose correctly.
- [x] Location video lookup returns only associated videos in original result order.

### UI and accessibility

- [x] App launches with Explore, Search, and Profile navigation.
- [x] Selected tab state follows navigation across all three destinations.
- [x] Notifications opens and dismisses a meaningful sheet.
- [x] Search field, sort state, and Profile edit action have accessible identities.
- [x] Missing-city search presents city guidance and can be cleared.
- [x] Profile edit and dietary sheets expose accessible controls.
- [x] The recommendation journey allows a food selection and keeps Continue reachable.
- [x] Survey navigation hides the bottom tabs while the journey is in progress.
- [x] Primary header and tab controls meet the 44×44-point minimum.
- [x] Location-prompt dismissal, ranking/occasion chips, and Browse by Cuisine meet the 44-point minimum.
- [x] Accessibility Large text keeps the primary navigation and actions reachable.
- [x] iPhone remains portrait-only while iPad keeps primary navigation reachable in landscape.
- [x] Diagnostics are off by default and Profile privacy actions remain accessible with 44-point targets.

## Manual functional matrix

### First launch and permissions — P0

- [x] Fresh install, location allowed: current area resolves and the map updates.
- [ ] Fresh install, location denied: app remains usable with typed location and explains recovery.
- [x] Location permission changed later in Settings: app reflects the new state after foregrounding.
- [ ] Airplane mode on first launch: app opens, local profile/saves remain usable, and retry messaging is clear.
- [x] Relaunch after force quit returns to a valid screen without a blank overlay or stuck loader.

### Recommendation journey — P0

- [x] Exercise every top-level occasion: fast, sit-down, brunch, late night, and drinks.
- [x] Exercise each food category and at least one expanded sub-option.
- [x] Verify category expansion visibly indicates that Continue is below the fold.
- [x] Exercise country-cuisine mode and switch back to vibe mode.
- [x] Exercise Trending, Best Rated, Hidden Gem, Date Night, and Special Occasion ranking modifiers.
- [ ] Verify city-wide search excludes radius language and radius search includes the selected distance.
- [ ] Drag the map center, adjust radius, collapse, reopen, and confirm the selection persists.
- [x] Apply every fine-tune control individually and in combination.
- [x] Confirm five or fewer result cards render without missing names, explanations, map links, or parking text.
- [ ] Open each result detail, gallery, map action, website, and phone action where available.
- [ ] Save, unsave, share, start New Vibe, and rerun a saved vibe.
- [ ] Trigger a no-match response, timeout, capacity error, and offline error; verify distinct recovery copy.
- [ ] Tap Retry after a forced 401 and verify the stale anonymous session is replaced once.

### Search — P1

- [ ] Search with full city name, abbreviation, neighborhood, punctuation, and mixed case.
- [ ] Search without a city and choose each suggested-city chip.
- [x] Switch among Videos, List, and Map while locations are still loading.
- [ ] Change Relevant, Most Liked, and Most Recent sorting after results load.
- [x] Combine Open Now and multiple neighborhood filters, including a zero-result combination.
- [x] Open a location from list and map, then launch its associated video feed.
- [x] Clear during loading and confirm old asynchronous results do not repopulate the screen.
- [ ] Background and foreground during search; verify no duplicate request or stuck loading state.

### Profile and local data — P0/P1

- [ ] Add/edit/remove name and choose every avatar row without clipping.
- [ ] Enable and disable every dietary preference; confirm prompt behavior on the next recommendation.
- [ ] Save the same restaurant twice and confirm only one record exists.
- [ ] Move a place Saved → Want to Go → Saved and confirm counts and cards update immediately.
- [ ] Delete a place and verify it stays deleted after relaunch.
- [ ] Save equivalent vibes with reordered food categories and confirm no duplicate.
- [ ] Upgrade from the prior production build with existing saves and verify migration preserves them.
- [ ] Simulate a persistent-store open failure and verify the original store is preserved.

### Backend and authentication — P0

- [x] Confirm `recommendations` is ACTIVE, JWT verification is enabled, and expected version is deployed.
- [x] Fresh anonymous signup returns 200 using the embedded publishable key.
- [x] Recommendation request without a bearer token returns 401.
- [x] Valid token returns 200 and every result satisfies the response contract.
- [ ] Expired/revoked token triggers exactly one session refresh/recreation and one retry.
- [ ] Multiple explicit discoveries in the same UTC day succeed without an ad or daily-free gate; authentication and paid-API abuse/spending protections still apply.
- [x] Per-user quota returns the documented 429 response and retry guidance.
- [ ] Global budget/capacity protection returns documented 429/503 behavior without repeated paid calls.
- [ ] Gemini timeout stays within the client latency budget and returns the documented 504 code.
- [ ] Logs contain request IDs and capacity metrics but no access tokens, prompts containing personal data, or API keys.
- [x] CORS preflight and content-type handling succeed for the intended clients.

### Accessibility and appearance — P0

- [ ] VoiceOver reads the screen in logical order on Explore, Search, Profile, sheets, and result cards.
- [ ] Selected tabs, chips, dietary preferences, sort options, and radius state announce their state.
- [ ] Every actionable icon has a useful label and hint; decorative images are ignored.
- [ ] Keyboard focus and dictation work in search and profile name fields.
- [x] Test all Dynamic Type sizes; at accessibility sizes, no primary action is lost or clipped.
- [ ] Reduce Motion removes looping and staged movement while preserving state changes.
- [x] Increase Contrast and Reduce Transparency keep text and controls legible.
- [x] Verify light and system-dark device settings both produce one coherent supported appearance.
- [ ] Check color meaning is never the only indication of selection, errors, or availability.
- [ ] Verify all tap targets are at least 44×44 points and do not overlap.

### Device, lifecycle, and performance — P1

- [x] Test smallest supported iPhone, current Pro size, and largest Pro Max size.
- [ ] Test minimum supported iOS version and current iOS version.
- [ ] Rotate during sheets, map expansion, search results, and result details if rotation is supported.
- [ ] Exercise low-memory warning while viewing image-heavy results; app remains responsive.
- [ ] Scroll 20+ cards/videos and confirm stable frame rate and bounded memory growth.
- [ ] Revisit image-heavy screens and confirm cache hits do not cause stale or mismatched images.
- [ ] Test Wi-Fi → cellular → offline transitions during recommendation and search requests.
- [ ] Leave the app backgrounded long enough for the access token to expire, then resume and search.
- [ ] Verify cold launch, warm launch, recommendation latency, and map-interaction targets against release SLOs.

### Privacy, security, and release packaging — P0

- [ ] Privacy Policy production URL returns HTTP 200 and its rewarded-ad disclosures match the deployed client and consent configuration.
- [ ] Diagnostics remain off until consent and stop immediately when consent is withdrawn.
- [x] Keychain stores refresh/session tokens; tokens never enter UserDefaults or logs.
- [x] Publishable client key is present; service-role and Gemini secrets are absent from the app bundle.
- [x] App Transport Security, privacy manifest, location usage text, and share-extension declarations are correct.
- [ ] Archive uses Release configuration, correct bundle IDs, signing team, version, and build number.
- [ ] TestFlight install/upgrade succeeds and production endpoints—not local/staging endpoints—are used.
- [ ] App Store screenshots and metadata reflect the actual UI and supported behavior.

## Suggested execution order

1. Run the automated suite on a clean simulator.
2. Run P0 first-launch, recommendation, backend, accessibility, privacy, and upgrade checks.
3. Run P1 Search, Profile, lifecycle, device, and performance checks.
4. Fix defects, repeat the affected section, then rerun the complete automated suite.
5. Archive the exact tested commit and record its commit SHA, Supabase function version, and xcresult bundle.

## Commands

```sh
xcodebuild -quiet clean test \
  -project bilu.xcodeproj \
  -scheme bilu \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'

supabase functions list --project-ref yysxjtexwlnvoptxcxlp --output json
```
