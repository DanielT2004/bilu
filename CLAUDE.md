# bilu — AI Coding Rules

This document is the authoritative design contract for the **bilu** app. Every AI-generated change must conform to these rules. Treat violations as bugs.

---

## Design System: Burnt Sienna / Midnight Café

The creative north star is **an independent food magazine meets a neighborhood café** — editorial, warm, slightly moody, premium but not intimidating. Bilu is recognizable through warmth, not brightness. Cream dominates, espresso anchors the type, burnt sienna marks actions, and golden ochre appears only for special moments. Light mode is "Burnt Sienna"; dark mode is "Midnight Café". Both follow the system setting.

---

## 1. Color Tokens — Use `AppTheme` Only

All colors live in `bilu/Helpers/AppTheme.swift`. **Never introduce raw hex strings or fixed colors (`Color.white`, `Color.black`, `.white` backgrounds) in view files.** Every token is adaptive (`AppTheme.Palette` holds a light and a dark value per role and resolves per trait collection), so views that use tokens get dark mode for free. If a new semantic color is needed, add a swatch to `AppTheme.Palette` first, with both values, and add its key pairs to `AppThemeContrastTests`.

Several token names are historic (the palette changed underneath them); the role column is what counts. Prefer the semantic aliases (`primary`, `accent`, `card`) in new code.

| Token | Light (Burnt Sienna) | Dark (Midnight Café) | Role |
|---|---|---|---|
| `AppTheme.surface` | `#F4EBDD` warm ivory | `#0E0A07` | Page / screen background |
| `AppTheme.sheetSurface` | `#F4EBDD` | `#1A120D` | Sheet backgrounds (one step up in dark) |
| `AppTheme.white` (`card`) | `#FFFAF2` soft cream | `#2A1B14` | Card faces, elevated surfaces |
| `AppTheme.sage` (`primary`) | `#B9563C` burnt sienna | `#C5523A` | Primary **fill**: buttons, FAB, selected chips, toggles, map pins |
| `AppTheme.primaryInk` | `#9F4A34` | `#E07A5E` | Sienna as **text/icons** on surfaces: links, "Run it back", distances, section icons, tab tint |
| `AppTheme.onPrimary` | `#FFFFFF` | `#FFFFFF` | Text and glyphs on a `sage` fill |
| `AppTheme.sageLt` | `#F5E1D7` | `#3B2219` | Sienna tint: icon trays, unselected action chips |
| `AppTheme.sageMd` | `#E5B4A3` | `#6B3426` | Progress mid-state, decorative |
| `AppTheme.terracotta` (`accent`) | `#D9A24B` golden ochre | `#D4A45A` | Special moments only (see below) |
| `AppTheme.accentInk` | `#7A5214` | `#D4A45A` | Ochre as text ("1 free today", pro-tip numbers) |
| `AppTheme.onAccent` | `#291C18` | `#1A120D` | Text on an ochre fill |
| `AppTheme.accentTint` | `#F6E6C6` | `#3A2C17` | Reward / featured badge backgrounds |
| `AppTheme.onSurface` | `#291C18` espresso | `#F3E7D9` | All primary text |
| `AppTheme.muted` | `#665A50` cocoa gray | `#B5A797` | Secondary / helper text |
| `AppTheme.subtle` | `#74675C` | `#9C8C7C` | Tertiary / placeholder text |
| `AppTheme.neutralBg` | `#EDE3D4` | `#33241B` | Neutral trays, unselected segments |
| `AppTheme.destructive` | `#B3261E` | `#F2836B` | Closed / destructive |
| `AppTheme.openGreen` | `#3D6B2B` | `#8CC07A` | Open / positive |
| `AppTheme.shadowColor` | `#291C18` @ 10% | `#000000` @ 45% | Ambient card shadow (espresso-tinted) |
| `AppTheme.ghostBorder` | `#B9563C` @ 18% | `#C5523A` @ 35% | Input field edges only |
| `AppTheme.photoScrim` | `#140D0A` | `#000000` | Gradients / pills behind white text on photos and video |

