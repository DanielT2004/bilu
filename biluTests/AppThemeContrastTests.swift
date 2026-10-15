import SwiftUI
import UIKit
import XCTest
@testable import bilu

/// WCAG 2.x AA for the Burnt Sienna (light) and Midnight Café (dark) palettes:
/// 4.5:1 for body text, 3:1 for large text and UI glyphs.
final class AppThemeContrastTests: XCTestCase {
    private typealias P = AppTheme.Palette

    private struct Pair {
        let name: String
        let foreground: ThemeSwatch
        let background: ThemeSwatch
        let minimum: Double
    }

    private let normalText = 4.5
    private let userInterface = 3.0

    private var pairs: [Pair] {
        [
            Pair(name: "text on background", foreground: P.text, background: P.background, minimum: normalText),
            Pair(name: "text on card", foreground: P.text, background: P.card, minimum: normalText),
            Pair(name: "text on sheet", foreground: P.text, background: P.sheet, minimum: normalText),
            Pair(name: "secondary text on background", foreground: P.textSecondary, background: P.background, minimum: normalText),
            Pair(name: "secondary text on card", foreground: P.textSecondary, background: P.card, minimum: normalText),
            Pair(name: "secondary text on neutral tray", foreground: P.textSecondary, background: P.neutral, minimum: normalText),
            Pair(name: "tertiary text on background", foreground: P.textTertiary, background: P.background, minimum: normalText),
            Pair(name: "tertiary text on card", foreground: P.textTertiary, background: P.card, minimum: normalText),
            Pair(name: "on-primary on primary button", foreground: P.onPrimary, background: P.primary, minimum: normalText),
            Pair(name: "sienna ink on background", foreground: P.primaryInk, background: P.background, minimum: normalText),
            Pair(name: "sienna ink on card", foreground: P.primaryInk, background: P.card, minimum: normalText),
            Pair(name: "sienna ink on sheet", foreground: P.primaryInk, background: P.sheet, minimum: normalText),
            Pair(name: "sienna ink on sienna tint chip", foreground: P.primaryInk, background: P.primaryTint, minimum: normalText),
            Pair(name: "primary fill vs background (UI)", foreground: P.primary, background: P.background, minimum: userInterface),
            Pair(name: "primary fill vs card (UI)", foreground: P.primary, background: P.card, minimum: userInterface),
            Pair(name: "ochre ink on background", foreground: P.accentInk, background: P.background, minimum: normalText),
            Pair(name: "ochre ink on card", foreground: P.accentInk, background: P.card, minimum: normalText),
            Pair(name: "ochre ink on ochre tint", foreground: P.accentInk, background: P.accentTint, minimum: normalText),
            Pair(name: "on-accent on ochre fill", foreground: P.onAccent, background: P.accent, minimum: normalText),
            Pair(name: "destructive on card", foreground: P.destructive, background: P.card, minimum: normalText),
            Pair(name: "positive on card", foreground: P.positive, background: P.card, minimum: normalText),
        ]
    }

    func testKeyPairsMeetWCAGAAInLightAndDark() {
        for pair in pairs {
            let light = Self.contrast(pair.foreground.light, pair.background.light)
            let dark = Self.contrast(pair.foreground.dark, pair.background.dark)
            XCTAssertGreaterThanOrEqual(light, pair.minimum, "Light: \(pair.name) is \(String(format: "%.2f", light)):1")
            XCTAssertGreaterThanOrEqual(dark, pair.minimum, "Dark: \(pair.name) is \(String(format: "%.2f", dark)):1")
        }
    }

    /// The SwiftUI tokens views use resolve to the palette per appearance.
    func testTokensResolvePerAppearance() {
        let tokens: [(Color, ThemeSwatch)] = [
            (AppTheme.surface, P.background), (AppTheme.white, P.card), (AppTheme.sage, P.primary),
            (AppTheme.primaryInk, P.primaryInk), (AppTheme.terracotta, P.accent),
            (AppTheme.onSurface, P.text), (AppTheme.muted, P.textSecondary),
        ]
        for (color, swatch) in tokens {
            XCTAssertEqual(Self.rgb(color, style: .light), swatch.light)
            XCTAssertEqual(Self.rgb(color, style: .dark), swatch.dark)
        }
    }

    func testOwnerPaletteAnchorsAreUnchanged() {
        XCTAssertEqual(P.background.light, 0xF4EBDD)
        XCTAssertEqual(P.card.light, 0xFFFAF2)
        XCTAssertEqual(P.primary.light, 0xB9563C)
        XCTAssertEqual(P.accent.light, 0xD9A24B)
        XCTAssertEqual(P.text.light, 0x291C18)
        XCTAssertEqual(P.textSecondary.light, 0x665A50)
        XCTAssertEqual(P.background.dark, 0x0E0A07)
        XCTAssertEqual(P.sheet.dark, 0x1A120D)
        XCTAssertEqual(P.card.dark, 0x2A1B14)
        XCTAssertEqual(P.primary.dark, 0xC5523A)
        XCTAssertEqual(P.accent.dark, 0xD4A45A)
        XCTAssertEqual(P.text.dark, 0xF3E7D9)
    }

    // MARK: - WCAG math

    static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ rgb: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((rgb >> 16) & 0xFF)
            + 0.7152 * channel((rgb >> 8) & 0xFF)
            + 0.0722 * channel(rgb & 0xFF)
    }

    private static func rgb(_ color: Color, style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
