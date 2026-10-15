//
//  LoadingPulseView.swift
//  bilu
//

import SwiftUI

struct LoadingPulseView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var outerAngle: Double = 0
    @State private var iconAngle: Double = 0
    @State private var orbit1: Double = 0
    @State private var orbit2: Double = 120
    @State private var orbit3: Double = 240
    @State private var breathScale: CGFloat = 1.0

    private let primaryColor   = AppTheme.sage
    private let secondaryColor = AppTheme.terracotta  // ochre: discovery moment
    private let lightBg        = AppTheme.sageLt

    var body: some View {
        ZStack {
            // Outer dashed spinning ring
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 10]))
                .foregroundColor(primaryColor.opacity(0.22))
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(outerAngle))

            // Card-colored mid circle
            Circle()
                .fill(AppTheme.white)
                .frame(width: 154, height: 154)
                .shadow(color: AppTheme.shadowColor, radius: 12, y: 4)

            // Sienna-tint inner circle
            Circle()
                .fill(lightBg)
                .frame(width: 114, height: 114)

            // Primary icon spinning CCW
            Circle()
                .fill(primaryColor)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(AppTheme.onPrimary)
                )
                .rotationEffect(.degrees(iconAngle))

            // Orbiting SF Symbol dots
            orbitDot(sfSymbol: "fork.knife",    color: primaryColor,   angle: $orbit1)
            orbitDot(sfSymbol: "flame.fill",    color: secondaryColor, angle: $orbit2)
            orbitDot(sfSymbol: "location.fill", color: primaryColor,   angle: $orbit3)
        }
        .frame(width: 190, height: 190)
        .scaleEffect(breathScale)
        .animation(
            reduceMotion
                ? .linear(duration: 0)
                : .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
            value: breathScale
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                outerAngle = 360
            }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                iconAngle = -360
            }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                orbit1 = orbit1 + 360
            }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                orbit2 = orbit2 - 360
            }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                orbit3 = orbit3 + 360
            }
            // Breathing pulse — applied to the whole spinner so it reads as one
            // organism. The .animation(value: breathScale) modifier above drives
            // the tween; this kicks off the state change to start the cycle.
            breathScale = 1.25
        }
    }

    private func orbitDot(sfSymbol: String, color: Color, angle: Binding<Double>) -> some View {
        Color.clear
            .frame(width: 190, height: 190)
            .overlay(
                Image(systemName: sfSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.white)
                    .clipShape(Circle())
                    .shadow(color: color.opacity(0.2), radius: 4, y: 2)
                    .offset(x: 80)
            )
            .rotationEffect(.degrees(angle.wrappedValue))
    }
}
