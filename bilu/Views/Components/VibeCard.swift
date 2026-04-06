//
//  VibeCard.swift
//  bilu
//

import SwiftUI

struct VibeCard: View {
    let title: String
    let desc: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    private var backgroundURL: URL? {
        let urlString: String
        switch title {
        case "Aesthetic":
            urlString = "https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=900&q=80"
        case "Intimate":
            urlString = "https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=900&q=80"
        case "Trendy", "Trending":
            urlString = "https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=900&q=80"
        case "Authentic", "Local and authentic":
            urlString = "https://images.unsplash.com/photo-1521017432531-fbd92d768814?auto=format&fit=crop&w=900&q=80"
        default:
            urlString = "https://images.unsplash.com/photo-1521017432531-fbd92d768814?auto=format&fit=crop&w=900&q=80"
        }
        return URL(string: urlString)
    }

    private var bottomColor: Color {
        switch title {
        case "Aesthetic": return Color(hex: "FED7AA")
        case "Intimate": return Color(hex: "E9D5FF")
        case "Trendy", "Trending": return Color(hex: "A5F3FC")
        case "Authentic", "Local and authentic": return Color(hex: "E5E7EB")
        default: return Color(hex: "F1F5F9")
        }
    }

    private var bottomTextColor: Color { Color(hex: "0F172A") }

    var body: some View {
        SurveyOptionCard(
            title: title,
            desc: desc,
            systemImage: systemImage,
            imageURL: backgroundURL,
            bottomColor: bottomColor,
            bottomTextColor: bottomTextColor,
            isSelected: isSelected,
            action: action
        )
    }
}
