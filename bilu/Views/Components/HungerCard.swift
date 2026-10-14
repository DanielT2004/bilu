//
//  HungerCard.swift
//  bilu
//

import SwiftUI

struct HungerCard: View {
    let title: String
    let desc: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    private var backgroundURL: URL? {
        let urlString: String
        switch title {
        case "Warm & Slurpy":
            urlString = "https://images.unsplash.com/photo-1543349689-9a4d426bee8e?auto=format&fit=crop&w=900&q=80"
        case "Doughy & Loaded":
            urlString = "https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?auto=format&fit=crop&w=900&q=80"
        case "Fresh & Crisp":
            urlString = "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=900&q=80"
        case "Spicy & Bold":
            urlString = "https://images.unsplash.com/photo-1482049016688-2d3e1b311543?auto=format&fit=crop&w=900&q=80"
        case "The Shareable Feast":
            urlString = "https://images.unsplash.com/photo-1521017432531-fbd92d768814?auto=format&fit=crop&w=900&q=80"
        case "The Sip & Snack":
            urlString = "https://images.unsplash.com/photo-1485808191679-5f86510681a2?auto=format&fit=crop&w=900&q=80"
        case "The Half-Priced Hero":
            urlString = "https://images.unsplash.com/photo-1477764227684-8c4e5bca6f0d?auto=format&fit=crop&w=900&q=80"
        case "The Liquid Dinner":
            urlString = "https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=900&q=80"
        default:
            urlString = "https://images.unsplash.com/photo-1521017432531-fbd92d768814?auto=format&fit=crop&w=900&q=80"
        }
        return URL(string: urlString)
    }

    private var bottomColor: Color {
        switch title {
        case "Warm & Slurpy": return AppTheme.trayAmber
        case "Doughy & Loaded": return AppTheme.sageMd
        case "Fresh & Crisp": return AppTheme.trayMoss
        case "Spicy & Bold": return AppTheme.sageLt
        case "The Shareable Feast": return AppTheme.trayPeach
        case "The Sip & Snack": return AppTheme.traySlate
        case "The Half-Priced Hero": return AppTheme.trayAmber
        case "The Liquid Dinner": return AppTheme.traySlate
        default: return AppTheme.neutralBg
        }
    }

    private var bottomTextColor: Color { AppTheme.onSurface }

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
