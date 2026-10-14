//
//  VibeSelection.swift
//  bilu
//

import Foundation

/// A plain value model used by UI and persistence. Keep its Codable
/// conformance independent of the app target's default MainActor isolation so
/// SwiftData can encode and decode it from model accessors safely.
nonisolated struct VibeSelection: Codable {
    var occasion: String
    /// v3 "Key question" selection (single-select).
    var keyQuestionAnswer: String
    /// v3 "Key question" extra detail (only for some answers, e.g. Date Night).
    var keyQuestionTimeWindow: String?
    /// v3 "Key question" extra detail (only for some answers, e.g. Date Night planning ahead).
    /// Stored as YYYY-MM-DD.
    var keyQuestionDate: String?

    /// v3 "Food feeling" selection (multi-select categories).
    var foodFeelings: [String]
    /// Per-category sub-option selections (e.g. ["Handheld": ["Burger", "Taco"]]).
    /// Empty dict means no sub-options chosen in any category.
    var selectedSubOptions: [String: [String]]

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
    /// The pin always displays at mapCenter; lat/lng are only fed to the prompt
    /// when useRadiusSearch is true (user opted in via the map toggle).
    var radiusMiles: Double
    var latitude: Double?
    var longitude: Double?
    /// When false (default), search is city-wide — no coordinates or radius in the prompt.
    /// When true, lat/lng and radiusMiles are included.
    var useRadiusSearch: Bool

    /// Cuisine selection mode: "vibe" uses foodFeelings, "country" uses selectedCountry.
    var cuisineMode: String
    /// User-selected country cuisine (only used when cuisineMode == "country").
    var selectedCountry: String

    /// Vibe filter selected on the new food feeling step (e.g. "🔥 Trending", "⭐ Best rated").
    var selectedVibe: String

    /// Whether the user explicitly opened and applied fine-tune settings.
    /// When false, price/partySize/openNow are omitted from the prompt entirely.
    var fineTuneApplied: Bool

    /// Parking preferences — multi-select from "Street", "Valet", "Private Lot".
    var parking: [String]
    /// Extras — independent boolean filters.
    var outdoorSeating: Bool
    var petFriendly: Bool
    var wheelchairAccess: Bool

    /// Sit Down sub-occasion toggles. Mutually exclusive at the UI layer.
    var dateNight: Bool
    var specialOccasion: Bool

    init(
        occasion: String = "",
        keyQuestionAnswer: String = "",
        keyQuestionTimeWindow: String? = nil,
        keyQuestionDate: String? = nil,
        foodFeelings: [String] = [],
        selectedSubOptions: [String: [String]] = [:],
        vibe: [String] = [],
        hunger: [String] = [],
        location: String = "",
        googleSearch: Bool = false,
        thinkingLevel: String = "LOW",
        pricePoints: [String] = ["$$", "$$$"],
        partySize: Int = 2,
        openNow: Bool = false,
        radiusMiles: Double = 2.0,
        latitude: Double? = nil,
        longitude: Double? = nil,
        useRadiusSearch: Bool = false,
        cuisineMode: String = "vibe",
        selectedCountry: String = "",
        selectedVibe: String = "",
        fineTuneApplied: Bool = false,
        parking: [String] = [],
        outdoorSeating: Bool = false,
        petFriendly: Bool = false,
        wheelchairAccess: Bool = false,
        dateNight: Bool = false,
        specialOccasion: Bool = false
    ) {
        self.occasion = occasion
        self.keyQuestionAnswer = keyQuestionAnswer
        self.keyQuestionTimeWindow = keyQuestionTimeWindow
        self.keyQuestionDate = keyQuestionDate
        self.foodFeelings = foodFeelings
        self.selectedSubOptions = selectedSubOptions
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
        self.useRadiusSearch = useRadiusSearch
        self.cuisineMode = cuisineMode
        self.selectedCountry = selectedCountry
        self.selectedVibe = selectedVibe
        self.fineTuneApplied = fineTuneApplied
        self.parking = parking
        self.outdoorSeating = outdoorSeating
        self.petFriendly = petFriendly
        self.wheelchairAccess = wheelchairAccess
        self.dateNight = dateNight
        self.specialOccasion = specialOccasion
    }

    /// Returns true if this selection represents the same user-meaningful vibe as `other`.
    /// Compares the fields that drive a recommendation: occasion, key answer, cuisine, location.
    /// Multi-select fields (food feelings, sub-options) compare order-insensitively.
    /// Not all fields participate — fine-tune toggles like party size shouldn't make two
    /// otherwise-identical vibes look distinct.
    func matches(_ other: VibeSelection) -> Bool {
        occasion == other.occasion
            && keyQuestionAnswer == other.keyQuestionAnswer
            && foodFeelings.sorted() == other.foodFeelings.sorted()
            && normalizedSubOptions == other.normalizedSubOptions
            && selectedCountry == other.selectedCountry
            && selectedVibe == other.selectedVibe
            && location == other.location
            && dateNight == other.dateNight
            && specialOccasion == other.specialOccasion
    }

    // Custom decoder so older persisted JSON (without selectedSubOptions) still decodes cleanly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        occasion              = try c.decode(String.self, forKey: .occasion)
        keyQuestionAnswer     = try c.decode(String.self, forKey: .keyQuestionAnswer)
        keyQuestionTimeWindow = try? c.decode(String.self, forKey: .keyQuestionTimeWindow)
        keyQuestionDate       = try? c.decode(String.self, forKey: .keyQuestionDate)
        foodFeelings          = (try? c.decode([String].self, forKey: .foodFeelings)) ?? []
        selectedSubOptions    = (try? c.decode([String: [String]].self, forKey: .selectedSubOptions)) ?? [:]
        vibe                  = (try? c.decode([String].self, forKey: .vibe)) ?? []
        hunger                = (try? c.decode([String].self, forKey: .hunger)) ?? []
        location              = (try? c.decode(String.self, forKey: .location)) ?? ""
        googleSearch          = (try? c.decode(Bool.self, forKey: .googleSearch)) ?? false
        thinkingLevel         = (try? c.decode(String.self, forKey: .thinkingLevel)) ?? "LOW"
        pricePoints           = (try? c.decode([String].self, forKey: .pricePoints)) ?? ["$$", "$$$"]
        partySize             = (try? c.decode(Int.self, forKey: .partySize)) ?? 2
        openNow               = (try? c.decode(Bool.self, forKey: .openNow)) ?? false
        radiusMiles           = (try? c.decode(Double.self, forKey: .radiusMiles)) ?? 2.0
        latitude              = try? c.decode(Double.self, forKey: .latitude)
        longitude             = try? c.decode(Double.self, forKey: .longitude)
        useRadiusSearch       = (try? c.decode(Bool.self, forKey: .useRadiusSearch)) ?? false
        cuisineMode           = (try? c.decode(String.self, forKey: .cuisineMode)) ?? "vibe"
        selectedCountry       = (try? c.decode(String.self, forKey: .selectedCountry)) ?? ""
        selectedVibe          = (try? c.decode(String.self, forKey: .selectedVibe)) ?? ""
        fineTuneApplied       = (try? c.decode(Bool.self, forKey: .fineTuneApplied)) ?? false
        parking               = (try? c.decode([String].self, forKey: .parking)) ?? []
        outdoorSeating        = (try? c.decode(Bool.self, forKey: .outdoorSeating)) ?? false
        petFriendly           = (try? c.decode(Bool.self, forKey: .petFriendly)) ?? false
        wheelchairAccess      = (try? c.decode(Bool.self, forKey: .wheelchairAccess)) ?? false
        dateNight             = (try? c.decode(Bool.self, forKey: .dateNight)) ?? false
        specialOccasion       = (try? c.decode(Bool.self, forKey: .specialOccasion)) ?? false
    }
}

extension VibeSelection {
    /// Sub-options with each list sorted and empty lists dropped, so order and
    /// "category opened but nothing picked" don't make two vibes look different.
    nonisolated var normalizedSubOptions: [String: [String]] {
        selectedSubOptions.compactMapValues { $0.isEmpty ? nil : $0.sorted() }
    }

    /// Taste tags for a place saved from this survey's results: each food feeling
    /// followed by its picked sub-options, then any sub-options whose category
    /// isn't in `foodFeelings`. "Surprise me" says nothing about taste, so it's
    /// left out. `SavedPlace.normalizedTags` handles trimming and duplicates.
    nonisolated var tasteTags: [String] {
        var tags: [String] = []
        for feeling in foodFeelings where feeling != "Surprise me" {
            tags.append(feeling)
            tags.append(contentsOf: selectedSubOptions[feeling] ?? [])
        }
        for category in selectedSubOptions.keys.sorted() where !foodFeelings.contains(category) {
            tags.append(contentsOf: selectedSubOptions[category] ?? [])
        }
        return SavedPlace.normalizedTags(tags) ?? []
    }
}
