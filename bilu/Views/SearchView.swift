//
//  SearchView.swift
//  bilu
//

import SwiftUI

private let C = AppTheme.self

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedViewModel: VideoFeedViewModel? = nil
    @State private var selectedLocation: SearchLocation? = nil
    @State private var mapTabPulse = false
    /// Tracks the prior view mode so transitions can slide directionally
    /// (forward = right→left, backward = left→right). Initialized to .list
    /// to match SearchViewModel's default; updated on every viewMode change.
    @State private var prevModeRaw: Int = ResultsViewMode.list.rawValue
    @FocusState private var searchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)

            sortChips
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if !viewModel.videos.isEmpty {
                viewModeToggle
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                if viewModel.isLoadingLocations {
                    LoadingStatusTicker(videos: viewModel.videos)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
            } else {
                Spacer().frame(height: 4)
            }

            ZStack {
                if viewModel.isLoading {
                    loadingState
                } else if viewModel.needsCity {
                    needsCityState
                } else if viewModel.hasSearched && viewModel.videos.isEmpty {
                    emptyResultsState
                } else if viewModel.videos.isEmpty {
                    emptyPromptState
                } else {
                    Group {
                        switch viewModel.viewMode {
                        case .videos:
                            videosGrid
                        case .list:
                            resultsList
                        case .map:
                            SearchResultsMapView(
                                locations: viewModel.filteredLocations,
                                isLoading: viewModel.isLoadingLocations,
                                videos: viewModel.videos,
                                onSelect: { selectedLocation = $0 }
                            )
                        }
                    }
                    .id(viewModel.viewMode)
                    .transition(.asymmetric(
                        insertion: .move(edge: viewModel.viewMode.rawValue > prevModeRaw ? .trailing : .leading)
                                      .combined(with: .opacity),
                        removal:   .move(edge: viewModel.viewMode.rawValue > prevModeRaw ? .leading : .trailing)
                                      .combined(with: .opacity)
                    ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(AnimationProfile.selection.animation(reduceMotion: reduceMotion), value: viewModel.viewMode)
            .onChange(of: viewModel.viewMode) { newMode in
                prevModeRaw = newMode.rawValue
            }
        }
        .background(C.surface.ignoresSafeArea())
        .fullScreenCover(item: $feedViewModel) { vm in
            VideoFeedView(viewModel: vm)
        }
        .sheet(item: $selectedLocation) { location in
            let locationVideos = viewModel.videos(forLocation: location)
            LocationVideosSheet(
                location: location,
                videos: locationVideos,
                onSelectVideo: { index in
                    guard !locationVideos.isEmpty, index >= 0, index < locationVideos.count else { return }
                    let vm = VideoFeedViewModel(videos: locationVideos, startIndex: index)
                    selectedLocation = nil
                    // Slight delay lets the sheet dismiss animation complete before the cover animates in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        feedViewModel = vm
                    }
                }
            )
            .id(location.id)
        }
    }

    // MARK: - View mode toggle (Videos / Map)

    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(ResultsViewMode.allCases) { mode in
                modeTab(mode)
            }
        }
        .background(C.white)
        .clipShape(Capsule())
        .shadow(color: C.shadowColor, radius: 8, y: 2)
    }

    private func modeTab(_ mode: ResultsViewMode) -> some View {
        let isActive = viewModel.viewMode == mode
        let isLocationDependent = mode == .map || mode == .list
        let showLoadingDot = isLocationDependent && viewModel.isLoadingLocations && !isActive
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.viewMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isActive ? mode.activeSystemImage : mode.systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(mode.label)
                    .font(.system(size: 13, weight: .medium))
                if showLoadingDot {
                    Circle()
                        .fill(C.sage)
                        .frame(width: 6, height: 6)
                        .opacity(mapTabPulse ? 1.0 : 0.3)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                mapTabPulse = true
                            }
                        }
                }
            }
            .foregroundColor(isActive ? .white : C.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isActive ? C.sage : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search")
                .font(.custom("Georgia", size: 28))
                .foregroundColor(C.onSurface)
            Text("Find spots from TikTok")
                .font(.system(size: 12, weight: .medium))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(searchFocused ? C.sage : C.muted)

                ZStack(alignment: .leading) {
                    if viewModel.query.isEmpty {
                        Text("Try: matcha in San Diego")
                            .font(.system(size: 15))
                            .foregroundColor(C.muted)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $viewModel.query)
                        .font(.system(size: 15))
                        .foregroundColor(C.onSurface)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .onSubmit { triggerSearch() }
                }

                if !viewModel.query.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.clear()
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(C.subtle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(C.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(C.ghostBorder, lineWidth: 1)
            )

            Button {
                triggerSearch()
            } label: {
                Text("Search")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(C.sage)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sort chips

    private var sortChips: some View {
        HStack(spacing: 8) {
            ForEach(SearchSort.allCases) { option in
                sortChip(option)
            }
            Spacer(minLength: 0)
        }
    }

    private func sortChip(_ option: SearchSort) -> some View {
        let isActive = viewModel.sort == option
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await viewModel.setSort(option) }
        } label: {
            Text(option.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isActive ? .white : C.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isActive ? C.sage : C.white)
                .clipShape(Capsule())
                .shadow(color: C.shadowColor, radius: isActive ? 6 : 0, x: 0, y: 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isActive)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty prompt

    private var emptyPromptState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(C.sageLt)
                    .frame(width: 72, height: 72)
                Image(systemName: "fork.knife")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(C.sage)
            }
            Text("Search TikTok for\nany food vibe")
                .font(.custom("Georgia", size: 20))
                .multilineTextAlignment(.center)
                .foregroundColor(C.onSurface)
            Text("Try \"best ramen NYC\" or \"hidden coffee gems\"")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(C.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 20) {
            LoadingPulseView()
                .frame(width: 120, height: 120)
            Text("Searching TikTok…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(C.muted)
        }
    }

    // MARK: - Empty results

    private var emptyResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(C.subtle)
            Text("No videos found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(C.onSurface)
            Text("Try a different search term")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(C.muted)
        }
    }

    // MARK: - Needs city

    private var needsCityState: some View {
        VStack(spacing: 18) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(C.sage)

            Text("Add a city to search")
                .font(.custom("Georgia", size: 24))
                .foregroundColor(C.onSurface)

            Text("Try \u{201C}best brunch in LA\u{201D} or pick a city below")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(C.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.suggestedCities, id: \.self) { city in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Task { await viewModel.appendCityAndSearch(city) }
                        } label: {
                            Text(city)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(C.sage)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(C.sageLt)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Videos grid

    private var videosGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(viewModel.videos.enumerated()), id: \.element.videoId) { index, video in
                    VideoTile(video: video) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        feedViewModel = VideoFeedViewModel(videos: viewModel.videos, startIndex: index)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Results list (tiered)

    private var resultsList: some View {
        let filtered = viewModel.filteredLocations
        let top3   = Array(filtered.prefix(3))
        let mid    = Array(filtered.dropFirst(3).prefix(5))   // #4–8
        let tail   = Array(filtered.dropFirst(8).prefix(4))   // #9–12

        return ScrollView {
            VStack(spacing: 0) {
                // Filter chips always render when we have locations, even if the
                // current filter wipes everything — otherwise the user has no way
                // to undo the filter.
                if !viewModel.locations.isEmpty {
                    FilterChipsBar(
                        openNowOnly: $viewModel.openNowOnly,
                        selectedNeighborhoods: $viewModel.selectedNeighborhoods,
                        availableNeighborhoods: viewModel.availableNeighborhoods
                    )
                    .padding(.bottom, 14)
                }

                if viewModel.isLoadingLocations && filtered.isEmpty {
                    findingLocationsBlock
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if filtered.isEmpty {
                    if !viewModel.locations.isEmpty {
                        // Filter eliminated everything — chips stay visible above
                        // so the user can toggle the filter back off.
                        VStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(C.subtle)
                            Text("No matches with these filters")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(C.muted)
                        }
                        .padding(.top, 60)
                    } else {
                        // Locations actually empty
                        VStack(spacing: 8) {
                            Image(systemName: "mappin.slash")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(C.subtle)
                            Text("No venues found")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(C.muted)
                        }
                        .padding(.top, 60)
                    }
                } else {
                    // Tier 1 — heroes
                    VStack(spacing: 14) {
                        ForEach(top3) { loc in
                            Button {
                                Haptics.light()
                                selectedLocation = loc
                            } label: {
                                LocationHeroCard(
                                    location: loc,
                                    heroVideo: heroVideo(for: loc)
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal, 20)

                    // Tier 2 — 2-col medium grid
                    if !mid.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(mid) { loc in
                                Button {
                                    Haptics.light()
                                    selectedLocation = loc
                                } label: {
                                    LocationMediumCard(
                                        location: loc,
                                        heroVideo: heroVideo(for: loc)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    }

                    // Tier 3 — compact rows
                    if !tail.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(tail) { loc in
                                Button {
                                    Haptics.light()
                                    selectedLocation = loc
                                } label: {
                                    LocationRow(
                                        location: loc,
                                        heroVideo: heroVideo(for: loc)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.bottom, 100)
            .animation(AnimationProfile.fastFeedback.animation(reduceMotion: reduceMotion), value: viewModel.isLoadingLocations)
            .animation(AnimationProfile.fastFeedback.animation(reduceMotion: reduceMotion), value: filtered.isEmpty)
        }
        .scrollIndicators(.hidden)
    }

    private var findingLocationsBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Source TikToks")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.subtle)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(viewModel.videos.enumerated()), id: \.element.videoId) { index, video in
                        VideoStripItem(video: video) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            feedViewModel = VideoFeedViewModel(videos: viewModel.videos, startIndex: index)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Pick the highest-view-count TikTok for a venue — used as the card's hero thumbnail.
    private func heroVideo(for location: SearchLocation) -> TikTokVideo? {
        let candidates = viewModel.videos(forLocation: location)
        return candidates.max(by: { $0.viewCount < $1.viewCount })
    }

    // MARK: - Helpers

    private func triggerSearch() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        searchFocused = false
        Task { await viewModel.search() }
    }
}

// MARK: - VideoStripItem (Search > List loading state)

private struct VideoStripItem: View {
    let video: TikTokVideo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        AppTheme.sageLt
                    }
                }
                .frame(width: 86, height: 122)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 3) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 8, weight: .medium))
                    Text(formatCompactCount(video.viewCount))
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(6)
            }
            .frame(width: 86, height: 122)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - VideoTile (Search > Videos grid)

private struct VideoTile: View {
    let video: TikTokVideo
    let onTap: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        AppTheme.sageLt
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(9.0/16.0, contentMode: .fill)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 10, weight: .medium))
                    Text(formatCompactCount(video.viewCount))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 8, y: 3)
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

// MARK: - Number formatting

private func formatCompactCount(_ n: Int) -> String {
    if n >= 10_000_000 { return "\(n / 1_000_000)M" }
    if n >= 1_000_000  { return String(format: "%.1fM", Double(n) / 1_000_000.0) }
    if n >= 100_000    { return "\(n / 1_000)K" }
    if n >= 1_000      { return String(format: "%.1fK", Double(n) / 1_000.0) }
    return "\(n)"
}

// MARK: - "Why this place" pill

private struct WhyThisPlacePill: View {
    let videoCount: Int
    let totalViews: Int
    let rating: Double?

    var body: some View {
        HStack(spacing: 6) {
            if videoCount > 1 {
                Label("\(videoCount) videos", systemImage: "play.rectangle.fill")
                    .labelStyle(.titleOnly)
                Text("·").foregroundColor(C.subtle)
            }
            Text("\(formatCompactCount(totalViews)) views")
            if let r = rating {
                Text("·").foregroundColor(C.subtle)
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(C.terracotta)
                    Text(String(format: "%.1f", r))
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(C.muted)
    }
}

// MARK: - LocationHeroCard (top 3)

private struct LocationHeroCard: View {
    let location: SearchLocation
    let heroVideo: TikTokVideo?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero image — venue's top video thumbnail
            ZStack(alignment: .topLeading) {
                AsyncImage(url: URL(string: heroVideo?.thumbnailUrl ?? "")) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Rectangle().fill(C.sageLt)
                            .overlay(Image(systemName: "fork.knife").foregroundColor(C.sage).font(.system(size: 28)))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipped()

                // Rank badge
                Text("#\(location.rank + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(C.sage)
                    .clipShape(Capsule())
                    .padding(12)
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                Text(location.placeName)
                    .font(.custom("Georgia", size: 22))
                    .foregroundColor(C.onSurface)
                    .lineLimit(2)

                if let n = location.neighborhood {
                    Text(n.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.0)
                        .foregroundColor(C.subtle)
                }

                WhyThisPlacePill(
                    videoCount: location.videoCount,
                    totalViews: location.totalViews,
                    rating: location.rating
                )
                .padding(.top, 4)
            }
            .padding(14)
        }
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: C.shadowColor, radius: 16, x: 0, y: 6)
    }
}

// MARK: - LocationMediumCard (#4-8)

private struct LocationMediumCard: View {
    let location: SearchLocation
    let heroVideo: TikTokVideo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: URL(string: heroVideo?.thumbnailUrl ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(C.sageLt)
                        .overlay(Image(systemName: "fork.knife").foregroundColor(C.sage).font(.system(size: 20)))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(location.placeName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(C.onSurface)
                    .lineLimit(1)

                WhyThisPlacePill(
                    videoCount: location.videoCount,
                    totalViews: location.totalViews,
                    rating: location.rating
                )
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .padding(8)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: C.shadowColor, radius: 12, x: 0, y: 4)
    }
}

// MARK: - LocationRow (#9-12)

private struct LocationRow: View {
    let location: SearchLocation
    let heroVideo: TikTokVideo?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: heroVideo?.thumbnailUrl ?? "")) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(C.sageLt)
                        .overlay(Image(systemName: "fork.knife").foregroundColor(C.sage).font(.system(size: 16)))
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(location.placeName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(C.onSurface)
                    .lineLimit(1)

                WhyThisPlacePill(
                    videoCount: location.videoCount,
                    totalViews: location.totalViews,
                    rating: location.rating
                )
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(C.subtle)
        }
        .padding(10)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: C.shadowColor, radius: 8, x: 0, y: 2)
    }
}

// MARK: - FilterChipsBar

private struct FilterChipsBar: View {
    @Binding var openNowOnly: Bool
    @Binding var selectedNeighborhoods: Set<String>
    let availableNeighborhoods: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Open now toggle
                chipButton(
                    label: "Open now",
                    icon: "clock.fill",
                    isActive: openNowOnly
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    openNowOnly.toggle()
                }

                if !availableNeighborhoods.isEmpty {
                    Divider()
                        .frame(height: 18)
                        .padding(.horizontal, 4)

                    ForEach(availableNeighborhoods, id: \.self) { n in
                        let isActive = selectedNeighborhoods.contains(n)
                        chipButton(label: n, icon: nil, isActive: isActive) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if isActive { selectedNeighborhoods.remove(n) }
                            else        { selectedNeighborhoods.insert(n) }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func chipButton(label: String, icon: String?, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .medium))
                }
                Text(label).font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isActive ? .white : C.sage)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isActive ? C.sage : C.sageLt)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SearchView()
}
