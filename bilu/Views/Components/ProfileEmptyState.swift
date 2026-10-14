//
//  ProfileEmptyState.swift
//  bilu
//

import SwiftUI

/// Friendly empty state for an empty Saved / Want-to-Go segment or the vibes row.
struct ProfileEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.sageLt.opacity(0.5))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(AppTheme.sageMd)
            }

            Text(title)
                .font(AppTheme.headline)
                .italic()
                .foregroundStyle(AppTheme.onSurface)

            Text(message)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}
