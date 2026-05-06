//
//  ConfettiBurstView.swift
//  bilu
//
//  One-shot radial particle burst — 5 food emojis fanning out from center.
//  Used by the save-vibe celebration in HomeView. Each instance plays once
//  and remains in the view tree as faded-out (parent should re-key with .id()
//  to trigger a fresh burst).
//

import SwiftUI

struct ConfettiBurstView: View {
    /// Food emojis chosen for brand vibe — swap to mascot-themed assets later
    /// if Bilu the Bear ships with paw-print / silhouette art.
    private static let particles: [String] = ["🌶️", "🍕", "🥑", "🍜", "☕️"]

    @State private var animateOut = false

    var body: some View {
        ZStack {
            ForEach(Array(Self.particles.enumerated()), id: \.offset) { index, emoji in
                let angle = Double(index) / Double(Self.particles.count) * 2 * .pi
                Text(emoji)
                    .font(.system(size: 36))
                    .scaleEffect(animateOut ? 1.1 : 0.4)
                    .opacity(animateOut ? 0 : 1)
                    .offset(
                        x: animateOut ? cos(angle) * 160 : 0,
                        y: animateOut ? sin(angle) * 160 : 0
                    )
            }
        }
        .onAppear {
            // ~1.4s total: bigger arc, slower fade so the eye can track each
            // particle. Linear-ish fade-out keeps the emojis readable late in the burst.
            withAnimation(.spring(response: 0.95, dampingFraction: 0.7)) {
                animateOut = true
            }
        }
    }
}

#Preview {
    ZStack {
        AppTheme.surface.ignoresSafeArea()
        Circle()
            .fill(AppTheme.sage)
            .frame(width: 80, height: 80)
            .overlay(ConfettiBurstView())
    }
}
