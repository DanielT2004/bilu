//
//  SearchViewModel.swift
//  bilu
//

import Foundation
import Combine

enum SearchSort: Int, CaseIterable, Identifiable {
    case relevant  = 0
    case mostLiked = 1
    case mostRecent = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .relevant:   return "Relevant"
        case .mostLiked:  return "Most Liked"
        case .mostRecent: return "Most Recent"
        }
    }
}

enum ResultsViewMode: Int, CaseIterable, Identifiable {
    case videos, map
    var id: Int { rawValue }
    var label: String { self == .videos ? "Videos" : "Map" }
    var systemImage: String { self == .videos ? "square.grid.2x2" : "map" }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var videos: [TikTokVideo] = []
    @Published var isLoading = false
    @Published var hasSearched = false
    @Published var sort: SearchSort = .relevant

    // Phase 2: locations + map
    @Published var locations: [SearchLocation] = []
    @Published var isLoadingLocations = false
    @Published var unresolvedVideoIds: [String] = []
    @Published var viewMode: ResultsViewMode = .videos

    private var locationTask: Task<Void, Never>?

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        hasSearched = true
        locations = []
        unresolvedVideoIds = []
        locationTask?.cancel()

        videos = await TikTokService.fetchVideos(
            query: trimmed,
            maxResults: 10,
            sortType: sort.rawValue
        )
        isLoading = false

        // Kick off location extraction in the background — don't block the grid.
        if !videos.isEmpty {
            locationTask = Task { [trimmed] in
                await self.extractLocations(for: videos, searchQuery: trimmed)
            }
        }
    }

    func setSort(_ newSort: SearchSort) async {
        guard newSort != sort else { return }
        sort = newSort
        if hasSearched && !query.trimmingCharacters(in: .whitespaces).isEmpty {
            await search()
        }
    }

    func clear() {
        query = ""
        videos = []
        hasSearched = false
        locations = []
        unresolvedVideoIds = []
        locationTask?.cancel()
    }

    // MARK: - Phase 2: location extraction

    private func extractLocations(for videos: [TikTokVideo], searchQuery: String) async {
        isLoadingLocations = true
        defer { isLoadingLocations = false }

        let result = await LocationExtractionService.extractLocations(
            videos: videos,
            searchQuery: searchQuery
        )

        if Task.isCancelled { return }

        locations = result.locations
        unresolvedVideoIds = result.unresolvedVideoIds
    }

    // MARK: - Helpers for UI

    func videos(forLocation location: SearchLocation) -> [TikTokVideo] {
        let ids = Set(location.videoIds)
        return videos.filter { ids.contains($0.videoId) }
    }
}
