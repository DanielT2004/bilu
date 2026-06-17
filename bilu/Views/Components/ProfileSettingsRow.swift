//
//  ProfileSettingsRow.swift
//  bilu
//

import SwiftUI

/// A tappable settings-style row (icon tray + title + trailing value + chevron).
/// Used for the Dietary Preferences entry. Borderless — a white card on surface.
struct ProfileSettingsRow: View {
    let icon: String
    let title: String
    let value: String
    let onTap: () -> Void

    var body: some View {
        Button(action: { Haptics.light(); onTap() }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(AppTheme.sageLt)
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.sage)
                }

                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)

                Spacer(minLength: 8)

                Text(value)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.subtle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AppTheme.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 12, x: 0, y: 4)
        }
        .buttonStyle(ScalePress())
    }
}
