# bilu — AI Coding Rules

This document is the authoritative design contract for the **bilu** app. Every AI-generated change must conform to these rules. Treat violations as bugs.

---

## Design System: The Dopamine Engine

The creative north star is **"app-as-a-dopamine-inducing discovery engine"** — high-energy, modern, food-forward. Every screen should feel alive, vibrant, and magnetic. If it feels calm and muted, add more red and remove a line.

---

## 1. Color Tokens — Use `AppTheme` Only

All colors live in `bilu/Helpers/AppTheme.swift`. **Never introduce raw hex strings in view files.** If a new semantic color is needed, add it to `AppTheme` first.

| Token | Hex | Role |
|---|---|---|
| `AppTheme.surface` | `#FFF6ED` | Page / screen background |
| `AppTheme.white` | `#ffffff` | Card faces, elevated surfaces |
| `AppTheme.sage` | `#FF3B30` | Primary — core actions, brand (Spicy Red) |
| `AppTheme.sageLt` | `#FFDAD6` | Icon tray backgrounds, chips (light red tint) |
| `AppTheme.sageMd` | `#FFB4AB` | Progress bar mid, decorative (medium red tint) |
| `AppTheme.terracotta` | `#FF9500` | Secondary CTA — Mango Orange, use sparingly |
| `AppTheme.onSurface` | `#1b1c19` | All primary text |
| `AppTheme.muted` | `#635a51` | Secondary / helper text |
| `AppTheme.subtle` | `#8B8070` | Tertiary / placeholder text |
| `AppTheme.shadowColor` | `#FF3B30` @ 8% | Ambient card shadow (red-tinted) |
| `AppTheme.ghostBorder` | `#FF3B30` @ 15% | Input field edges only |

### Forbidden colors
- `#8B5CF6` purple — never. Replace with `AppTheme.terracotta`.
- `#0F172A` / `#1C1C1E` near-black — use `AppTheme.onSurface`.
- `#64748B` slate gray — use `AppTheme.muted`.
- Pure `Color.black` / `Color.gray` for shadows — use `AppTheme.shadowColor`.
- `#516237` sage green — replaced by `AppTheme.sage` (Spicy Red).
- `#9f402d` old terracotta — replaced by `AppTheme.terracotta` (Mango Orange).

---

## 2. The No-Line Rule

**Never use a 1px solid border to define a section or card.** Boundaries must be *felt*, not seen.

### What to do instead
- **Background shift**: cards use `AppTheme.white` on `AppTheme.surface` background — the cream/white contrast provides sufficient separation.
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
| Display / brand | `Georgia` (target: Noto Serif) | 28–30pt | Regular | Tight line spacing |
| Section headline | `Georgia` | 24–26pt | Regular | — |
| UI labels/buttons | `.system` (target: Plus Jakarta Sans) | 13–15pt | `.medium` | — |
| Body / description | `.system` | 13–15pt | `.light` | — |
| Category tags | `.system` | 10–11pt | `.medium` | `.textCase(.uppercase)`, `.tracking(1.0)` |

**Note:** Noto Serif and Plus Jakarta Sans are the target fonts per the design spec. Add them as project resources and update `AppTheme` when available. Until then, Georgia and SF Pro are the functional equivalents.

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

## 5. Elevation — Tonal Layering, Not Shadows Everywhere

Depth comes from stacking surface tiers:

```
Base page:          AppTheme.surface    (#fbf9f4)
Cards / containers: AppTheme.white      (#ffffff)
Floating overlays:  .ultraThinMaterial  (blur + tint)
```

Only floating elements (FABs, modals, nav bars) may use `backdrop-filter` / `.ultraThinMaterial`. Use `.shadow(color: AppTheme.shadowColor, ...)` only when a card needs clear visual lift.

---

## 6. Buttons — Pebble Shape

All buttons are pill-shaped (Capsule or `cornerRadius: 999`).

```swift
// Primary CTA (full width)
.foregroundColor(.white)
.frame(maxWidth: .infinity)
.padding(.vertical, 15)
.background(AppTheme.sage)
.clipShape(Capsule())

// Secondary / high-priority CTA (use sparingly)
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

### Navigation Bar Glass
The bottom tab bar and sticky headers use `.ultraThinMaterial` for the frosted-glass effect — never a solid white/cream background with a hairline border.

```swift
// Bottom nav bar:
.background(.ultraThinMaterial)
// Remove any Rectangle() divider above it
```

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
- Use `sageLt` / `sageMd` for icon trays, not gray
- Use `AppTheme.terracotta` for high-urgency CTAs ("Take Me There", "New Vibe")
- Use `Georgia` for all display/headline text
- Use `.continuous` curve style on `RoundedRectangle` for a softer feel
- Stagger list reveals with `.delay()` for a curated, editorial feel
- Add `.shadow(color: AppTheme.shadowColor, radius: 16, y: 6)` to floating cards
- Add haptic feedback to every state-changing tap
- Implement swipe-to-dismiss on all sheet presentations and full-screen overlays
- Ask "what gesture would feel natural here?" before adding a UI button
- Use `DragGesture` + `@GestureState` for fluid, physics-feeling dismiss patterns

### Don't
- Use purple (`#8B5CF6`) anywhere
- Use `Color.black` or `Color.gray` for shadows
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
