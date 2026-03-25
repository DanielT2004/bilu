//
//  VibeSelection.swift
//  bilu
//

import Foundation

struct VibeSelection: Codable {
    var occasion: String
    var vibe: [String]
    var hunger: [String]
    /// User-entered area (city, neighborhood, etc.). Empty → prompt uses a default.
    var location: String
    var googleSearch: Bool
    var thinkingLevel: String

    init(
        occasion: String = "",
        vibe: [String] = [],
        hunger: [String] = [],
        location: String = "",
        googleSearch: Bool = false,
        thinkingLevel: String = "LOW"
    ) {
        self.occasion = occasion
        self.vibe = vibe
        self.hunger = hunger
        self.location = location
        self.googleSearch = googleSearch
        self.thinkingLevel = thinkingLevel
    }
}
