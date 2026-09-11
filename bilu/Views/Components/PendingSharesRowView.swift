//
//  PendingSharesRowView.swift
//  bilu
//
//  TikTok links shared into bilu via the Share Extension that haven't been
//  opened or dismissed yet. Auto-resolving them into a saved restaurant isn't
//  built — tapping a card opens the link so the user can search it manually.
//

import SwiftUI

struct PendingSharesRowView: View {
    let shares: [PendingTikTokShare]
    let onOpen: (PendingTikTokShare) -> Void
    let onDismiss: (PendingTikTokShare) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(shares) { share in
                    card(share)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func card(_ share: PendingTikTokShare) -> some View {
        HStack(spacing: 10) {
            Button {
                Haptics.medium()
                onOpen(share)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.terracotta)
                    Text(share.urlString)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button {
                onDismiss(share)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppTheme.subtle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.white)
        .clipShape(Capsule())
        .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
    }
}
