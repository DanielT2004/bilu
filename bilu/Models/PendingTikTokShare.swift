//
//  PendingTikTokShare.swift
//  bilu
//

import Foundation

/// A TikTok link the user shared into bilu via the Share Extension. Queued in
/// the App Group container until the user dismisses it; on launch the app
/// resolves it to the place(s) the video is about (`PendingSharesModel`).
struct PendingTikTokShare: Identifiable, Equatable {
    let id: String
    let urlString: String
    let dateAdded: Date
    /// Where resolution stands. Persisted separately from the extension's queue
    /// so a resolved share is never resolved (or charged) twice.
    var resolution: PendingShareResolution = .pending
}

/// The stored result of resolving one shared TikTok.
enum PendingShareResolution: Codable, Equatable {
    /// Not tried yet, or the last try hit `.retryLater`. Resolved on next launch.
    case pending
    /// The video was read; `places` may be empty when it names no venue.
    case resolved(video: ResolvedShareVideo, places: [ResolvedSharePlace])
    /// The resolver needs a city; the user is asked for one.
    case needsCity
    /// Not a TikTok link, or private/deleted. The user can only dismiss it.
    case unavailable
}

/// A place a shared TikTok resolved to, kept on the share record.
struct ResolvedSharePlace: Codable, Equatable, Identifiable {
    let placeId: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let rating: Double?
    let neighborhood: String?
    /// Taste tags (cuisine, vibe) when the resolve response includes them.
    /// Stored here until `SavedPlace` gains a `tags` field (workstream F).
    let tags: [String]

    var id: String { placeId }

    init(
        placeId: String,
        name: String,
        address: String,
        latitude: Double,
        longitude: Double,
        rating: Double? = nil,
        neighborhood: String? = nil,
        tags: [String] = []
    ) {
        self.placeId = placeId
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.rating = rating
        self.neighborhood = neighborhood
        self.tags = tags
    }

    init(location: SearchLocation, tags: [String] = []) {
        self.init(
            placeId: location.placeId,
            name: location.placeName,
            address: location.address,
            latitude: location.lat,
            longitude: location.lng,
            rating: location.rating,
            neighborhood: location.neighborhood,
            tags: tags
        )
    }

    /// The `Recommendation` the saved-places store takes. Its identity is the
    /// Places id, so adding the same place twice is a no-op.
    func recommendation(caption: String?) -> Recommendation {
        var maps = URLComponents(string: "https://www.google.com/maps/search/")!
        maps.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "query_place_id", value: placeId)
        ]
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Recommendation(
            name: name,
            dish: "",
            image: nil,
            explanation: trimmedCaption.isEmpty ? "From a TikTok you shared." : trimmedCaption,
            mapsUrl: maps.url?.absoluteString ?? "",
            latitude: latitude,
            longitude: longitude,
            rating: rating,
            reviewCount: nil,
            isOpen: nil,
            photos: nil,
            address: address,
            phone: nil,
            website: nil,
            parking: nil,
            placeId: placeId,
            photoRefs: nil,
            reviews: nil
        )
    }
}
