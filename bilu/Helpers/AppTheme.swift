//
//  AppTheme.swift
//  bilu
//
//  Single source of truth for the design system.
//  All views should import these tokens rather than using raw hex strings.
//

import SwiftUI

/// One color in both appearances. Tokens resolve per trait collection, so every
/// view that uses `AppTheme` follows the system light/dark setting.
struct ThemeSwatch {
    let light: UInt32
    let dark: UInt32
    var lightAlpha: CGFloat = 1
    var darkAlpha: CGFloat = 1

    var uiColor: UIColor {
        let light = light, dark = dark, lightAlpha = lightAlpha, darkAlpha = darkAlpha
        return UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark, alpha: darkAlpha)
                : UIColor(rgb: light, alpha: lightAlpha)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

enum AppTheme {
    /// Light = "Burnt Sienna", dark = "Midnight Café". Contrast pairs are
    /// asserted in `AppThemeContrastTests` (WCAG AA in both appearances).
    enum Palette {
        // Surfaces
        static let background    = ThemeSwatch(light: 0xF4EBDD, dark: 0x0E0A07) // warm ivory / midnight
        static let sheet         = ThemeSwatch(light: 0xF4EBDD, dark: 0x1A120D) // sheets sit one step up in dark
        static let card          = ThemeSwatch(light: 0xFFFAF2, dark: 0x2A1B14) // soft cream / café card
        // Brand
        static let primary       = ThemeSwatch(light: 0xB9563C, dark: 0xC5523A) // burnt sienna fills
        static let primaryInk    = ThemeSwatch(light: 0x9F4A34, dark: 0xE07A5E) // sienna as text
        static let onPrimary     = ThemeSwatch(light: 0xFFFFFF, dark: 0xFFFFFF)
        static let primaryTint   = ThemeSwatch(light: 0xF5E1D7, dark: 0x3B2219)
        static let primaryTintMd = ThemeSwatch(light: 0xE5B4A3, dark: 0x6B3426)
        static let accent        = ThemeSwatch(light: 0xD9A24B, dark: 0xD4A45A) // golden ochre
        static let accentInk     = ThemeSwatch(light: 0x7A5214, dark: 0xD4A45A) // ochre as text
        static let onAccent      = ThemeSwatch(light: 0x291C18, dark: 0x1A120D)
        static let accentTint    = ThemeSwatch(light: 0xF6E6C6, dark: 0x3A2C17)
        // Text
        static let text          = ThemeSwatch(light: 0x291C18, dark: 0xF3E7D9) // espresso / warm paper
        static let textSecondary = ThemeSwatch(light: 0x665A50, dark: 0xB5A797) // cocoa gray
        static let textTertiary  = ThemeSwatch(light: 0x74675C, dark: 0x9C8C7C)
        // Neutrals and trays
        static let neutral       = ThemeSwatch(light: 0xEDE3D4, dark: 0x33241B)
        static let trayPeach     = ThemeSwatch(light: 0xF7E3D6, dark: 0x3A2419)
        static let trayMoss      = ThemeSwatch(light: 0xF3E8CC, dark: 0x33291A)
        static let trayAmber     = ThemeSwatch(light: 0xF5E4C8, dark: 0x3A2C17)
        static let traySlate     = ThemeSwatch(light: 0xEFE2D6, dark: 0x2F241E)
        // Status
        static let destructive   = ThemeSwatch(light: 0xB3261E, dark: 0xF2836B)
        static let positive      = ThemeSwatch(light: 0x3D6B2B, dark: 0x8CC07A)
        // Effects
        static let shadow        = ThemeSwatch(light: 0x291C18, dark: 0x000000, lightAlpha: 0.10, darkAlpha: 0.45)
        static let ghostBorder   = ThemeSwatch(light: 0xB9563C, dark: 0xC5523A, lightAlpha: 0.18, darkAlpha: 0.35)
        /// Scrim behind text laid over photos. Dark in both appearances.
        static let photoScrim    = ThemeSwatch(light: 0x140D0A, dark: 0x000000)
    }

    // MARK: - Surfaces
    /// Page / screen background — warm ivory #F4EBDD · midnight #0E0A07.
    static let surface      = Palette.background.color
    /// Sheet background — ivory · #1A120D.
    static let sheetSurface = Palette.sheet.color
    /// Card face on `surface` — soft cream #FFFAF2 · #2A1B14.
    /// (Historic name: it was plain white before the Burnt Sienna palette.)
    static let white        = Palette.card.color
    static var card: Color  { white }

    // MARK: - Brand
    /// Primary fill — burnt sienna #B9563C · #C5523A. Buttons, FAB, selected
    /// chips, tab tint, icons. (Historic name: was sage green, then red.)
    static let sage         = Palette.primary.color
    /// Sienna for text and links on `surface`/`white`/tints. Darker in light,
    /// lighter in dark, so it passes AA where the fill would not.
    static let primaryInk   = Palette.primaryInk.color
    /// Text and glyphs on a `sage` fill.
    static let onPrimary    = Palette.onPrimary.color
    /// Light sienna tint — icon trays, unselected action chips.
    static let sageLt       = Palette.primaryTint.color
    /// Medium sienna tint — progress mid-state, decorative.
    static let sageMd       = Palette.primaryTintMd.color

    /// Golden ochre — special moments only: featured places, discoveries,
    /// rewards, "free today", the saved-vibe sparkle. Never a default CTA.
    /// (Historic name: was mango orange.)
    static let terracotta   = Palette.accent.color
    /// Ochre as text on light surfaces.
    static let accentInk    = Palette.accentInk.color
    /// Text and glyphs on an ochre fill.
    static let onAccent     = Palette.onAccent.color
    /// Pale ochre — featured badge / reward backgrounds.
    static let accentTint   = Palette.accentTint.color

    /// Tray backgrounds for occasion / hunger / vibe cards.
    static let trayPeach    = Palette.trayPeach.color
    static let trayMoss     = Palette.trayMoss.color
    static let trayAmber    = Palette.trayAmber.color
    static let traySlate    = Palette.traySlate.color

    // MARK: - Text
    /// Primary text — espresso #291C18 · #F3E7D9.
    static let onSurface    = Palette.text.color
    /// Secondary text — cocoa gray #665A50 · #B5A797.
    static let muted        = Palette.textSecondary.color
    /// Tertiary / placeholder text — #74675C · #9C8C7C.
    static let subtle       = Palette.textTertiary.color

    // MARK: - Status
    static let destructive  = Palette.destructive.color
    static let openGreen    = Palette.positive.color

    // MARK: - Neutrals
    /// Badge label on key question cards — sienna ink.
    static let darkSage     = Palette.primaryInk.color
    /// Neutral tray / unselected segment background.
    static let neutralBg    = Palette.neutral.color

    // MARK: - Elevation
    /// Espresso-tinted ambient shadow (black, stronger, in dark).
    static let shadowColor  = Palette.shadow.color
    /// Ghost border — inputs only.
    static let ghostBorder  = Palette.ghostBorder.color
    /// Gradient / pill scrim behind white text on photos and video.
    static let photoScrim   = Palette.photoScrim.color

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

    // MARK: - Semantic aliases (prefer these in new code)
    static var primary: Color   { sage }
    static var accent: Color    { terracotta }
    static var primaryLt: Color { sageLt }
}
