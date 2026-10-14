//
//  SavedVibesRowView.swift
//  bilu
//

import SwiftUI

/// Horizontal scroller of saved-vibe chips. Tapping a chip asks the Profile to
/// re-run that search (handled by the parent via onSelect).
struct SavedVibesRowView: View {
    let vibes: [SavedVibe]
    let onSelect: (SavedVibe) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(vibes) { vibe in
                    chip(vibe)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(_ vibe: SavedVibe) -> some View {
        Button {
            Haptics.medium()
            onSelect(vibe)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: AppTheme.Icon.vibe)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.terracotta)
                Text(vibe.summary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(1)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.sage)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppTheme.white)
            .clipShape(Capsule())
            .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(ScalePress())
    }
}
