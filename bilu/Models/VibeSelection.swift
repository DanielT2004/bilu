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

    /// Map widget — search radius and center coordinates.
    /// Defaults to USC area; updated live as the user drags the radius ring.
    var radiusMiles: Double
    var latitude: Double?
    var longitude: Double?

    /// Cuisine selection mode: "vibe" uses foodFeelings, "country" uses selectedCountry.
    var cuisineMode: String
    /// User-selected country cuisine (only used when cuisineMode == "country").
    var selectedCountry: String

    /// Whether the user explicitly opened and applied fine-tune settings.
    /// When false, price/partySize/openNow are omitted from the prompt entirely.
    var fineTuneApplied: Bool

    /// Parking preferences — multi-select from "Street", "Valet", "Private Lot".
    var parking: [String]
    /// Extras — independent boolean filters.
    var outdoorSeating: Bool
    var petFriendly: Bool
    var wheelchairAccess: Bool

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
        openNow: Bool = false,
        radiusMiles: Double = 2.0,
        latitude: Double? = 34.0224,
        longitude: Double? = -118.2851,
        cuisineMode: String = "vibe",
        selectedCountry: String = "",
        fineTuneApplied: Bool = false,
        parking: [String] = [],
        outdoorSeating: Bool = false,
        petFriendly: Bool = false,
        wheelchairAccess: Bool = false
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
        self.radiusMiles = radiusMiles
        self.latitude = latitude
        self.longitude = longitude
        self.cuisineMode = cuisineMode
        self.selectedCountry = selectedCountry
        self.fineTuneApplied = fineTuneApplied
        self.parking = parking
        self.outdoorSeating = outdoorSeating
        self.petFriendly = petFriendly
        self.wheelchairAccess = wheelchairAccess
    }
}
