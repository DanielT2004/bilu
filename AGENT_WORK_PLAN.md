# Bilu — sub-agent work plan (October 11, 2026)

Goal: get `setup-onboarding` to a releasable TestFlight build. Sources: the
release gates in `RELEASE_TEST_PLAN.md` (currently only in the older checkout at
`~/Realm/personal/nomis-files/bilu/`), `ADMOB_SETUP.md`,
`LOADING_ADS_VERIFICATION.md`, `PURCHASE_INFRASTRUCTURE.md`, and the issues found
on October 9–10.

## Rules for every agent

1. Read `CLAUDE.md` in full and the `bilu-builder` skill before changing code.
2. Work in your own git worktree and branch, `agent/<workstream-letter>-<slug>`.
   Never commit to `setup-onboarding` directly; the coordinator merges.
3. Only touch the files your workstream owns. If you need another file, stop and
   report what you need rather than editing it.
4. Use only your assigned simulator and pass your own `-derivedDataPath`
   (`/tmp/bilu-dd-<letter>`). Parallel runs on one simulator break each other.
5. **Never**: deploy Edge Functions, apply migrations, change Supabase secrets,
   upload to App Store Connect or TestFlight, tap production ad units, or run
   unbounded live Gemini/Places calls. Each workstream may make at most
   **3 live discoveries** in total, and only when its goal needs them.
6. Known tooling quirk: `xcodebuild test` can hang after the tests finish. Wait
   for `Test Suite 'Selected tests' passed|failed` in the log, then stop it.
7. Finish with a report covering: branch, commits, files changed, exact test
   commands and results, what was verified, and what was **not** verified.

Simulators (UDIDs): A → iPhone 17 `BF9DD194-1435-4DFD-BF34-423234BB83AF` ·
C → iPhone 17 Pro `30513E90-4892-49F5-890E-4BB3F623D161` ·
D/G → iPhone 17 Pro Max `A514B1E5-BC0A-4E22-83A3-9B575DD351B9` ·
F → iPhone 17e `6FCAA280-2E72-4C7B-AA53-BD6F819781F8` ·
H → iPad Pro 13-inch `0AB3A36A-B59B-4DEF-88E5-6928660634C7`.

## Decisions the owner must make first

- **Monetization for this release.** The code ships one free discovery per UTC
  day plus rewarded ads, with a commerce wallet behind flags. Release gate
  "multiple discoveries per day without an ad" (plan line 159) contradicts that.
  Pick one; workstreams B, C and H depend on it.
- **Pushing.** May the coordinator push `setup-onboarding` and agent branches to
  `origin`?

## Phase 0 — Stabilize the branch (coordinator, sequential, blocks everything)

**W0. Commit the in-flight work in reviewable pieces.** 61 untracked and 26
modified files exist only in the working tree, and worktrees start from the last
commit. Suggested commits: (1) purchase wallet and account (client, functions,
migration, tests, docs); (2) loading-screen ads and discovery analytics;
(3) the reward-flow fixes (rejected-reward notice, 30 s timeout, `debug-verify`,
message persistence); (4) bring `RELEASE_TEST_PLAN.md` into the repo.
Each commit must build on its own. Exclude `build/`, `downloads/`,
`_claude_backup/`, `11.txt` and secrets.
*Done when* `git status` is clean apart from deliberate ignores, the unit suite
passes, and the only failing UI test is the known one in workstream A.

## Phase 1 — Parallel workstreams (start after W0)

**A. Test-suite health.** Re-check
`AppLaunchUITests.testSearchKeepsKeyboardVisibleAfterEveryCharacter` before
fixing anything: it passed 7 of 7 runs on iPhone 17 Pro / iOS 26.5 at d5f2c64
and 1343565 (October 13). Run it on this workstream's iPhone 17 before closing
the gate. The original failure: the search field measured 80 pt tall instead
of 44. It fails without the tab change, so it
probably comes from the uncommitted `SearchView.swift` edits. Decide whether the
view or the test is wrong, using the 44 pt single-line contract. Then get every
unit and UI test green on one run.
*Owns* `bilu/Views/SearchView.swift`, `biluUITests/`.
*Done when* the full `bilu` scheme passes with a result bundle path in the report.

