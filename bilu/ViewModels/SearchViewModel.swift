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
    case videos, list, map
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .videos: return "Videos"
        case .list:   return "List"
        case .map:    return "Map"
        }
    }
    var systemImage: String {
        switch self {
        case .videos: return "square.grid.2x2"
        case .list:   return "list.bullet"
        case .map:    return "map"
        }
    }
    /// Filled / heavier variant used when this mode is the active selection.
    var activeSystemImage: String {
        switch self {
        case .videos: return "square.grid.2x2.fill"
        case .list:   return "text.justify.left"
        case .map:    return "map.fill"
        }
    }
}

/// Popular cities offered as one-tap chips when a query lacks a city.
private let kSuggestedCities = ["Los Angeles", "New York", "San Francisco", "Chicago", "Brooklyn"]

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
    @Published var viewMode: ResultsViewMode = .list

    /// Set when a search was rejected for missing a city (client- or server-side).
    @Published var needsCity = false
    @Published var suggestedCities: [String] = kSuggestedCities

    // Filter state — applied client-side over the loaded locations.
    @Published var openNowOnly = false
    @Published var selectedNeighborhoods: Set<String> = []

    /// Locations after applying client-side filters (open now / neighborhoods).
    var filteredLocations: [SearchLocation] {
        locations.filter { loc in
            if openNowOnly && loc.isOpen != true { return false }
            if !selectedNeighborhoods.isEmpty {
                guard let n = loc.neighborhood, selectedNeighborhoods.contains(n) else { return false }
            }
            return true
        }
    }

    /// Distinct neighborhood names with at least one location, alphabetized. Empty if <2 distinct.
    var availableNeighborhoods: [String] {
        let set = Set(locations.compactMap { $0.neighborhood?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        guard set.count >= 2 else { return [] }
        return set.sorted()
    }

    private var locationTask: Task<Void, Never>?

    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Client-side fast path: if no city hint, prompt user without burning any backend calls.
        if !hasCityHint(in: trimmed) {
            needsCity = true
            suggestedCities = kSuggestedCities
            hasSearched = true
            videos = []
            locations = []
            unresolvedVideoIds = []
            return
        }

        needsCity = false
        isLoading = true
        hasSearched = true
        locations = []
        unresolvedVideoIds = []
        openNowOnly = false
        selectedNeighborhoods = []
        locationTask?.cancel()

        videos = await TikTokService.fetchVideos(
            query: trimmed,
            maxResults: 25,
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

    /// User picked a city chip — append it to the current query and re-run.
    func appendCityAndSearch(_ city: String) async {
        let base = query.trimmingCharacters(in: .whitespaces)
        // Avoid double-appending if user already added " in <city>" but it slipped past the regex.
        let needle = "in \(city)".lowercased()
        if !base.lowercased().contains(needle) {
            query = base.isEmpty ? "best food in \(city)" : "\(base) in \(city)"
        }
        await search()
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
        needsCity = false
        locations = []
        unresolvedVideoIds = []
        viewMode = .list
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

        // Server is authoritative — if it rejected for missing city, fall back to needsCity state.
        if result.missingCity {
            needsCity = true
            suggestedCities = result.suggestedCities ?? kSuggestedCities
            self.videos = []
            locations = []
            unresolvedVideoIds = []
            return
        }

        locations = result.locations
        unresolvedVideoIds = result.unresolvedVideoIds
    }

    // MARK: - Helpers for UI

    func videos(forLocation location: SearchLocation) -> [TikTokVideo] {
        let ids = Set(location.videoIds)
        return videos.filter { ids.contains($0.videoId) }
    }

    // MARK: - City-hint heuristic

    /// Cheap pre-flight check: does the query plausibly mention a city?
    /// The server is authoritative — this just avoids burning Apify+Gemini on obvious misses.
    private func hasCityHint(in query: String) -> Bool {
        let lower = query.lowercased()
        // Pattern 1: contains " in <something>"
        if lower.range(of: #"\sin\s\S"#, options: .regularExpression) != nil { return true }
        // Pattern 2: contains a known major US city/abbr
        let knownCities = [
            "la", "los angeles", "nyc", "ny", "new york", "sf", "san francisco",
            "chicago", "brooklyn", "queens", "manhattan", "boston", "miami",
            "seattle", "austin", "portland", "dc", "washington", "philly", "philadelphia",
            "houston", "dallas", "atlanta", "denver", "vegas", "las vegas",
            "san diego", "nashville", "k-town", "ktown", "koreatown", "weho",
            "santa monica", "venice", "pasadena", "long beach"
        ]
        for city in knownCities {
            // Word-boundary check so "lake" doesn't trip on "la"
            let pattern = #"(?:^|\s|,)"# + NSRegularExpression.escapedPattern(for: city) + #"(?:$|\s|,|\?|!|\.)"#
            if lower.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        return false
    }
}
