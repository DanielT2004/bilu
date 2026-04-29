//
//  LoadingPulseView.swift
//  bilu
//

import SwiftUI

struct LoadingPulseView: View {
    @State private var outerAngle: Double = 0
    @State private var iconAngle: Double = 0
    @State private var orbit1: Double = 0
    @State private var orbit2: Double = 120
    @State private var orbit3: Double = 240

    private let primaryColor   = AppTheme.sage        // FF3B30 Spicy Red
    private let secondaryColor = AppTheme.terracotta  // FF9500 Mango Orange
    private let lightBg        = AppTheme.sageLt      // FFDAD6 light red tint

    var body: some View {
        ZStack {
            // Outer dashed spinning ring
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 10]))
                .foregroundColor(primaryColor.opacity(0.22))
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(outerAngle))

            // White mid circle
            Circle()
                .fill(Color.white)
                .frame(width: 154, height: 154)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

            // Light red inner circle
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
                        .foregroundColor(.white)
                )
                .rotationEffect(.degrees(iconAngle))

            // Orbiting SF Symbol dots
            orbitDot(sfSymbol: "fork.knife",    color: primaryColor,   angle: $orbit1)
            orbitDot(sfSymbol: "flame.fill",    color: secondaryColor, angle: $orbit2)
            orbitDot(sfSymbol: "location.fill", color: primaryColor,   angle: $orbit3)
        }
        .frame(width: 190, height: 190)
        .onAppear {
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
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: color.opacity(0.2), radius: 4, y: 2)
                    .offset(x: 80)
            )
            .rotationEffect(.degrees(angle.wrappedValue))
    }
}