### Contrast (WCAG AA, asserted by `biluTests/AppThemeContrastTests`)
| Pair | Light | Dark |
|---|---|---|
| Text on background / card | 13.96 / 15.87 | 16.19 / 13.63 |
| Secondary text on background / card | 5.65 / 6.43 | 8.39 / 7.06 |
| White on primary button | 4.71 | 4.52 |
| Sienna ink on background / card | 5.07 / 5.77 | 6.68 / 5.62 |
| Ochre ink on background | 5.84 | 8.69 |
| Espresso on ochre fill | 7.24 | 8.15 |

`AppTheme.sage` is a fill, not a text color: as text it is only 3.99:1 on ivory (light) and 3.67:1 on cards (dark). Use `primaryInk` for sienna text and icons on surfaces.

### Where each color goes
- **Cream / ivory dominates.** Most of every screen is `surface` and `white` cards.
- **Espresso anchors typography.** All titles and body text are `onSurface` / `muted`.
- **Sienna marks actions:** the FAB, "Find spots" and other primary buttons, links, selected chips, the tab tint.
- **Ochre is for special moments only:** the saved-vibe sparkle, rewards / Discovery Pass / "free today", featured badges, star ratings, the "visited" state. Never a default CTA, and never text on cream (use `accentInk`).
- **Photos and video** keep white text on a `photoScrim` gradient in both modes; the full-screen video player stays black.

### Forbidden colors
- Raw hex in views, `Color.white` / `Color.black` / `.white` backgrounds. Use tokens; white is allowed only as text on a sienna fill (`onPrimary`) or over photos/video.
- `#FF3B30` spicy red and `#FF9500` mango orange — replaced by burnt sienna and golden ochre.
- `#8B5CF6` purple — never.
- `#0F172A` / `#1C1C1E` near-black — use `AppTheme.onSurface`.
- `#64748B` slate gray — use `AppTheme.muted`.
- Pure `Color.black` / `Color.gray` for shadows — use `AppTheme.shadowColor`.
- Translucent white text on sienna (`.white.opacity(0.7)`) — it fails AA; use full `onPrimary`.
- `.preferredColorScheme(.light)` or `UIUserInterfaceStyle` — the app follows the system appearance.

---

## 2. The No-Line Rule

**Never use a 1px solid border to define a section or card.** Boundaries must be *felt*, not seen.

### What to do instead
- **Background shift**: cards use `AppTheme.white` (soft cream / café brown) on `AppTheme.surface` — the tonal step provides separation in both modes.
- **Ambient shadow**: `.shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)` for cards that need lift.
- **Negative space**: generous `padding` between elements creates visual islands.

### The only exception
Input fields may use a ghost border on focus: `.overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.ghostBorder, lineWidth: 1))`.

### In code: forbidden patterns
```swift
// ❌ Never do this
.overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.2), lineWidth: 1))
.overlay(Rectangle().fill(Color.gray).frame(height: 0.5))  // divider lines

// ✅ Do this instead
.shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
```

---

## 3. Typography

| Role | Font | Size | Weight | Notes |
|---|---|---|---|---|
| Display / screen title | Noto Serif | 28–30pt | Regular | Tight line spacing; one per screen |
| Section header (inline) | Plus Jakarta Sans | 15–17pt | `.semibold` | Never 34pt black mid-screen |
| UI labels/buttons | Plus Jakarta Sans | 13–15pt | `.medium` | — |
| Body / description | Plus Jakarta Sans | 13–15pt | Regular | — |
| Category tags | Plus Jakarta Sans | 10–11pt | `.medium` | `.textCase(.uppercase)`, `.tracking(1.0)` |

Both fonts are SIL OFL licensed, bundled with the app, and used **only through `AppTheme` typography tokens** built with `Font.custom(_:size:relativeTo:)`, so Dynamic Type works. Never call `.custom("…")` or hard-code a font in a view. Tokens: `AppTheme.display`, `.title`, `.headline`, `.body`, `.label`, `.caption`. No italic faces are bundled, so don't use `.italic()` on them. Remaining `Georgia` and `.system(size:)` call sites are being migrated; add no new ones.

### One title per screen
Each screen has exactly one title, at the top. Sections below it use the inline section-header style above.

