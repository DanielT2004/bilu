//
//  VibeSelection.swift
//  bilu
//

import Foundation

struct VibeSelection: Codable {
    var occasion: String
    /// v3 "Key question" selection (single-select).
    var keyQuestionAnswer: String
    /// v3 "Key question" extra detail (only for some answers, e.g. Date Night).
    var keyQuestionTimeWindow: String?
    /// v3 "Key question" extra detail (only for some answers, e.g. Date Night planning ahead).
    /// Stored as YYYY-MM-DD.
    var keyQuestionDate: String?

    /// v3 "Food feeling" selection (multi-select).
    var foodFeelings: [String]

    /// Legacy fields (kept for backend compatibility).
    var vibe: [String]
    var hunger: [String]
    /// User-entered area (city, neighborhood, etc.). Empty → prompt uses a default.
    var location: String
    var googleSearch: Bool
    var thinkingLevel: String

    /// Fine-tune fields (price tiers, party size, open-now toggle).
    var pricePoints: [String]
    var partySize: Int
    var openNow: Bool

    init(
        occasion: String = "",
        keyQuestionAnswer: String = "",
        keyQuestionTimeWindow: String? = nil,
        keyQuestionDate: String? = nil,
        foodFeelings: [String] = [],
        vibe: [String] = [],
        hunger: [String] = [],
        location: String = "",
        googleSearch: Bool = false,
        thinkingLevel: String = "LOW",
        pricePoints: [String] = ["$$", "$$$"],
        partySize: Int = 2,
        openNow: Bool = false
    ) {
        self.occasion = occasion
        self.keyQuestionAnswer = keyQuestionAnswer
        self.keyQuestionTimeWindow = keyQuestionTimeWindow
        self.keyQuestionDate = keyQuestionDate
        self.foodFeelings = foodFeelings
        self.vibe = vibe
        self.hunger = hunger
        self.location = location
        self.googleSearch = googleSearch
        self.thinkingLevel = thinkingLevel
        self.pricePoints = pricePoints
        self.partySize = partySize
        self.openNow = openNow
    }
}
