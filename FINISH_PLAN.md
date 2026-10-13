# Bilu — finish the release and the redesign (October 13, 2026)

**Paste this into Claude Code (or another agent IDE with Xcode) at
`/Users/joyboy/bilu`:**

> Read `FINISH_PLAN.md` in full and act as the coordinator it describes. Ask me
> the owner decisions first, then run the phases in order, spawning one
> sub-agent per workstream with the agent type listed. Stop at Phase 4 and
> report.

This file replaces the "what's next" parts of `AGENT_WORK_PLAN.md` (release)
and `FEEDBACK_REDESIGN_PLAN.md` (redesign). Read both for background; where
they disagree with this file, this file wins.

---

## Where things stand

Pushed to `origin/setup-onboarding` (1343565): W0 (in-flight work committed),
C0 (design contract in `AGENTS.md`/`CLAUDE.md`), P1 (Explore quick fixes).

Local branches, **not pushed, not yet merged**, all made without Xcode:

| Branch | What's in it | Verified | Not verified |
| --- | --- | --- | --- |
| `agent/rel-e-backend-verify` (2a24f11) | `rewarded-access` split into `handler.ts` + 8 `debug-verify` tests | `deno check` on every function; 84/84 Deno tests | — |
| `agent/rel-b-docs-truth` (1219837) | `ADMOB_SETUP.md`, `RELEASE_TEST_PLAN.md`, `AGENT_WORK_PLAN.md` corrections | Each claim traced to code | Keychain/UUID claim not tried on a device |
| `agent/fb-b1-tiktok-resolve` (2599fd4) | Pipeline moved to `_shared/tiktok_places.ts`; new `tiktok-resolve` function + 9 tests; `TikTokResolveService.swift` + `TikTokResolveServiceTests.swift` | 85/85 Deno tests | **Swift never compiled.** UI not wired. Not deployed |

`redesign/feedback` exists locally at 1343565 with nothing on it yet.