### Labels must be catalogue-style
```swift
// Correct section label style:
Text("What's the occasion?")
    .font(.system(size: 10, weight: .medium))
    .tracking(1.0)
    .textCase(.uppercase)
    .foregroundColor(AppTheme.muted)
```

---

## 4. Corner Radii — Organic, Never Hard

| Context | Radius | SwiftUI |
|---|---|---|
| Full-width cards | 18–20pt | `.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))` |
| Modals / sheets | 24pt | — |
| Buttons | Pill / Capsule | `.clipShape(Capsule())` or `cornerRadius: 999` |
| Small chips / badges | 8pt | — |
| Input fields | 10pt | — |
| Icon trays | 10–12pt | — |

**Never use `cornerRadius: 0` (hard corners) on user-facing surfaces.**

---

## 4a. Cards — One Style

There is one card style: `AppTheme.white` on `AppTheme.surface`, 18pt continuous corners, `AppTheme.shadowColor` shadow when it needs lift. Use the shared card component (`Views/Components/BiluCard.swift`) instead of restyling cards per screen. A card may lead with a small, cropped photo (feed place cards) only when the photo URL is already stored on the model — never fetch photos or call Places just to decorate a card.

**Never on cards:** colored accent bars, faint "ghost" background icons, or stacks of uppercase badges. These read as generic AI-template UI.

---

## 5. Elevation — Tonal Layering, Not Shadows Everywhere

Depth comes from stacking surface tiers:

```
Base page:          AppTheme.surface       (#F4EBDD · #0E0A07)
Sheets:             AppTheme.sheetSurface  (#F4EBDD · #1A120D)
Cards / containers: AppTheme.white         (#FFFAF2 · #2A1B14)
Floating overlays:  .ultraThinMaterial  (blur + tint)
```

Only floating elements (FABs, modals, nav bars) may use `backdrop-filter` / `.ultraThinMaterial`. Use `.shadow(color: AppTheme.shadowColor, ...)` only when a card needs clear visual lift.

---

## 6. Buttons — Pebble Shape

All buttons are pill-shaped (Capsule or `cornerRadius: 999`).

```swift
// Primary CTA (full width)
.foregroundStyle(AppTheme.onPrimary)
.frame(maxWidth: .infinity)
.padding(.vertical, 15)
.background(AppTheme.sage)
.clipShape(Capsule())

// Special-moment state (saved vibe, visited, reward) — ochre with espresso text
.foregroundStyle(AppTheme.onAccent)
.background(AppTheme.terracotta)
.clipShape(Capsule())
```

**On press:** scale to 96% with a 0.12s ease-in-out. Use the `ScalePress` ButtonStyle already in the project.

---

## 7. Animation Catalog

### Page / Step Transitions
When navigating between survey steps, use a direction-aware slide + fade:

```swift
// In HomeView, track direction:
@State private var stepForward = true

// Apply to stepContent:
stepContent
    .id(viewModel.step)
    .transition(.asymmetric(
        insertion: .move(edge: stepForward ? .trailing : .leading).combined(with: .opacity),
        removal:   .move(edge: stepForward ? .leading  : .trailing).combined(with: .opacity)
    ))
    .animation(.spring(response: 0.38, dampingFraction: 0.86), value: viewModel.step)

// Detect direction in .onChange:
.onChange(of: viewModel.step) { newStep in
    let allSteps = Step.allCases
    if let old = allSteps.firstIndex(of: previousStep),
       let new = allSteps.firstIndex(of: newStep) {
        stepForward = new > old
    }
    previousStep = newStep
}
```

### Sheet / Modal Presentation
Sheets slide up from the bottom — this is the default iOS behavior. Use `.sheet(item:)` for all full-screen overlays (restaurant detail, etc.). Never push a full-screen NavigationLink when a sheet suffices.

### Card Selection
Use spring animation for selection state changes:
```swift
.animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
```

### List / Reveal Stagger
When revealing a list of cards (results screen), stagger their appearance:
```swift
ForEach(Array(items.enumerated()), id: \.offset) { index, item in
    ItemCard(item: item)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.07), value: items.count)
}
```

