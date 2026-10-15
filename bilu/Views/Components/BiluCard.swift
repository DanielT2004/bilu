//
//  BiluCard.swift
//  bilu
//
//  The one card style: cream (café brown in dark) on surface, 18 pt continuous
//  corners, ambient espresso-tinted shadow. No accent bars, ghost icons or borders.
//

import SwiftUI

struct BiluCard<Content: View>: View {
    var padding: CGFloat = 16
    var elevated: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: elevated ? AppTheme.shadowColor : .clear, radius: 16, x: 0, y: 6)
    }
}

#Preview {
    VStack(spacing: 16) {
        BiluCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tsujita LA").font(AppTheme.title).foregroundStyle(AppTheme.onSurface)
                Text("Tsukemen worth the line.").font(AppTheme.body).foregroundStyle(AppTheme.muted)
            }
        }
        BiluCard(elevated: false) {
            Text("Flat card").font(AppTheme.label).foregroundStyle(AppTheme.onSurface)
        }
    }
    .padding(20)
    .background(AppTheme.surface)
}
