//
//  ProfileHeaderView.swift
//  bilu
//

import SwiftUI

/// The Profile identity block: a breathing emoji avatar, name + handle, and an
/// edit affordance. Layout only — all state lives in ProfileViewModel.
struct ProfileHeaderView: View {
    let avatarEmoji: String
    let displayName: String
    let handle: String
    let hasName: Bool
    let onEdit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppTheme.sageLt)
                    .frame(width: 96, height: 96)
                Text(avatarEmoji)
                    .font(.system(size: 46))
            }
            .scaleEffect(breathScale)
            .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
            .animation(
                reduceMotion
                    ? .linear(duration: 0)
                    : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                value: breathScale
            )
            .onAppear { if !reduceMotion { breathScale = 1.05 } }
            .accessibilityHidden(true)
            .overlay(alignment: .bottomTrailing) {
                Button(action: { Haptics.light(); onEdit() }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(color: AppTheme.shadowColor, radius: 8, x: 0, y: 3)
                        // Keep the 34 pt visual, but give it a 44×44 hit area.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit profile")
                .offset(x: 9, y: 9)
            }

            VStack(spacing: 4) {
                Text(hasName ? displayName : "Add your name")
                    .font(AppTheme.display)
                    .foregroundStyle(hasName ? AppTheme.onSurface : AppTheme.subtle)

                Text(handle)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