**B. Documentation truth pass (docs only).** Fix the claims that are now wrong:
`ADMOB_SETUP.md` says Debug bypasses SSV, but Debug now uses `debug-verify` and
the `REWARD_DEBUG_USER_IDS` allowlist. Reconcile `RELEASE_TEST_PLAN.md` with the
monetization decision, the tab-persistence behavior, and the 30 s client
timeout. Document the debug-reward allowlist, including that a reinstall
changes the account ID. List every deployed vs. local function and migration.
*Owns* `*.md` only. *Done when* each changed claim cites the code or command
that backs it.

**C. Recommendation-journey recovery (P0).** Release gates 127–128: no-match,
timeout, capacity, offline, usage-limit, reward-rejected, and forced-401 retry
each show distinct copy and recover correctly. Add a unit test for each in
`HomeViewModel` using the injected `fetchRecommendations`, and add a UI check for
the visible copy. Also confirm a slow response no longer loses the free
discovery: the client waits 30 s and the server deadline is 19 s.
*Owns* `HomeViewModel.swift`, the error section of `HomeView.swift`,
`GeminiService.swift`, `biluTests/LoadingAdTests.swift` or a new test file.
*Done when* tests cover every failure type and screenshots show the copy.

**D. Accessibility audit (read-only).** Run the P0 accessibility gates (plan
lines 166–177) on Explore, Search, Profile, sheets and result cards: VoiceOver
order and labels, selected-state announcements, 44×44 targets, the largest
Dynamic Type size, Reduce Motion, and color-only meaning. Produce a defect list
ranked P0/P1/P2, with each item giving file:line, a screenshot and a suggested fix.
*Owns* nothing (no edits). *Done when* the list is written to
`build/a11y-audit/REPORT.md` with screenshots.

**E. Backend verification (no deploys).** Run `deno fmt --check` and
`deno check` on every function, plus the existing Deno and SQL test suites.
Add Deno tests for `rewarded-access`: `debug-verify` refused when the allowlist
is unset or the account isn't listed; accepted once; a second use refused; an
expired session refused. Check that logs never contain tokens, prompts or keys.
Use `npx deno@latest` if Deno isn't installed.
*Owns* `supabase/functions/**/**_test.ts`, `supabase/tests/`, and formatting of
files it already has to touch.
*Done when* all suites pass and the report lists the commands.

**F. Profile and persistence (P0/P1).** Release gates 143–150: no duplicate
saves, Saved ↔ Want to Go moves, deletions surviving relaunch, vibe dedupe
regardless of order, migration from the previous production build's store, and
a store that fails to open being preserved. Add the missing tests and fix any
defects.
*Owns* `bilu/Models/`, the persistence controller and saved-places store,
`biluTests/ModelAndPersistenceTests.swift`.
*Done when* each gate has a passing test or a written reason it can only be
checked manually.

## Phase 2 — After Phase 1 is reviewed and merged

**G. Accessibility fixes.** Fix D's P0/P1 items. To avoid conflicts, split by
screen: G1 Explore (`HomeView.swift`), G2 Search, G3 Profile and sheets. Run
them one at a time, or in parallel only if no two touch the same file.

**H. Release packaging dry run.** Do an unsigned Release archive and check the
bundle IDs, version and build number, `Info.plist` production ad IDs, privacy
manifest, entitlements (Sign in with Apple, App Group), that Debug-only code
(`debug-verify`, purchase preview fixtures) is excluded from Release, and the
iPad layout. No upload. *Done when* there's a packaging report with archive
evidence.

**Review.** Run a read-only reviewer over each branch before it merges.

## Phase 3 — Owner-gated (needs explicit approval or a human)

- Apply migration `20261009010000_discovery_ad_diagnostics` and deploy
  `discovery-telemetry` (production project).
- Production rewarded SSV: AdMob SSV test tool plus a TestFlight/device run on
  the real unit (Release builds don't use `debug-verify`).
- AdMob dashboard: impression-level revenue, consent and content controls,
  app-ads.txt, SKAdNetwork list.
- App Store Connect privacy answers and the hosted privacy policy, for banners,
  metrics and the voluntary reward.
- Commerce, if it's in scope: Apple sandbox purchase, restore, refund,
  notifications, and account deletion (`PURCHASE_INFRASTRUCTURE.md` gates).
- Physical iPhone smoke run, fresh install with location denied, airplane-mode
  launch, TestFlight install and upgrade over the previous build.
- Before a public release, decide whether to keep or clear
  `REWARD_DEBUG_USER_IDS` (it fails closed either way).
