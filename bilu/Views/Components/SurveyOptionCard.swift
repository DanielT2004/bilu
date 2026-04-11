//
//  SurveyOptionCard.swift
//  bilu
//
//  Shared template for vibe + hunger survey tiles: image, bottom color band,
//  circular SF Symbol, and title/description.
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
                        .fill(AppTheme.white)
                        .frame(width: 44, height: 44)
                        .shadow(color: AppTheme.shadowColor, radius: 8, y: 4)
                        .overlay(
                            Image(systemName: systemImage)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppTheme.onSurface)
                        )
                        .position(x: size.width / 2, y: size.height * 0.6)

                    SurveyOptionCardBottomLabels(
                        title: title,
                        desc: desc,
                        bottomTextColor: bottomTextColor,
                        cardWidth: size.width,
                        cardHeight: size.height
                    )

                    if isSelected {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.black.opacity(0.06))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            isSelected ? AppTheme.sage : Color.clear,
                            lineWidth: isSelected ? 2.5 : 0
                        )
                )
                .shadow(color: AppTheme.shadowColor, radius: 12, y: 6)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
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
                    AppTheme.sageLt
                @unknown default:
                    AppTheme.sageLt
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            AppTheme.sageLt
        }
    }
}

// MARK: - Bottom labels

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
