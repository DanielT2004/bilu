//
//  VibeGlyph.swift
//  bilu
//
//  Procedural visual identity for a completed vibe survey.
//  A small (72×72) abstract composition whose shape is derived from the user's
//  selections — the same vibe always produces the same glyph, but every
//  distinct vibe produces a distinct visual.
//
//  Read-only fields used (do not expand without intentional schema review):
//      • selection.partySize          → number of perimeter circles (clamped 1...6)
//      • selection.occasion           → hue token (sage / terracotta / sageMd / sageLt)
//      • selection.foodFeelings       → center dot diameter (4...14pt)
//      • selection.pricePoints        → number of stacked outer rings (1...4)
//      • selection.selectedVibe       → optional accent rotation offset
//
//  Legacy fields `selection.vibe` and `selection.hunger` are deliberately
//  ignored — they're kept on the model for backend compatibility only.
//

import SwiftUI

struct VibeGlyph: View {
    let selection: VibeSelection
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            // ── Outer rings (price tiers) ─────────────────────────────────
            // 1 ring for $, 2 for $$, etc. — gives "weight" to higher-end vibes.
            ForEach(0..<ringCount, id: \.self) { i in
                Circle()
                    .stroke(perimeterColor.opacity(0.15 + 0.08 * Double(i)), lineWidth: 1)
                    .frame(
                        width:  size - CGFloat(i) * 4,
                        height: size - CGFloat(i) * 4
                    )
            }

            // ── Perimeter circles (party size) ────────────────────────────
            // Distributed evenly around a ring at ~62% of the glyph radius.
            ForEach(0..<perimeterCount, id: \.self) { i in
                let angle = (Double(i) / Double(perimeterCount)) * 2 * .pi + rotationOffset
                Circle()
                    .fill(perimeterColor.opacity(0.7))
                    .frame(width: dotSize, height: dotSize)
                    .blendMode(.multiply)
                    .offset(
                        x: cos(angle) * (size * 0.31),
                        y: sin(angle) * (size * 0.31)
                    )
            }

            // ── Center dot (food-feeling intensity) ───────────────────────
            Circle()
                .fill(perimeterColor)
                .frame(width: centerSize, height: centerSize)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // Decorative — full vibe info is in surrounding text.
    }

    // MARK: - Encoding

    private var perimeterCount: Int {
        max(1, min(6, selection.partySize))
    }

    private var ringCount: Int {
        max(1, min(4, selection.pricePoints.count))
    }

    private var dotSize: CGFloat {
        // Slightly smaller perimeter circles when there are more of them, so
        // they don't crowd. 14pt for 1, 9pt for 6.
        14 - CGFloat(perimeterCount) * 1.0
    }

    private var centerSize: CGFloat {
        // 4pt minimum (no food feelings) → 14pt cap (5+ food feelings).
        let n = min(5, selection.foodFeelings.count)
        return CGFloat(4 + n * 2)
    }

    /// Categorical color from occasion. Stable mapping — same occasion → same color.
    private var perimeterColor: Color {
        switch selection.occasion.lowercased() {
        case let s where s.contains("morning"), let s where s.contains("breakfast"):
            return AppTheme.terracotta
        case let s where s.contains("lunch"):
            return AppTheme.sageMd
        case let s where s.contains("drinks"), let s where s.contains("happy"):
            return AppTheme.darkSage
        case let s where s.contains("dinner"), let s where s.contains("sit"):
            return AppTheme.sage
        default:
            return AppTheme.sage
        }
    }

    /// Selected vibe filter (e.g. "🔥 Trending") rotates the perimeter pattern
    /// slightly so different filters with the same other inputs still differ.
    private var rotationOffset: Double {
        guard !selection.selectedVibe.isEmpty else { return 0 }
        // Stable hash → rotation in radians. Hash collisions are fine.
        let h = abs(selection.selectedVibe.hashValue % 360)
        return Double(h) * .pi / 180
    }
}

#Preview {
    VStack(spacing: 24) {
        VibeGlyph(selection: VibeSelection(
            occasion: "Dinner",
            foodFeelings: ["Spicy", "Comforting"],
            pricePoints: ["$$", "$$$"],
            partySize: 2,
            selectedVibe: "🔥 Trending"
        ))
        VibeGlyph(selection: VibeSelection(
            occasion: "Drinks",
            foodFeelings: ["Light", "Fresh", "Smoky"],
            pricePoints: ["$$$$"],
            partySize: 4,
            selectedVibe: "⭐ Best rated"
        ))
        VibeGlyph(selection: VibeSelection(
            occasion: "Morning",
            foodFeelings: [],
            pricePoints: ["$"],
            partySize: 1
        ))
    }
    .padding(40)
    .background(AppTheme.surface)
}
