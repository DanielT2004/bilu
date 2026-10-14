//
//  ProfileStatsView.swift
//  bilu
//

import SwiftUI

/// Three playful, borderless stat tiles (Saved / Want to Go / Cuisines).
/// Counts are passed in from the live @Query results in UserView.
struct ProfileStatsView: View {
    let savedCount: Int
    let wantToGoCount: Int
    let cuisineCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            stat(value: savedCount, label: "Saved", index: 0)
            divider
            stat(value: wantToGoCount, label: "Want to Go", index: 1)
            divider
            stat(value: cuisineCount, label: "Cuisines", index: 2)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion { appeared = true; return }
            withAnimation(AnimationProfile.listReveal.animation(reduceMotion: false)) { appeared = true }
        }
    }

    private func stat(value: Int, label: String, index: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(AppTheme.display)
                .foregroundStyle(AppTheme.onSurface)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(
            AnimationProfile.listReveal.animation(reduceMotion: reduceMotion).delay(Double(index) * 0.07),
            value: appeared
        )
    }

    // Tonal separator — a soft tinted gap, not a hairline rule.
    private var divider: some View {
        Capsule()
            .fill(AppTheme.sageLt.opacity(0.6))
            .frame(width: 2, height: 28)
    }
}
