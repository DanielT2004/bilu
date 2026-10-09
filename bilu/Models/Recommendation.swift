//
//  Recommendation.swift
//  bilu
//

import Foundation

struct Recommendation: Codable, Identifiable {
    var id: String { name + dish }
    let name: String
    let dish: String
    let image: String?
    let explanation: String
    let mapsUrl: String
    let latitude: Double?
    let longitude: Double?
    let rating: Double?
    let reviewCount: Int?
    let isOpen: Bool?
    let photos: [String]?
    let address: String?
    let phone: String?
    let website: String?
    /// Concise parking guidance returned by the grounded recommendation service.
    /// Nil/blank means the source could not verify parking availability.
    let parking: String?
    let placeId: String?
    let photoRefs: [String]?
    /// Guest reviews from Google Places, when the backend resolved this place fresh
    /// (not on a places_cache hit — the cache doesn't store review text yet).
    let reviews: [PlaceReview]?
}

extension Recommendation {
    /// A feed card requires an explicit Places confirmation. Nil can represent
    /// a failed lookup and is therefore not treated as open.
    var isVerifiedOpen: Bool { isOpen == true }

    /// Never implies parking exists when the backend could not verify it.
    var parkingDisplayText: String {
        guard let parking,
              !parking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Parking not confirmed"
        }
        let value = parking.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["not confirmed", "unknown", "unverified"].contains(value.lowercased()) {
            return "Parking not confirmed"
        }
        return value
    }
}

extension Sequence where Element == Recommendation {
    var verifiedOpenRecommendations: [Recommendation] {
        filter(\.isVerifiedOpen)
    }
}

struct PlaceReview: Codable {
    let authorName: String
    let rating: Double?
    let relativeTime: String?
    let text: String
}

struct VibeResult: Codable {
    let recommendations: [Recommendation]
    let groundingPlaces: [GroundingPlace]?
    let relaxed: Bool?
}

struct GroundingPlace: Codable {
    let placeId: String
    let title: String
    let uri: String
}
