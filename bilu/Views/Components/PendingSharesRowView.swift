//
//  PendingSharesRowView.swift
//  bilu
//
//  TikTok links shared into bilu via the Share Extension. Each card shows where
//  resolution stands: finding the place, the place(s) with "Add to Want to Go",
//  a city prompt, or a dead link the user can dismiss.
//

import SwiftUI

struct PendingSharesRowView: View {
    let shares: [PendingTikTokShare]
    let resolving: Set<String>
    let isInWantToGo: (ResolvedSharePlace) -> Bool
    let onAddToWantToGo: (PendingTikTokShare, ResolvedSharePlace) -> Void
    let onChooseCity: (PendingTikTokShare) -> Void
    let onOpen: (PendingTikTokShare) -> Void
    let onDismiss: (PendingTikTokShare) -> Void

    private let cardWidth: CGFloat = 280

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(shares) { share in
                    card(share)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Card

    private func card(_ share: PendingTikTokShare) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: share))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppTheme.onSurface)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(for: share))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                dismissButton(share)
            }

            content(share)
        }
        .padding(16)
        .frame(width: cardWidth, alignment: .topLeading)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pending-share-\(share.id)")
    }

    @ViewBuilder
    private func content(_ share: PendingTikTokShare) -> some View {
        switch share.resolution {
        case .pending:
            if resolving.contains(share.id) {
                HStack(spacing: 8) {
                    ProgressView().tint(AppTheme.sage)
                    Text("Finding the place…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            } else {
                secondaryButton("Open in TikTok", systemImage: "arrow.up.right") { onOpen(share) }
            }

        case let .resolved(_, places):
            if places.isEmpty {
                secondaryButton("Open in TikTok", systemImage: "arrow.up.right") { onOpen(share) }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(places) { place in
                        placeRow(place, share: share)
                    }
                }
            }

        case .needsCity:
            primaryButton("Choose a city", systemImage: "mappin.and.ellipse") {
                onChooseCity(share)
            }
            .accessibilityHint("Pick the city this video is in to find the place.")

        case .unavailable:
            secondaryButton("Dismiss", systemImage: "xmark") { onDismiss(share) }
        }
    }

    private func placeRow(_ place: ResolvedSharePlace, share: PendingTikTokShare) -> some View {
        let added = isInWantToGo(place)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(2)
                Text(place.neighborhood ?? place.address)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            if added {
                Label("In Want to Go", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppTheme.sage)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(AppTheme.sageLt)
                    .clipShape(Capsule())
                    .accessibilityLabel("\(place.name) is in Want to Go")
            } else {
                primaryButton("Add to Want to Go", systemImage: "plus") {
                    onAddToWantToGo(share, place)
                }
                .accessibilityLabel("Add \(place.name) to Want to Go")
            }
        }
    }

    // MARK: - Copy

    private func title(for share: PendingTikTokShare) -> String {
        switch share.resolution {
        case .pending:
            return resolving.contains(share.id) ? "Shared TikTok" : "Waiting to match"
        case let .resolved(_, places):
            switch places.count {
            case 0: return "No place named"
            case 1: return "From your TikTok"
            default: return "\(places.count) places from your TikTok"
            }
        case .needsCity:
            return "Which city is this in?"
        case .unavailable:
            return "Video unavailable"
        }
    }

    private func subtitle(for share: PendingTikTokShare) -> String {
        switch share.resolution {
        case .pending:
            return resolving.contains(share.id)
                ? share.urlString
                : "We'll try again next time you open bilu."
        case let .resolved(video, places):
            if places.isEmpty { return "We couldn't find a restaurant in this video." }
            let caption = video.caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !caption.isEmpty { return caption }
            return video.authorName.map { "Shared from \($0)" } ?? share.urlString
        case .needsCity:
            return "Pick a city and we'll find the place."
        case .unavailable:
            return "It's private, deleted, or not a TikTok link."
        }
    }

    // MARK: - Buttons

    private func dismissButton(_ share: PendingTikTokShare) -> some View {
        Button {
            onDismiss(share)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.subtle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -12)
        .padding(.trailing, -12)
        .accessibilityLabel("Dismiss shared TikTok")
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppTheme.sage)
                .clipShape(Capsule())
        }
        .buttonStyle(ScalePress())
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.onSurface)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(AppTheme.neutralBg)
                .clipShape(Capsule())
        }
        .buttonStyle(ScalePress())
    }
}
