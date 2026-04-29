//
//  SearchView.swift
//  bilu
//

import SwiftUI

private let C = AppTheme.self

struct SearchView: View {
    let selectedTab: Tab
    let onSelectTab: (Tab) -> Void
    @StateObject private var viewModel = SearchViewModel()
    @State private var feedViewModel: VideoFeedViewModel? = nil
    @State private var selectedLocation: SearchLocation? = nil
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
                    findingLocationsPill
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
            } else {
                Spacer().frame(height: 4)
            }

            ZStack {
                if viewModel.isLoading {
                    loadingState
                } else if viewModel.hasSearched && viewModel.videos.isEmpty {
                    emptyResultsState
                } else if viewModel.videos.isEmpty {
                    emptyPromptState
                } else {
                    switch viewModel.viewMode {
                    case .videos:
                        resultsGrid
                            .transition(.opacity)
                    case .map:
                        SearchResultsMapView(
                            locations: viewModel.locations,
                            isLoading: viewModel.isLoadingLocations,
                            onSelect: { selectedLocation = $0 }
                        )
                        .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: viewModel.viewMode)

            TabBarView(selectedTab: selectedTab, onSelect: onSelectTab)
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
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.viewMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(mode.label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isActive ? .white : C.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isActive ? C.sage : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var findingLocationsPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(C.sage)
            Text("Finding locations…")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(C.sageLt.opacity(0.6))
        .clipShape(Capsule())
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

    // MARK: - Results grid

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                    VideoThumbnailCard(video: video)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.8)
                                .delay(Double(index) * 0.07),
                            value: viewModel.videos.count
                        )
                        .onTapGesture {
                            let snapshot = viewModel.videos
                            guard index >= 0, index < snapshot.count else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            feedViewModel = VideoFeedViewModel(videos: snapshot, startIndex: index)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Helpers

    private func triggerSearch() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        searchFocused = false
        Task { await viewModel.search() }
    }
}

// MARK: - VideoThumbnailCard

private struct VideoThumbnailCard: View {
    let video: TikTokVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure, .empty:
                    Rectangle()
                        .fill(C.sageLt)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(C.sage)
                                .font(.system(size: 24))
                        )
                @unknown default:
                    Rectangle().fill(C.sageLt)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(9/16, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                viewCountBadge
                    .padding(8)
            }

            // Metadata
            VStack(alignment: .leading, spacing: 3) {
                if !video.desc.isEmpty {
                    Text(video.desc)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(C.onSurface)
                        .lineLimit(2)
                }
                Text("@\(video.author.name)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(C.muted)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: C.shadowColor, radius: 12, x: 0, y: 4)
    }

    private var viewCountBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "play.fill")
                .font(.system(size: 8))
            Text(formatCount(video.viewCount))
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45))
        .clipShape(Capsule())
    }

    private func formatCount(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return "\(n / 1_000_000)M"
        case 1_000...:     return "\(n / 1_000)k"
        default:           return "\(n)"
        }
    }
}

#Preview {
    SearchView(selectedTab: .search, onSelectTab: { _ in })
}