### Loading / Pulse
Spinning rings use `.linear(duration: N).repeatForever(autoreverses: false)`. Orbit items use counter-rotation for visual interest. Do not replace this pattern without design review.

### Gesture-Driven Dismissal
Full-screen overlays and sheets must respond to a downward drag — not just a tap on an X button. This is the standard set by iOS Photos, TikTok, and Instagram. Use this pattern on: video feed, restaurant detail sheet, any full-screen overlay.

```swift
@GestureState private var dragOffset: CGFloat = 0
@Environment(\.dismiss) private var dismiss

var body: some View {
    content
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.translation.height > 0 { state = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                }
        )
}
```

### Native Navigation and Search
- **Tab bar:** the native `TabView`, icons only (keep text labels for VoiceOver), no active-tab dot. Hide it with `.toolbar(.hidden, for: .tabBar)`. Do not build custom tab bars.
- **Search:** native `.searchable`, not a custom `UITextField` wrapper.
- **Sheets:** standard `.sheet` with `.presentationDetents([.medium, .large])` where a partial sheet fits.
- **Liquid Glass:** native tab bars and sheets pick it up automatically on iOS 26 (deployment target stays 17.6). Any direct `glassEffect` call goes behind `if #available(iOS 26, *)` with an `.ultraThinMaterial` fallback.
- **Sticky headers** use `.ultraThinMaterial` — never a solid white/cream background with a hairline border.

---

## 8. Spacing Scale

| Token | Value | Use |
|---|---|---|
| `xs` | 4pt | Gap between label and body text |
| `sm` | 8–9pt | Gap between cards in a grid |
| `md` | 14–16pt | Card internal padding |
| `lg` | 20pt | Horizontal page margin |
| `xl` | 24pt | Section separation |
| `xxl` | 40–52pt | Top safe area, hero breathing room |

When in doubt, add 20% more space. Premium design requires "wasteful" space.

---

## 9. Do's and Don'ts

### Do
- Embrace asymmetry — don't center everything
- Let cream dominate; keep espresso for type, sienna for actions, ochre for special moments
- Use `AppTheme.sage` for action fills with `onPrimary` text, and `primaryInk` for sienna text, links and icons
- Use ochre (`terracotta` / `accentInk` / `accentTint`) only for the saved-vibe sparkle, rewards, Discovery Pass, "free today", featured badges and ratings
- Use `sageLt` / `sageMd` for icon trays, not gray
- Check every new screen in light and dark mode
- Use the `AppTheme` typography tokens (Noto Serif display, Plus Jakarta Sans UI) for all text
- Keep one title per screen, at the top
- Use native `TabView`, `.searchable` and sheets
- Use `.continuous` curve style on `RoundedRectangle` for a softer feel
- Stagger list reveals with `.delay()` for a curated, editorial feel
- Add `.shadow(color: AppTheme.shadowColor, radius: 16, y: 6)` to floating cards
- Add haptic feedback to every state-changing tap
- Implement swipe-to-dismiss on all sheet presentations and full-screen overlays
- Ask "what gesture would feel natural here?" before adding a UI button
- Use `DragGesture` + `@GestureState` for fluid, physics-feeling dismiss patterns

### Don't
- Make every component brown or sienna — most surfaces stay cream
- Use ochre for ordinary CTAs, or as text on cream (use `accentInk`)
- Use `AppTheme.sage` as small text on surfaces (use `primaryInk`)
- Hard-code `Color.white`, `Color.black` or hex in views, or force a color scheme
- Use purple (`#8B5CF6`) anywhere
- Use `Color.black` or `Color.gray` for shadows
- Add accent bars, ghost icons or uppercase badge stacks to cards
- Use one SF Symbol for two concepts, or two symbols for one concept (use `AppTheme.Icon`: `bookmark` = Saved, `signpost.right` = Want to Go, `sparkles` = saved vibe)
- Ship a button with an empty action
- Use `1px` stroke borders on cards or section dividers
- Use hard corners (`cornerRadius: 0–4`) on cards
- Use `NavigationStack` push transitions when a sheet would work
- Summarize changes at the end of responses (user can read the diff)
- Add features, error handling, or abstractions beyond what was asked
- Make dismissal button-only — pair every X button with a swipe-down gesture
- Add haptics to purely visual or decorative interactions
- Put API calls or data logic inside View `body` or `onAppear` — route through ViewModel

