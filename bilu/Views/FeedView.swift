//
//  FeedView.swift
//  bilu
//
//  Explore's entry. Everything here comes from the device: Want to Go places,
//  places resolved from shared TikToks, and saved vibes. Opening it never
//  spends a discovery or makes a paid call. Empty sections hide.
//

import SwiftUI
import SwiftData

struct FeedView: View {
    @ObservedObject var viewModel: HomeViewModel
    var onSelectPlace: (Recommendation, [String]?) -> Void
    var onRunVibe: (VibeSelection) -> Void

    @Query(sort: \SavedPlace.dateSaved, order: .reverse) private var savedPlaces: [SavedPlace]
    @Query(sort: \SavedVibe.dateSaved, order: .reverse) private var savedVibes: [SavedVibe]
    /// Observed so "1 free today" updates when a discovery or reward lands.
    @EnvironmentObject private var discoveryAllowance: DiscoveryAllowance
    /// The app root's shared-TikTok model; its resolved places feed the
    /// "From your TikToks" row as soon as they land, without opening Profile.
    @EnvironmentObject private var pendingShares: PendingSharesModel

    var body: some View {
        let origin = viewModel.feedOrigin
        let wantToGo = HomeViewModel.nearestWantToGo(savedPlaces, from: origin)
        let savedKeys = Set(savedPlaces.map(\.identityKey))
        let tikTok = viewModel.tikTokPlaces.filter { !savedKeys.contains($0.id) }
        let vibes = savedVibes.compactMap { vibe in vibe.selection.map { (vibe.id, vibe.summary, $0) } }

        VStack(alignment: .leading, spacing: 0) {
            Text("Find your next spot")
                .font(AppTheme.display)
                .foregroundStyle(AppTheme.onSurface)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("feed-title")
                .padding(.horizontal, 20)
                .padding(.top, 18)

            LocationChip(viewModel: viewModel)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            if !wantToGo.isEmpty {
                section(title: "Want to Go near you", systemImage: AppTheme.Icon.wantToGo) {
                    ForEach(wantToGo) { place in
                        placeCard(name: place.name,
                                  detail: place.address ?? place.dish,
                                  cuisine: CuisineLabel.infer(name: place.name, dish: place.dish,
                                                              explanation: place.explanation, tags: place.tags),
                                  photoURL: Self.storedPhotoURL(image: place.image, photos: place.photos),
                                  miles: HomeViewModel.milesLabel(from: origin, latitude: place.latitude,
                                                                  longitude: place.longitude),
                                  identifier: "feed-want-to-go-card") {
                            onSelectPlace(place.asRecommendation, place.tags)
                        }
                    }
                }
            }

            if !tikTok.isEmpty {
                section(title: "From your TikToks", systemImage: "play.rectangle") {
                    ForEach(tikTok) { item in
                        // Resolved shares carry no photo yet, so these stay text cards.
                        placeCard(name: item.place.name,
                                  detail: item.place.neighborhood ?? item.place.address,
                                  cuisine: CuisineLabel.infer(name: item.place.name, tags: item.place.tags),
                                  photoURL: nil,
                                  miles: HomeViewModel.milesLabel(from: origin, latitude: item.place.latitude,
                                                                  longitude: item.place.longitude),
                                  identifier: "feed-tiktok-card") {
                            onSelectPlace(item.recommendation, item.place.tags.isEmpty ? nil : item.place.tags)
                        }
                    }
                }
            }

            if !vibes.isEmpty {
                section(title: "Run it back", systemImage: AppTheme.Icon.vibe, iconColor: AppTheme.terracotta) {
                    ForEach(vibes, id: \.0) { _, summary, selection in
                        vibeCard(summary: summary) { onRunVibe(selection) }
                    }
                }
            }

            if wantToGo.isEmpty && tikTok.isEmpty && vibes.isEmpty {
                emptyState
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
            }
        }
        .onReceive(pendingShares.$shares) { viewModel.showSharedPlaces(from: $0) }
    }

    // MARK: - Sections

