//
//  SurveyOptionCard.swift
//  bilu
//
//  Shared template for vibe + hunger survey tiles: image, bottom color band,
//  circular SF Symbol, and title/description (HungerCard spacing/fonts as standard).
//

import SwiftUI

struct SurveyOptionCard: View {
    let title: String
    let desc: String
    let systemImage: String
    let imageURL: URL?
    let bottomColor: Color
    let bottomTextColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    surveyBackground(size: size)

                    // Bottom color panel (~40% of card height)
                    Rectangle()
                        .fill(bottomColor)
                        .frame(height: size.height * 0.4)
                        .position(x: size.width / 2, y: size.height * 0.80)

                    // Icon circle between image and panel
                    Circle()
                        .fill(Color.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .overlay(
                            Image(systemName: systemImage)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color(hex: "0F172A"))
                        )
                        .position(x: size.width / 2, y: size.height * 0.6)

                    // Title + description (standard: HungerCard typography & position)
                    SurveyOptionCardBottomLabels(
                        title: title,
                        desc: desc,
                        bottomTextColor: bottomTextColor,
                        cardWidth: size.width,
                        cardHeight: size.height
                    )

                    if isSelected {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.black.opacity(0.06))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? Color(hex: "8B5CF6") : Color.black.opacity(0.04),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            }
            .aspectRatio(0.9, contentMode: .fit)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func surveyBackground(size: CGSize) -> some View {
        if let url = imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Color(hex: "E5E7EB")
                @unknown default:
                    Color(hex: "E5E7EB")
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            Color(hex: "E5E7EB")
        }
    }
}

// MARK: - Bottom labels (single source of truth for fonts & spacing)

private struct SurveyOptionCardBottomLabels: View {
    let title: String
    let desc: String
    let bottomTextColor: Color
    let cardWidth: CGFloat
    let cardHeight: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(bottomTextColor)
                .multilineTextAlignment(.center)
            Text(desc)
                .font(.system(size: 11))
                .foregroundStyle(bottomTextColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(width: cardWidth * 0.9, alignment: .bottom)
        .position(x: cardWidth / 2, y: cardHeight * 0.85)
    }
}
