//
//  UserView.swift
//  bilu
//

import SwiftUI

private let C = AppTheme.self

struct UserView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Breathing avatar — placeholder for Bilu the Bear mascot art.
                // Continuous slow breath signals "alive but idle"; suppressed
                // when Reduce Motion is on. When mascot ships, swap the
                // Image(systemName:) for Image("BiluAvatar") — layout unchanged.
                ZStack {
                    Circle()
                        .fill(C.sageLt)
                        .frame(width: 88, height: 88)
                    Image(systemName: "person.fill")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(C.sage)
                }
                .scaleEffect(breathScale)
                .animation(
                    reduceMotion
                        ? .linear(duration: 0)
                        : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                    value: breathScale
                )
                .onAppear {
                    if !reduceMotion { breathScale = 1.06 }
                }

                VStack(spacing: 6) {
                    Text("Profile")
                        .font(.custom("Georgia", size: 28))
                        .foregroundColor(C.onSurface)

                    Text("Coming soon")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundColor(C.subtle)
                }

                // Teaser feature list — disabled-style preview of what will live here.
                VStack(spacing: 10) {
                    teaserRow(icon: "bookmark.fill",      label: "Saved vibes")
                    teaserRow(icon: "map.fill",           label: "Your map")
                    teaserRow(icon: "clock.arrow.circlepath", label: "Activity history")
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.surface.ignoresSafeArea())
    }

    private func teaserRow(icon: String, label: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .light))
                .foregroundColor(C.subtle)
                .frame(width: 22)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(C.muted)

            Spacer(minLength: 0)

            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundColor(C.subtle.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(C.white.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    UserView()
}
