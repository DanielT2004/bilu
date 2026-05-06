//
//  Haptics.swift
//  bilu
//
//  Single chokepoint for haptic feedback and animation profiles.
//  Replaces inline UIImpactFeedbackGenerator(...) / UINotificationFeedbackGenerator()
//  call sites so reduceMotion gating and tweaks live in one place.
//

import UIKit
import SwiftUI

enum Haptics {
    /// Selection / toggle on. Light pulse.
    static func light()   { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// Primary action confirmed (Submit, Take Me There, dismiss threshold).
    static func medium()  { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// Drag threshold crossed, escalation beat.
    static func rigid()   { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    /// Soft nudge — rare; reserve for scroll snap, gentle confirm.
    static func soft()    { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    /// Milestone reached (results revealed, vibe saved, bookmark committed).
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Error / destructive warning.
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

/// Animation curves used across the app, tied to the existing spring catalog.
/// Returns `.linear(duration: 0)` when reduceMotion is on so callers don't branch.
enum AnimationProfile {
    case selection            // .spring 0.25 / 0.7  — toggles, checkboxes
    case stepTransition       // .spring 0.38 / 0.86 — step + reveal-phase changes
    case listReveal           // .spring 0.40 / 0.80 — staggered card reveals
    case fastFeedback         // .spring 0.28 / 0.72 — sub-option picks
    case burst                // .spring 0.55 / 0.62 — overshoot fan-out (confetti, celebrations)

    func animation(reduceMotion: Bool) -> Animation {
        if reduceMotion { return .linear(duration: 0) }
        switch self {
        case .selection:      return .spring(response: 0.25, dampingFraction: 0.7)
        case .stepTransition: return .spring(response: 0.38, dampingFraction: 0.86)
        case .listReveal:     return .spring(response: 0.40, dampingFraction: 0.80)
        case .fastFeedback:   return .spring(response: 0.28, dampingFraction: 0.72)
        case .burst:          return .spring(response: 0.55, dampingFraction: 0.62)
        }
    }
}
