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

    // MARK: - Convenience aliases
    static var primary: Color   { sage }        // FF3B30 Spicy Red
    static var secondary: Color { terracotta }  // FF9500 Mango Orange
    static var primaryLt: Color { sageLt }      // FFDAD6 light red tint
}
