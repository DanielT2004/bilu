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
            case .amber: return Color(hex: "FEF9E8")
            case .purple: return Color(hex: "F8F1FF")
            case .teal: return Color(hex: "E8FDF9")
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
            case .amber: return Color(red: 245/255, green: 158/255, blue: 11/255)
            case .purple: return Color(red: 168/255, green: 85/255, blue: 247/255)
            case .teal: return Color(red: 20/255, green: 184/255, blue: 166/255)
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
                            .foregroundStyle(Color(hex: "0F172A"))
                        Text(time)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                    }
                    Text(desc)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: "64748B"))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(hex: "94A3B8"))
            }
            .padding(34)
            .background(color.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}