---

## 10. File Conventions

---

## 11. Interaction Philosophy — Touch First

bilu is a tactile app. Every screen should feel alive under a thumb. The design bar is iOS Photos, TikTok, and Instagram — apps where gestures are the primary language, not buttons.

### The Gesture-First Principle
Before adding any button, ask: **"How would a user naturally do this with their thumb?"**

- A video player → swipeable down to dismiss, not just X-button closeable
- A restaurant detail sheet → draggable down to close
- A card result → swipeable to save/skip
- A settings panel → edge-swipeable back

If there's a natural gesture, implement the gesture *first*. The button is a fallback affordance, not the primary interaction.

### Gesture Catalog

| Gesture | When to use |
|---|---|
| Swipe down | Dismiss any full-screen overlay or sheet |
| Swipe left / right | Navigate between pages, dismiss cards |
| Long press | Reveal contextual actions on cards |
| Pinch | Expand/collapse maps or image galleries |
| Drag | Move, reorder, or adjust spatial elements |

### Reference Apps
When in doubt, ask: "How does TikTok/Instagram/iOS Photos handle this?" Then match that interaction density. Never settle for a modal alert when a swipe would do.

---

## 12. Haptic Feedback — Make It Feel Real

Haptics are the tactile layer of the design. Every state-changing interaction should have a corresponding physical pulse. The app must feel like it responds to every touch.

### Haptic Catalog

```swift
// Selection / toggle on (card tap, option select, toggle)
UIImpactFeedbackGenerator(style: .light).impactOccurred()

// Primary action confirmed (Submit, Take Me There, New Vibe)
UIImpactFeedbackGenerator(style: .medium).impactOccurred()

// Success / milestone (results revealed, booking confirmed)
UINotificationFeedbackGenerator().notificationOccurred(.success)

// Error / destructive warning
UINotificationFeedbackGenerator().notificationOccurred(.error)

// Drag threshold crossed (swipe-to-dismiss snap point)
UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

// Soft interaction (scroll snap, subtle nudge)
UIImpactFeedbackGenerator(style: .soft).impactOccurred()
```

### Rules
- Every tap that **changes state** → `.light` impact
- Primary CTAs ("Submit", "Take Me There") → `.medium` impact  
- Results reveal → `.success` notification
- Drag crosses a dismiss threshold → `.rigid` impact
- **Never** add haptics to scroll, passive animation, or purely decorative transitions
- Wrap generators in a helper or call inline — do not create persistent `UIImpactFeedbackGenerator` instances as stored properties

---

## 13. Code Quality Principles

### Architecture
- **ViewModels own logic, Views own layout** — no API calls, data transforms, or business logic inside `View` structs
- **State flows down, actions flow up** — use `@Binding` and closures to keep child views stateless
- **One source of truth** — if `HomeViewModel` owns `step`, no View may hold a parallel `@State var currentStep`

### Naming
- Prefer readable over terse: `isLoadingResults` not `isFetching`, `selectedOccasion` not `occ`
- Boolean states use `is` / `has` / `should` prefixes: `isExpanded`, `hasLoaded`, `shouldShowMap`

### Safety
- **No force unwraps** (`!`) on user-facing data paths — use `guard let` or `if let`
- Avoid `try!` outside test code

### Cleanliness
- Remove unused variables, commented-out code blocks, and `TODO` stubs before considering a feature done
- Don't leave debug `print()` statements in committed code
- Don't add `// MARK:` sections unless a file exceeds ~200 lines and genuinely benefits from navigation

| What | Where |
|---|---|
| Color / theme tokens | `bilu/Helpers/AppTheme.swift` |
| Shared button styles | Define inside `HomeView.swift` (e.g. `ScalePress`) or promote to `AppTheme` if reused |
| View components | `bilu/Views/Components/` |
| Main screens | `bilu/Views/` |
| Data models | `bilu/Models/` |
| API / service logic | `bilu/Services/` |
