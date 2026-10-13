# Bilu — feedback redesign: coordinator prompt (October 13, 2026)

**Paste this into Claude Code at the repo root:**

> Read `FEEDBACK_REDESIGN_PLAN.md` in full and act as the coordinator it
> describes. Confirm the owner decisions with me first, then run the phases in
> order, spawning one sub-agent per workstream with the agent type listed.

---

## What this plan does

Turns the product feedback session into shipped work. The feedback and how it
maps to the code are in the "Bilu — Product Feedback Review" doc
(https://claude.ai/code/artifact/fd71efb9-7842-4ff0-aaf0-61084650d71f).
In short: Explore becomes a feed, one floating action button starts every
search, navigation goes native, the design system gets its own fonts and drops
the AI-template card look, and TikToks shared into Bilu become taste signals.

**Not for agents** (the owner does these): Mom Test interviews with 10 to 20
people, syncing with Danny on recommendation signals, studying BiteSight, and
the friend/social system (it needs real accounts, which is an owner decision).

## How this fits with `AGENT_WORK_PLAN.md`

The TestFlight release plan comes first. This plan does not start until its
**W0** is done: as of today 66 untracked and 29 modified files exist only in
the working tree, and worktrees start from the last commit.

- **Workstream P1** (quick fixes) branches from `setup-onboarding` so it can
  ship in the release build.
- **Everything else** goes on a new integration branch, `redesign/feedback`,
  cut from `setup-onboarding` after W0 and P1 merge. It does not merge back
  until the owner says the release build is cut.

## Owner decisions (confirm before Phase 0; defaults shown)

1. **Action button scope.** One button with Food and Drinks inside it, not one per
   tab. *Default: one button* (the reviewer's lean).
2. **Intents.** Preset intents, not user-built ones. *Default: presets* —
   "Café to lock in", "Food", "Drinks", "Late night", "Brunch", combinable.
3. **Saved lists.** Keep the existing Saved and Want to Go; no new Favorites
   tab. *Default: keep as is.*
4. **Social.** Feed v1 is personal only; no friend features until accounts
   exist. *Default: personal only.*
5. **Fonts.** Noto Serif for display, Plus Jakarta Sans for UI (already the
   target in `AGENTS.md`; both are SIL OFL licensed, so they can be bundled).
   *Default: those two.*
6. **Deployment target.** Stay on iOS 17.6. A native `TabView` and medium-detent
   sheets render as Liquid Glass automatically on iOS 26 when built with the
   Xcode 26 SDK; anything that calls `glassEffect` goes behind
   `if #available(iOS 26, *)` with an `.ultraThinMaterial` fallback.
   *Default: stay on 17.6.*

## Rules for every agent

1. Rules 1–7 of `AGENT_WORK_PLAN.md` apply unchanged: read `CLAUDE.md` and the
   `bilu-builder` skill first, own worktree and branch, only your owned files,
   own simulator and `-derivedDataPath`, **no deploys, migrations, secrets,
   uploads or production ad taps**, at most **3 live discoveries** per
   workstream, and the `xcodebuild test` hang workaround.
2. Branch names: `agent/fb-<id>-<slug>` (for example `agent/fb-d2-native-nav`),
   cut from the branch named in the workstream.
3. Simulators: don't share with release workstreams. Create your own:
   `xcrun simctl create "bilu-fb-<id>" "iPhone 17 Pro"` and use its UDID.
4. Test command (substitute your id and UDID):
   `xcodebuild test -scheme bilu -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath /tmp/bilu-dd-fb-<id>`
5. Every UI change ships with before/after screenshots in
   `build/feedback-redesign/<id>/`, light and dark.
6. Keep the accessibility identifiers the UI tests rely on (`tab-explore`,
   `tab-search`, `tab-profile`, and so on). If one must change, update the test
   in the same commit.
7. Finish with the report format from `AGENT_WORK_PLAN.md` rule 7.

## Agents used

| Agent type | Used for | Can edit code |
| --- | --- | --- |
| `Explore` | Read-only sweeps and audits | No |
| `Plan` | Designing a change before anyone builds it | No |
| `general-purpose` | Implementation in a worktree | Yes |
| `general-purpose` + `mvp-pre-push-review` skill | Reviewing each branch before merge | No (report only) |

The coordinator is the main Claude Code session. It merges branches, resolves
conflicts, and is the only one who edits `AGENTS.md` / `CLAUDE.md`.

---

## Phase 0 — Coordinator (sequential, blocks everything)

**C0. Update the design contract.** Every agent reads it, so it changes first.
In `AGENTS.md` and `CLAUDE.md` (they are identical copies; keep them so):
- Navigation: native `TabView`, icons only, no active-tab dot; replaces the
  custom `TabBarView` and the "Navigation Bar Glass" section.
- Search: native `.searchable`.
- Typography: Noto Serif display, Plus Jakarta Sans UI, both through
  `AppTheme` with `Font.custom(_:size:relativeTo:)` so Dynamic Type works.
  Remove "Use Georgia for all display/headline text".
- Cards: one card style; no colored accent bars, ghost icons or uppercase
  badge stacks.
- Layout: one title per screen, at the top; inline section headers at
  15–17 pt, never 34 pt black mid-screen.
*Done when* the contract is committed on `setup-onboarding` and both copies
match (`diff AGENTS.md CLAUDE.md` is empty).

## Phase 1 — Quick fixes (ships with the release)

**P1. Bugs and polish.** Agent: `general-purpose`. Branch from
`setup-onboarding`.
- Header in `HomeView.swift`: the `person` and `bell` buttons have empty
  actions `{ }`. Wire `person` to the Profile tab (`coordinator.requestedTab =
  .profile`); remove `bell` until notifications exist.
- One profile symbol: header `person` vs tab bar `person.crop.circle`. Use
  `person.crop.circle` everywhere.
- Remove the active-tab dot in `TabBarView`.
- Reduce the header's 28 pt top padding to sit just under the safe area.
- Replace `Color.black` shadows in `timeCard` and `occasionChip` with
  `AppTheme.shadowColor`.
- Trending Now: `loadTrendingIfNeeded()` in `HomeViewModel` is an empty stub,
  so the section never fills. Hide the whole section, header included, when
  `trendingRecommendations` is empty.
*Owns* the header, `timeCard`, `occasionChip` and `trendingNowSection` in
`HomeView.swift`; `TabBarView.swift`.
*Done when* the full `bilu` scheme passes and screenshots show Explore (Eat and
Drinks) before and after.

## Phase 2 — Redesign (on `redesign/feedback`, after P1 merges)

**R1. Audit sweep.** Agent: `Explore`, very thorough. Confirm every row of the
doc's "Feedback mapped to the code" table still holds, then list anything else
of the same kind: buttons with empty actions, SF Symbols used for one concept
in two ways, hard-coded colors or fonts outside `AppTheme`, and screens with
more than one large title.
*Owns* nothing. *Done when* `build/feedback-redesign/r1/REPORT.md` lists each
item with file:line. Start D1–D3 when it lands.

**D1. Design-system foundation.** Agent: `general-purpose`.
- Bundle Noto Serif and Plus Jakarta Sans (regular, medium, semibold, bold) and
  register them in `Info.plist` (`UIAppFonts`) and the project.
- Add typography tokens to `AppTheme` (`display`, `title`, `headline`, `body`,
  `label`, `caption`), all Dynamic Type aware.
- Add one shared card component, `Views/Components/BiluCard.swift`: white on
  surface, 18 pt continuous corners, `AppTheme.shadowColor`, no accent bar.
- Move existing call sites to the tokens only where the file isn't owned by
  D2 or D3; list the rest for them.
*Owns* `Helpers/AppTheme.swift`, font files, `Info.plist` font keys, project
file font references, `BiluCard.swift`.
*Done when* the app builds, fonts render at the largest Dynamic Type size
(screenshot), and no view outside D2/D3's files uses `.custom("Georgia"`.

**D2. Native navigation.** Agent: `general-purpose`. Runs in parallel with D3
once D1 merges; **must wait for release workstream A**, which owns
`SearchView.swift`.
- Replace the custom tab bar in `ContentView.swift` with a native `TabView`,
  icons only (labels kept for VoiceOver). Delete `TabBarView.swift`.
- Keep today's behavior: every tab keeps its state, re-selecting Explore
  returns it to the start, and the bar hides during the survey
  (`.toolbar(.hidden, for: .tabBar)` instead of `hideTabBar` layout).
- Replace the `UITextField` wrapper in `SearchView` with `.searchable`; update
  `testSearchKeepsKeyboardVisibleAfterEveryCharacter` to match.
*Owns* `ContentView.swift`, `TabBarView.swift`, the search-bar part of
`SearchView.swift`, `biluUITests/`.
*Done when* UI tests pass and screenshots show the tab bar on iOS 26 (Liquid
Glass) and iOS 17.6 or 18.

**D3a. Plan the feed and action flow.** Agent: `Plan`. Read-only; the owner
approves its output before D3b starts.
- **Feed v1 sections**, using data Bilu already has: picks based on Saved and
  Want to Go, saved vibes to re-run, places resolved from shared TikToks (B1),
  and Trending near you. Constraint: opening the feed must not use the user's
  daily free discovery and must not add a paid Gemini, Places or Apify call per
  app open; propose a cached or server-side daily source for anything paid.
- **Intent sheet**: map each preset intent ("Café to lock in", "Food",
  "Drinks", "Late night", "Brunch", and combinations such as Drinks + Late
  night) onto the existing `VibeSelection` occasions and survey steps, so the
  `/recommendations` prompt does not change. Every intent must go through the
  same flow; today "Fresh Baked" skips the sub-flow the other drinks options
  get.
- **Map**: becomes a location chip ("Near you · 2 mi") at the top of the feed
  and results; tapping it opens `HomeMapWidget` in a sheet.
*Done when* `build/feedback-redesign/d3a/PLAN.md` has the section list with
data sources and costs, the intent → `VibeSelection` table, and the file list
for D3b.

**D3b. Build the feed and action button.** Agent: `general-purpose`. Starts
after D1 merges and the owner approves D3a.
- Explore opens on the feed (new `Views/FeedView.swift`), with one title at the
  top and the location chip.
- A floating action button, bottom right above the tab bar, in `AppTheme.sage`,
  opens the intent sheet: a standard `.sheet` with `.medium` and `.large`
  detents (Liquid Glass on iOS 26), combinable intent chips, then the existing
  survey and reveal steps.
- Remove the Eat / Drinks switcher, the time cards and the occasion chips from
  Explore; their options live in the intent sheet.
*Owns* `HomeView.swift`, `HomeViewModel.swift`, `HomeMapWidget.swift`,
`FeedView.swift`, `IntentSheet.swift`, and tests for those view models.
*Done when* unit tests cover the intent mapping, the full scheme passes, and a
screen recording shows open app → feed → action button → intent → results.

**B1. Shared TikTok → place.** Agent: `general-purpose`. Independent of D1–D3;
can start with R1.
- The share extension already queues TikTok links (`PendingTikTokShare`,
  `PendingShareStore`), but `PendingTikTokShare.swift` notes that resolving
  them to a restaurant isn't built.
- Add an Edge Function, `supabase/functions/tiktok-resolve/`, that takes a
  share URL, fetches that one video's caption, transcript URL and anchors
  through the existing Apify path, then runs the extraction and Places lookup
  already in `tiktok-locations` (move the reusable parts into `_shared/`; don't
  fork them).
- In the app, resolve pending shares on launch, show the place in the shared
  row, offer "Add to Want to Go", and record the place's tags as a taste signal
  for the feed.
- Deno tests with mocked Apify, Gemini and Places. **Do not deploy.**
*Owns* `supabase/functions/tiktok-resolve/`, the shared parts moved into
`supabase/functions/_shared/`, `Models/PendingTikTokShare.swift`,
`Services/PendingShareStore.swift`, `Views/Components/PendingSharesRowView.swift`,
a new `Services/TikTokResolveService.swift`.
*Done when* `deno check` and the Deno tests pass, `tiktok-locations` tests still
pass, and the report lists what the owner must deploy.

## Phase 3 — Review (after each Phase 2 branch, before it merges)

**V1. Pre-merge review.** Agent: `general-purpose` running the
`mvp-pre-push-review` skill on the branch diff against `redesign/feedback`.
Report only; the owning agent fixes.

**V2. Accessibility pass on new screens.** Agent: `Explore` (read-only), using
its own simulator. Check the feed, intent sheet, icon-only tabs and location
chip: VoiceOver labels and order, 44×44 targets, the largest Dynamic Type size
with the new fonts, Reduce Motion, and no meaning carried by color alone.
*Done when* `build/feedback-redesign/v2/REPORT.md` ranks issues P0/P1/P2 with
file:line and screenshots.

## Phase 4 — Coordinator wrap-up

Merge in order D1 → D2 → B1 → D3b, rerun the full scheme on
`redesign/feedback`, and collect a before/after screenshot set for the reviewer
in `build/feedback-redesign/summary/`. Then stop and report; the owner decides
when the redesign merges and ships.
