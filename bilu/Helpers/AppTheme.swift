//
//  AppTheme.swift
//  bilu
//
//  Single source of truth for the "Tactile Archive" design system.
//  All views should import these tokens rather than using raw hex strings.
//

import SwiftUI

enum AppTheme {
    // MARK: - Surface hierarchy (Cream tones — The Foundation)
    /// Page/screen background. #fbf9f4
    static let surface      = Color(hex: "fbf9f4")
    /// Plain white — for card faces that sit on top of `surface`
    static let white        = Color.white

    // MARK: - Brand colors
    /// Primary / Sage — core actions, brand moments. #516237
    static let sage         = Color(hex: "516237")
    /// Light sage — icon backgrounds, tag chips, progress fill. #e8f0e0
    static let sageLt       = Color(hex: "e8f0e0")
    /// Medium sage — progress bar mid-state, decorative. #c8d4b8
    static let sageMd       = Color(hex: "c8d4b8")

    /// Terracotta — secondary / high-priority CTAs, accent sparingly. #9f402d
    static let terracotta   = Color(hex: "9f402d")

    // MARK: - Text hierarchy
    /// Primary text — never 100% black. #1b1c19
    static let onSurface    = Color(hex: "1b1c19")
    /// Secondary / helper text. #7a8a6a
    static let muted        = Color(hex: "7a8a6a")
    /// Tertiary / placeholder text. #a0aa90
    static let subtle       = Color(hex: "a0aa90")

    // MARK: - Semantic / status
    /// Destructive / closed indicator
    static let destructive  = Color(hex: "DC2626")
    /// Open / positive indicator (reuses sageLt bg + sage text)
    static let openGreen    = Color(hex: "3d6b2b")

    // MARK: - Elevation helpers
    /// Sage-tinted ambient shadow — spec: rgba(81,98,55,0.08)
    static func cardShadow(radius: CGFloat = 16, y: CGFloat = 6) -> some View {
        EmptyView() // Convenience: apply via .shadow(color: AppTheme.shadowColor, ...)
    }
    static let shadowColor  = Color(hex: "516237").opacity(0.08)

    // MARK: - Ghost border (inputs only — "whisper, not a statement")
    static let ghostBorder  = Color(hex: "516237").opacity(0.15)
}
