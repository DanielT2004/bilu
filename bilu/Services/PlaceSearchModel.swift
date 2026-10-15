//
//  PlaceSearchModel.swift
//  bilu
//
//  Type-ahead place search for the "Where to search" sheet. Uses Apple's
//  on-device MapKit completer (free, no paid API), so typing never spends a
//  discovery or a Places call.
//

import Combine
import Foundation
import MapKit

struct PlaceSuggestion: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
}

final class PlaceSearchModel: NSObject, ObservableObject {
    @Published var query = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                suggestions = []
                completions = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    @Published private(set) var isResolving = false
    @Published private(set) var errorMessage: String?

    private let completer = MKLocalSearchCompleter()
    private var completions: [MKLocalSearchCompletion] = []

    override init() {
        super.init()
        // Cities, neighborhoods and addresses — places you search *around*,
        // not individual businesses.
        completer.resultTypes = .address
        completer.delegate = self
    }

    /// Resolves a suggestion to a coordinate. Returns nil (and sets
    /// `errorMessage`) if MapKit can't place it.
    func resolve(_ suggestion: PlaceSuggestion) async -> CLLocationCoordinate2D? {
        guard completions.indices.contains(suggestion.id) else { return nil }
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: completions[suggestion.id])
        request.resultTypes = .address
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let coordinate = response.mapItems.first?.placemark.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else {
                errorMessage = "Couldn't find that place. Try another search."
                return nil
            }
            return coordinate
        } catch {
            errorMessage = "Couldn't find that place. Check your connection and try again."
            return nil
        }
    }

    func clear() {
        query = ""
        errorMessage = nil
    }

    fileprivate func apply(_ results: [MKLocalSearchCompletion]) {
        // Ignore late results for a query the user already cleared.
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        completions = Array(results.prefix(6))
        suggestions = completions.enumerated().map { index, completion in
            PlaceSuggestion(id: index, title: completion.title, subtitle: completion.subtitle)
        }
        errorMessage = nil
    }
}

extension PlaceSearchModel: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { apply(completer.results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            suggestions = []
            completions = []
        }
    }
}