Reports to read (in the main checkout; `build/` is gitignored, so worktrees
won't have them):
- `build/feedback-redesign/r1/REPORT.md`: audit, with file:line for every open
  item and new findings.
- `build/feedback-redesign/d3a/PLAN.md`: the feed and intent-sheet plan for
  D3b. Needs owner approval (decisions 2 and 3 below).

Housekeeping: `/Users/joyboy/bilu-wt-fb-p1` is an orphaned worktree folder
from P1 (its branch is merged and git no longer tracks it). Delete it.

## Owner decisions (ask before Phase 0; defaults shown)

1. **Monetization for this release.** The code ships 1 free discovery per UTC
   day plus rewarded ads; release gate "multiple discoveries per day without
   an ad" contradicts it. *Default: keep what's coded and change the gate.*
2. **Trending (D3a decision A).** A1: daily per-city cache (needs a migration
   and a deploy). A2: leave Trending out of feed v1. *Default: A2.*
3. **Taste tags (D3a decision B).** Add optional `tags` to `SavedPlace` and fill
   them on save. *Default: yes.*
4. **Search-text logging.** `tiktok-locations` logs the user's search query
   and transcript previews (`_shared/tiktok_places.ts` after B1 merges). The
   release plan says no personal data in logs. *Default: log lengths and
   counts only.*
5. **Pushing.** May the coordinator push `setup-onboarding` and
   `redesign/feedback` to origin (DanielT2004/bilu)? *Default: ask again
   before each push.*

## Rules for every agent

1. Rules 1–7 of `AGENT_WORK_PLAN.md` still apply: read `CLAUDE.md` and the
   `bilu-builder` skill first; own worktree (`/Users/joyboy/bilu-wt-<id>`) and
   branch (`agent/<id>-<slug>`); touch only owned files; own simulator and
   `-derivedDataPath /tmp/bilu-dd-<id>`; **no deploys, migrations, secret
   changes, App Store/TestFlight uploads or production ad taps**; at most 3
   live discoveries per workstream; stop `xcodebuild test` once
   `Test Suite 'Selected tests' passed|failed` prints.
2. Deno: if `deno` isn't installed, use `npx -y deno@latest`.
3. Every UI change ships with before/after screenshots (light and dark) in
   `build/<track>/<id>/` in the main checkout.
4. Keep the accessibility identifiers the UI tests use; if one must change,
   update its test in the same commit.
5. Report: branch, commits, files, exact test commands and results, what was
   verified, what was **not**.

## Agents

| Agent type | Used for | Edits code |
| --- | --- | --- |
| `general-purpose` | Implementation in a worktree | Yes |
| `Explore` | Read-only audits | No |
| `general-purpose` + `mvp-pre-push-review` skill | Review of each branch before merge | No |

The coordinator is the main session: it merges, resolves conflicts, runs the
full suite after each merge, and is the only one who pushes.

---

## Phase 0 — Coordinator: land the no-Xcode work (sequential)

1. Merge `agent/rel-e-backend-verify` then `agent/rel-b-docs-truth` into
   `setup-onboarding` (the docs reference E's test file). Run all Deno tests
   and the full `bilu` scheme.
2. Reset `redesign/feedback` to the new `setup-onboarding`
   (`git branch -f redesign/feedback setup-onboarding`; nothing is on it yet).
3. Rebase `agent/fb-b1-tiktok-resolve` onto `redesign/feedback`. **Build it in
   Xcode first.** Fix any compile errors in `TikTokResolveService.swift` or its
   tests, then run `TikTokResolveServiceTests` and the Deno suite.
   Workstream B1b continues on this branch.

*Done when* `setup-onboarding` has E and B, the full scheme and Deno suite pass,
and B1's Swift compiles and its tests pass.

## Phase 1 — Parallel (start after Phase 0)

Release track (branch from `setup-onboarding`; simulators from
`AGENT_WORK_PLAN.md`):

**A. Test-suite health.** `general-purpose`, iPhone 17. Run
`testSearchKeepsKeyboardVisibleAfterEveryCharacter` 5× on iPhone 17 first; fix
only if it fails. Add a UI test that re-selecting Explore returns it to the
start (the unchecked item in `RELEASE_TEST_PLAN.md`). Get every unit and UI
test green in one run. *Owns* `SearchView.swift`, `biluUITests/`.

**C. Recommendation-journey recovery.** `general-purpose`, iPhone 17 Pro. As
written in `AGENT_WORK_PLAN.md` (each failure type has distinct copy, recovers,
and has a unit test; a slow response keeps the free discovery).

**D. Accessibility audit.** `Explore`, iPhone 17 Pro Max. As written in
`AGENT_WORK_PLAN.md`; report to `build/a11y-audit/REPORT.md`.

**F. Profile and persistence.** `general-purpose`, iPhone 17e. As written in
`AGENT_WORK_PLAN.md`. If decision 3 is yes, F also owns adding the optional
`tags` field to `SavedPlace` (an additive change) with a migration test from
the previous store.

**E2. Backend tidy.** `general-purpose`, no simulator. `deno fmt` the three
unformatted files (`_shared/discovery_access.ts`, `photos/index.ts`,
`support/index.ts`) and apply decision 4 to the logs. Branch from
`redesign/feedback` so it includes B1's `_shared/tiktok_places.ts`.

Redesign track (branch from `redesign/feedback`; create simulators with
`xcrun simctl create "bilu-fb-<id>" "iPhone 17 Pro"`):

**B1b. Shared TikToks in the app.** `general-purpose`, continuing on
`agent/fb-b1-tiktok-resolve`. On launch, resolve each pending share with
`TikTokResolveService` (pass `cityForTikTok()` and coordinates). Show the
place in `PendingSharesRowView`, with "Add to Want to Go". `.needsCity` asks
for a city; `.unavailable` lets the user dismiss; `.retryLater` keeps the
share. If decision 3 is yes, store the place's tags. *Owns*
`PendingSharesRowView.swift`, `PendingShareStore.swift`,
`PendingTikTokShare.swift`, `TikTokResolveService.swift`, the share section of
`UserView.swift`.

**D1. Design-system foundation.** `general-purpose`. As in
`FEEDBACK_REDESIGN_PLAN.md`: bundle Noto Serif and Plus Jakarta Sans (OFL,
download from Google Fonts or their GitHub repos), register in `UIAppFonts`,
add `AppTheme` type tokens with Dynamic Type, add `BiluCard`. Also from R1:
one icon per meaning (`bookmark` = Saved, a different symbol for Want to Go,
used the same in Profile and the detail screen; "Save this vibe" gets its own
symbol), and replace `Color.black`/`Color.gray` in shared components
(`HungerCard`, `HorizontalOccasionCard`, `VibeCard`, `SwipeFoodPanel`,
`SurveyOptionCard`). *Owns* `AppTheme.swift`, fonts, `Info.plist` font keys,
`BiluCard.swift`, those components, the icon parts of `RestaurantDetailView`
and `UserView`.

**P2. Quick fix from R1.** `general-purpose`, small. The restaurant-detail
search icon (`RestaurantDetailView.swift:127`) looks tappable but isn't a
button: remove it. Comment or remove the empty `onTapGesture` in
`BiluMapView.swift:86`. Can merge into `setup-onboarding` for the release.

## Phase 2 — After Phase 1 merges

**G. Accessibility fixes.** `general-purpose`, split by screen as in
`AGENT_WORK_PLAN.md`. Skip anything in Explore that D3b replaces.

**D2. Native navigation.** `general-purpose`. Starts after A merges. As in
`FEEDBACK_REDESIGN_PLAN.md`: native `TabView` (icons only, state kept,
Explore re-select resets, hidden during the survey), `.searchable` in Search,
native back buttons (R1 found `arrow.left` and `chevron.left` both in use).

**D3b. Feed and action button.** `general-purpose`. Starts after D1 merges.
Build exactly what `build/feedback-redesign/d3a/PLAN.md` describes, with the
owner's decisions 2 and 3 applied: `FeedView`, `IntentSheet`, `LocationChip`,
`applyIntent` in `HomeViewModel`, and remove the Eat/Drinks switcher, time
cards, chips and the 34 pt titles. This also clears the Drinks tab's empty
space, the last open item on the doc's bug list. Unit tests for every row of
the plan's intent table, plus Drinks + Late night.

**H. Release packaging dry run.** `general-purpose`. As in
`AGENT_WORK_PLAN.md`, on `setup-onboarding` after A, C, F, G and P2 merge. No
upload.

## Phase 3 — Review

**V1.** `general-purpose` running `mvp-pre-push-review` on every branch diff
before it merges. **V2.** `Explore` accessibility pass on the feed, intent
sheet, tab bar and location chip (VoiceOver, 44×44 targets, largest Dynamic
Type with the new fonts, Reduce Motion), report to
`build/feedback-redesign/v2/REPORT.md`.

## Phase 4 — Coordinator wrap-up

Merge order on `redesign/feedback`: B1b → E2 → D1 → D2 → D3b. Re-run the full
scheme and Deno suite after each. Put a before/after screenshot set for the
reviewer in `build/feedback-redesign/summary/`. Report per workstream, then
list what's left for the owner:

- Deploy `tiktok-resolve` (and the moved `tiktok-locations`), plus Trending if
  decision 2 was A1.
- Everything in `AGENT_WORK_PLAN.md` Phase 3 (owner-gated): migrations and
  deploys, production SSV, AdMob dashboard, App Store privacy answers,
  commerce gates, physical-device smoke run, `REWARD_DEBUG_USER_IDS`.
- Not for agents: Mom Test interviews, the Danny sync, studying BiteSight,
  circling back with the reviewer.
