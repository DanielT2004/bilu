//
//  HorizontalOccasionCard.swift
//  bilu
//

import SwiftUI

struct HorizontalOccasionCard: View {
    let title: String
    let time: String
    let desc: String
    let color: OccasionColor
    let action: () -> Void

    enum OccasionColor {
        case amber, purple, teal
        var backgroundColor: Color {
            switch self {
            case .amber: return AppTheme.trayAmber
            case .purple: return AppTheme.trayPeach
            case .teal: return AppTheme.traySlate
            }
        }
        var iconName: String {
            switch self {
            case .amber: return "figure.walk"
            case .purple: return "sofa"
            case .teal: return "wineglass"
            }
        }
        var iconColor: Color {
            switch self {
            case .amber: return AppTheme.terracotta
            case .purple: return AppTheme.sage
            case .teal: return AppTheme.darkSage
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Image(systemName: color.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(color.iconColor)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.onSurface)
                        Text(time)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.accentInk)
                    }
                    Text(desc)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.subtle)
            }
            .padding(34)
            .background(color.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
