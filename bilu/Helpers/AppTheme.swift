//
//  AppTheme.swift
//  bilu
//
//  Single source of truth for the design system.
//  All views should import these tokens rather than using raw hex strings.
//

import SwiftUI

enum AppTheme {
    // MARK: - Surface hierarchy (Warm Cream — The Foundation)
    /// Page/screen background. #FFF6ED
    static let surface      = Color(hex: "FFF6ED")
    /// Plain white — for card faces that sit on top of `surface`
    static let white        = Color.white

    // MARK: - Brand colors
    /// Primary / Spicy Red — core actions, brand moments. #FF3B30
    static let sage         = Color(hex: "FF3B30")
    /// Light red tint — icon backgrounds, tag chips, progress fill. #FFDAD6
    static let sageLt       = Color(hex: "FFDAD6")
    /// Medium red tint — progress bar mid-state, decorative. #FFB4AB
    static let sageMd       = Color(hex: "FFB4AB")

    /// Occasion card tray backgrounds — warm cream variants
    static let trayPeach    = Color(hex: "fff0e6")   // warm peach
    static let trayMoss     = Color(hex: "fff3d6")   // warm amber-cream
    static let trayAmber    = Color(hex: "ffefd6")   // amber cream
    static let traySlate    = Color(hex: "fdeede")   // light apricot

    /// Mango Orange — secondary / high-priority CTAs, accent sparingly. #FF9500
    static let terracotta   = Color(hex: "FF9500")

    // MARK: - Text hierarchy
    /// Primary text — never 100% black. #1b1c19
    static let onSurface    = Color(hex: "1b1c19")
    /// Secondary / helper text. #635a51
    static let muted        = Color(hex: "635a51")
    /// Tertiary / placeholder text. #8B8070
    static let subtle       = Color(hex: "8B8070")

    // MARK: - Semantic / status
    /// Destructive / closed indicator
    static let destructive  = Color(hex: "DC2626")
    /// Open / positive indicator
    static let openGreen    = Color(hex: "3d6b2b")

    // MARK: - Promoted inline tokens
    /// Badge label on key question cards — dark red
    static let darkSage     = Color(hex: "CC1A10")
    /// Fine-tune extras icon tray background
    static let neutralBg    = Color(hex: "f0ece7")
    /// Fine-tune toggle track when off
    static let toggleOff    = Color(hex: "d4cfc9")

    // MARK: - Elevation helpers
    /// Red-tinted ambient shadow — spec: rgba(255,59,48,0.08)
    static func cardShadow(radius: CGFloat = 16, y: CGFloat = 6) -> some View {
        EmptyView() // Convenience: apply via .shadow(color: AppTheme.shadowColor, ...)
    }
    static let shadowColor  = Color(hex: "FF3B30").opacity(0.08)

    // MARK: - Ghost border (inputs only — "whisper, not a statement")
    static let ghostBorder  = Color(hex: "FF3B30").opacity(0.15)

    // MARK: - Dark surface (Late Night chip)
    /// Near-black for dark-mode chip backgrounds #1C1C1E
    static let darkSurface   = Color(hex: "1C1C1E")

    // MARK: - Trending / badge accent (mint green pop)
    /// "New Entry" badge background — design spec tertiary-fixed-dim #36eaa1
    static let mintBadge     = Color(hex: "36eaa1")
    /// "New Entry" badge text — design spec on-tertiary-fixed #005a3a
    static let mintBadgeText = Color(hex: "005a3a")

    // MARK: - Typography
    // Bundled SIL OFL fonts (bilu/Resources/Fonts, registered in Info.plist
    // UIAppFonts). Every token scales with Dynamic Type via `relativeTo:`.

    enum FontName {
        static let serifRegular  = "NotoSerif-Regular"
        static let serifMedium   = "NotoSerif-Medium"
        static let serifSemiBold = "NotoSerif-SemiBold"
        static let serifBold     = "NotoSerif-Bold"
        static let sansRegular   = "PlusJakartaSans-Regular"
        static let sansMedium    = "PlusJakartaSans-Medium"
        static let sansSemiBold  = "PlusJakartaSans-SemiBold"
        static let sansBold      = "PlusJakartaSans-Bold"

        static let all = [serifRegular, serifMedium, serifSemiBold, serifBold,
                          sansRegular, sansMedium, sansSemiBold, sansBold]
    }

    /// Screen title — Noto Serif 30. One per screen.
    static let display  = Font.custom(FontName.serifRegular, size: 30, relativeTo: .largeTitle)
    /// Secondary serif title — sheet titles, place names, the wordmark. Noto Serif 22.
    static let title    = Font.custom(FontName.serifRegular, size: 22, relativeTo: .title2)
    /// Inline section header — Plus Jakarta Sans SemiBold 17.
    static let headline = Font.custom(FontName.sansSemiBold, size: 17, relativeTo: .headline)
    /// Body / description — Plus Jakarta Sans Regular 15.
    static let body     = Font.custom(FontName.sansRegular, size: 15, relativeTo: .body)
    /// UI labels and buttons — Plus Jakarta Sans Medium 14.
    static let label    = Font.custom(FontName.sansMedium, size: 14, relativeTo: .callout)
    /// Category tags — Plus Jakarta Sans Medium 11; pair with uppercase + tracking(1.0).
    static let caption  = Font.custom(FontName.sansMedium, size: 11, relativeTo: .caption)

    // MARK: - Icons (one SF Symbol per meaning)

    enum Icon {
        /// Saved list (bookmark a place you love).
        static let saved          = "bookmark"
        static let savedFilled    = "bookmark.fill"
        /// Want to Go list.
        static let wantToGo       = "signpost.right"
        static let wantToGoFilled = "signpost.right.fill"
        /// A saved vibe (survey selection you can re-run).
        static let vibe           = "sparkles"
    }

    // MARK: - Convenience aliases
    static var primary: Color   { sage }        // FF3B30 Spicy Red
    static var secondary: Color { terracotta }  // FF9500 Mango Orange
    static var primaryLt: Color { sageLt }      // FFDAD6 light red tint
}
