//
//  SavesNotKeptBanner.swift
//  bilu
//
//  Shown when the saved-places store couldn't open and saves only last for this
//  session (`PersistenceStatus.temporary`). Calm, informational copy: earlier
//  saves aren't lost, new ones won't survive closing the app, and what to try.
//

import SwiftUI

struct SavesNotKeptBanner: View {
    enum Style { case full, compact }

    let reason: PersistenceFailureReason
    var style: Style = .full
    /// Compact only: this place is saved right now, so say it's for this session.
    var hasTemporarySave = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: style == .full ? 17 : 15, weight: .semibold))
                .foregroundStyle(AppTheme.terracotta)
                .frame(width: style == .full ? 40 : 34, height: style == .full ? 40 : 34)
                .background(AppTheme.trayAmber)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: style == .full ? 15 : 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                Text(message)
                    .font(.system(size: style == .full ? 13 : 12))
                    .foregroundStyle(AppTheme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(style == .full ? 16 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Full: the standard card on the cream page. Compact sits inside the white
        // detail sheet, so it steps down a tonal tier instead of adding a shadow.
        .background(style == .full ? AppTheme.white : AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: style == .full ? AppTheme.shadowColor : .clear, radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(message)")
        .accessibilityIdentifier("saves-not-kept-banner")
    }

    private var title: String {
        switch style {
        case .full: return "Saves won't be kept right now"
        case .compact:
            return hasTemporarySave ? "Saved for now, not kept after you close Bilu" : "Saves last only until you close Bilu"
        }
    }

    private var message: String {
        switch (style, reason) {
        case (.full, .lowStorage):
            return "Your iPhone is almost out of storage, so Bilu couldn't open your saved places. They aren't lost. Anything you save now lasts only until you close the app. Free up some space, then restart Bilu."
        case (.full, .unavailable):
            return "Bilu couldn't open your saved places. They aren't lost. Anything you save now lasts only until you close the app. Try restarting Bilu."
        case (.compact, .lowStorage):
            return "To keep a place, free up some storage, restart Bilu, then save it again."
        case (.compact, .unavailable):
            return "To keep a place, restart Bilu, then save it again."
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        SavesNotKeptBanner(reason: .unavailable)
        SavesNotKeptBanner(reason: .lowStorage)
        SavesNotKeptBanner(reason: .unavailable, style: .compact)
        SavesNotKeptBanner(reason: .lowStorage, style: .compact, hasTemporarySave: true)
    }
    .padding(20)
    .background(AppTheme.surface)
}
