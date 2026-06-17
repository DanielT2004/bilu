//
//  SavedVibe.swift
//  bilu
//

import Foundation
import SwiftData

/// A persisted search "vibe". `VibeSelection` is a Codable struct with a
/// migration-safe custom decoder, so it's stored as encoded Data rather than
/// flattened into columns — that preserves the decoder and keeps the schema lean.
@Model
final class SavedVibe {
    @Attribute(.unique) var id: UUID
    var encodedSelection: Data
    /// Denormalized label for the row (e.g. "Date Night · Italian") so list
    /// rows never decode JSON during scroll.
    var summary: String
    var dateSaved: Date

    var selection: VibeSelection? {
        try? JSONDecoder().decode(VibeSelection.self, from: encodedSelection)
    }

    init(selection: VibeSelection, summary: String, id: UUID = UUID(), dateSaved: Date = .now) {
        self.id = id
        self.encodedSelection = (try? JSONEncoder().encode(selection)) ?? Data()
        self.summary = summary
        self.dateSaved = dateSaved
    }
}

extension VibeSelection {
    /// Short human label built from the user-meaningful fields. Used as the
    /// denormalized `SavedVibe.summary`.
    var shortSummary: String {
        var parts: [String] = []
        if !occasion.isEmpty { parts.append(occasion) }
        if !selectedCountry.isEmpty {
            parts.append(selectedCountry)
        } else if let firstFeeling = foodFeelings.first {
            parts.append(firstFeeling)
        }
        if !location.isEmpty { parts.append(location) }
        return parts.isEmpty ? "Saved vibe" : parts.joined(separator: " · ")
    }
}
