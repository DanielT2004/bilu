//
//  LocationPermissionCard.swift
//  bilu
//
//  Soft pre-prompt shown before the cold iOS location dialog. Explains the value
//  so the one-time system prompt is only spent on users who opt in.
//

import SwiftUI

struct LocationPermissionCard: View {
    var onAllow: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            // Dimmed scrim — tap to dismiss
            AppTheme.photoScrim.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    Haptics.light()
                    onDismiss()
                }

            card
                .offset(y: max(0, dragOffset))
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            if value.translation.height > 0 { state = value.translation.height }
                        }
                        .onEnded { value in
                            if value.translation.height > 120 {
                                Haptics.rigid()
                                onDismiss()
                            }
                        }
                )
                .padding(.horizontal, 32)
        }
    }

    private var card: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(AppTheme.primaryInk)
                .frame(width: 52, height: 52)
                .background(AppTheme.sageLt)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Find spots near you")
                .font(AppTheme.title)
                .foregroundColor(AppTheme.onSurface)
                .multilineTextAlignment(.center)

            Text("We'll center the map on where you are so your picks are always close by.")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(AppTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                Button {
                    Haptics.medium()
                    onAllow()
                } label: {
                    Text("Use my location")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppTheme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppTheme.sage)
                        .clipShape(Capsule())
                }
                .buttonStyle(ScalePress())

                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text("Maybe later")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.muted)
                        .padding(.vertical, 6)
                }
                .buttonStyle(ScalePress())
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
    }
}
