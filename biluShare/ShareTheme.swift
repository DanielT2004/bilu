import SwiftUI

enum ShareTheme {
    static let surface     = Color(shareHex: "FFF6ED")
    static let white       = Color.white
    static let sage        = Color(shareHex: "FF3B30")
    static let sageLt      = Color(shareHex: "FFDAD6")
    static let terracotta  = Color(shareHex: "FF9500")
    static let onSurface   = Color(shareHex: "1b1c19")
    static let muted       = Color(shareHex: "635a51")
    static let subtle      = Color(shareHex: "8B8070")
    static let shadowColor = Color(shareHex: "FF3B30").opacity(0.08)
}

extension Color {
    init(shareHex: String) {
        let hex = shareHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1.0)
    }
}

struct ShareLoader: View {
    @State private var outerAngle: Double = 0
    @State private var iconAngle: Double = 0
    @State private var orbit1: Double = 0
    @State private var orbit2: Double = 120
    @State private var orbit3: Double = 240

    var body: some View {
        ZStack {
            Circle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 10]))
                .foregroundColor(ShareTheme.sage.opacity(0.22))
                .frame(width: 130, height: 130)
                .rotationEffect(.degrees(outerAngle))

            Circle()
                .fill(ShareTheme.white)
                .frame(width: 104, height: 104)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 3)

            Circle()
                .fill(ShareTheme.sageLt)
                .frame(width: 78, height: 78)

            Circle()
                .fill(ShareTheme.sage)
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                )
                .rotationEffect(.degrees(iconAngle))

            orbitDot(symbol: "fork.knife",    color: ShareTheme.sage,       angle: $orbit1)
            orbitDot(symbol: "flame.fill",    color: ShareTheme.terracotta, angle: $orbit2)
            orbitDot(symbol: "location.fill", color: ShareTheme.sage,       angle: $orbit3)
        }
        .frame(width: 130, height: 130)
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) { outerAngle = 360 }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false))  { iconAngle = -360 }
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false))  { orbit1 += 360 }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false))  { orbit2 -= 360 }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false))  { orbit3 += 360 }
        }
    }

    private func orbitDot(symbol: String, color: Color, angle: Binding<Double>) -> some View {
        Color.clear
            .frame(width: 130, height: 130)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 24, height: 24)
                    .background(ShareTheme.white)
                    .clipShape(Circle())
                    .shadow(color: color.opacity(0.2), radius: 3, y: 2)
                    .offset(x: 55)
            )
            .rotationEffect(.degrees(angle.wrappedValue))
    }
}