    /// Section icons are sienna; the saved-vibe sparkle is ochre (a special moment).
    private func section<Content: View>(title: String, systemImage: String,
                                        iconColor: Color = AppTheme.primaryInk,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(AppTheme.label)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(AppTheme.headline)
                    .foregroundStyle(AppTheme.onSurface)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) { content() }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
        }
        .padding(.top, 28)
    }

    /// A photo already stored on the saved place (a Places `photoUri` resolved
    /// when it was saved). Never triggers a Places call; nil keeps a text card.
    static func storedPhotoURL(image: String?, photos: [String]?) -> URL? {
        let candidate = [image].compactMap { $0 } + (photos ?? [])
        return candidate
            .lazy
            .compactMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .first { ["https", "http"].contains($0.scheme?.lowercased() ?? "") }
    }

    private func placeCard(name: String, detail: String, cuisine: String?, photoURL: URL?, miles: String?,
                           identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            BiluCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if let photoURL { FeedCardPhoto(url: photoURL) }
                    placeCardText(name: name, detail: detail, cuisine: cuisine, miles: miles)
                        .padding(14)
                }
            }
            .frame(width: 220)
        }
        .buttonStyle(ScalePress())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
        .accessibilityIdentifier(identifier)
    }

    private func placeCardText(name: String, detail: String, cuisine: String?, miles: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let cuisine {
                Text(cuisine)
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.primaryInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.sageLt)
                    .clipShape(Capsule())
                    .padding(.bottom, 2)
                    .accessibilityLabel("\(cuisine) cuisine")
            }
            Text(name)
                .font(AppTheme.headline)
                .foregroundStyle(AppTheme.onSurface)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !detail.isEmpty {
                Text(detail)
                    .font(AppTheme.body)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if let miles {
                Text(miles)
                    .font(AppTheme.caption)
                    .foregroundStyle(AppTheme.primaryInk)
                    .padding(.top, 2)
            }
        }
    }

    private func vibeCard(summary: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.medium()
            action()
        } label: {
            BiluCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .font(AppTheme.headline)
                        .foregroundStyle(AppTheme.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(AppTheme.caption)
                            .accessibilityHidden(true)
                        Text("Run it back")
                            .font(AppTheme.label)
                    }
                    .foregroundStyle(AppTheme.primaryInk)
                    if let status = viewModel.discoveryAllowanceStatus {
                        Text("Uses a discovery · \(status)")
                            .font(AppTheme.caption)
                            .foregroundStyle(AppTheme.accentInk)
                    }
                }
            }
            .frame(width: 220)
        }
        .buttonStyle(ScalePress())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed-run-it-back-card")
    }

    private var emptyState: some View {
        Button {
            Haptics.light()
            viewModel.isShowingIntentSheet = true
        } label: {
            BiluCard(padding: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tell us what you're after")
                        .font(AppTheme.title)
                        .foregroundStyle(AppTheme.onSurface)
                        .multilineTextAlignment(.leading)
                    Text("Coffee to lock in, a late bite, drinks with friends — pick a vibe and we'll find spots worth the trip.")
                        .font(AppTheme.body)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("Get started")
                            .font(AppTheme.label)
                        Image(systemName: "arrow.right")
                            .font(AppTheme.caption)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(AppTheme.primaryInk)
                    .padding(.top, 4)
                }
            }
        }
        .buttonStyle(ScalePress())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the intent sheet")
        .accessibilityIdentifier("feed-empty-state")
    }
}

/// A small, cropped photo across the top of a feed card. A tinted placeholder
/// holds the space while it loads; if the stored URL no longer loads, the
/// photo collapses and the card reads as a plain text card.
private struct FeedCardPhoto: View {
    let url: URL
    @State private var failed = false

    var body: some View {
        if !failed {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color.clear.onAppear { failed = true }
                default:
                    AppTheme.neutralBg
                }
            }
            .frame(width: 220, height: 112)
            .clipped()
            .accessibilityHidden(true)
        }
    }
}
