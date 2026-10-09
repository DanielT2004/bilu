//
//  SavedPlace.swift
//  bilu
//

import Foundation
import SwiftData

/// Which collection a place lives in. The same physical place can move between
/// lists (Want to Go → Saved) by flipping this field, so both lists share one model.
enum SavedListType: String, Codable, CaseIterable {
    case saved
    case wantToGo
}

@Model
final class SavedPlace {
    /// Stable identity across sessions: placeId when present, else name+dish
    /// (mirrors `Recommendation.id`). Unique so re-saving updates rather than duplicates.
    @Attribute(.unique) var identityKey: String

    var name: String
    var dish: String
    var image: String?
    var explanation: String
    var mapsUrl: String
    var address: String?
    var phone: String?
    var website: String?
    var parking: String?
    var placeId: String?
    var latitude: Double?
    var longitude: Double?
    var rating: Double?
    var reviewCount: Int?
    var isOpen: Bool?
    var photos: [String]?
    var photoRefs: [String]?

    /// Stored as `SavedListType.rawValue`; SwiftData stores primitives most cleanly.
    var listTypeRaw: String
    var dateSaved: Date

    var listType: SavedListType {
        get { SavedListType(rawValue: listTypeRaw) ?? .saved }
        set { listTypeRaw = newValue.rawValue }
    }

    init(from rec: Recommendation, listType: SavedListType, dateSaved: Date = .now) {
        self.identityKey = rec.placeId ?? (rec.name + rec.dish)
        self.name = rec.name
        self.dish = rec.dish
        self.image = rec.image
        self.explanation = rec.explanation
        self.mapsUrl = rec.mapsUrl
        self.address = rec.address
        self.phone = rec.phone
        self.website = rec.website
        self.parking = rec.parking
        self.placeId = rec.placeId
        self.latitude = rec.latitude
        self.longitude = rec.longitude
        self.rating = rec.rating
        self.reviewCount = rec.reviewCount
        self.isOpen = rec.isOpen
        self.photos = rec.photos
        self.photoRefs = rec.photoRefs
        self.listTypeRaw = listType.rawValue
        self.dateSaved = dateSaved
    }
}

extension SavedPlace {
    /// Rebuilds a `Recommendation` so the Profile can drive the existing
    /// `RecommendationCard` and `RestaurantDetailView` with no new rendering code.
    var asRecommendation: Recommendation {
        Recommendation(
            name: name,
            dish: dish,
            image: image,
            explanation: explanation,
            mapsUrl: mapsUrl,
            latitude: latitude,
            longitude: longitude,
            rating: rating,
            reviewCount: reviewCount,
            isOpen: isOpen,
            photos: photos,
            address: address,
            phone: phone,
            website: website,
            parking: parking,
            placeId: placeId,
            photoRefs: photoRefs,
            reviews: nil
        )
    }
}

extension Recommendation {
    /// The same identity scheme `SavedPlace` uses — for membership checks.
    var identityKey: String { placeId ?? (name + dish) }
}
