//
//  TikTokResolveService.swift
//  bilu
//
//  Resolves a TikTok link shared into bilu (via biluShare) to the place(s) the
//  video is about, through the /tiktok-resolve Edge Function. Service layer
//  only: the shared-row UI and "Add to Want to Go" call this.
//

import Foundation

struct ResolvedShareVideo: Codable, Equatable {
    let videoId: String
    let caption: String
    let canonicalUrl: String
    let authorName: String?
    let thumbnailUrl: String?
}

enum TikTokResolveOutcome: Equatable {
    case resolved(video: ResolvedShareVideo, places: [ResolvedSharePlace])
    /// The video was read but no city is known; ask for one and retry.
    case needsCity(video: ResolvedShareVideo?)
    /// Not a TikTok link, or the video is private or deleted. Safe to dismiss.
    case unavailable
    /// Quota, auth, network or server trouble. Keep the share and retry later.
    case retryLater
}

/// The resolve call, injectable so `PendingSharesModel` can be tested without
/// the network. Matches `TikTokResolveService.resolve`.
typealias TikTokShareResolver = (
    _ shareURL: String,
    _ city: String?,
    _ latitude: Double?,
    _ longitude: Double?
) async -> TikTokResolveOutcome

enum TikTokResolveService {

    static func resolve(
        shareURL: String,
        city: String?,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async -> TikTokResolveOutcome {
        var body: [String: Any] = ["shareUrl": shareURL]
        if let city, !city.isEmpty { body["city"] = city }
        if let latitude { body["latitude"] = latitude }
        if let longitude { body["longitude"] = longitude }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return .unavailable
        }

        do {
            var request = try await AuthenticatedAPIRequest.post(path: "tiktok-resolve", timeout: 30)
            request.httpBody = httpBody
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return decode(statusCode: code, data: data)
        } catch {
            #if DEBUG
            print("[TikTokResolveService] Error: \(error)")
            #endif
            return .retryLater
        }
    }

    /// Maps the function's status codes to outcomes. Kept separate so it can be
    /// unit tested without the network.
    static func decode(statusCode: Int, data: Data) -> TikTokResolveOutcome {
        /// A place plus any taste tags the function adds alongside the
        /// `SearchLocation` fields (`tags`, or a single `cuisine`).
        struct PlacePayload: Decodable {
            let location: SearchLocation
            let tags: [String]

            private enum CodingKeys: String, CodingKey { case tags, cuisine }

            init(from decoder: Decoder) throws {
                location = try SearchLocation(from: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                var tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
                if let cuisine = try? container.decodeIfPresent(String.self, forKey: .cuisine),
                   !cuisine.isEmpty, !tags.contains(cuisine) {
                    tags.insert(cuisine, at: 0)
                }
                self.tags = tags
            }
        }
        struct Payload: Decodable {
            let error: String?
            let video: ResolvedShareVideo?
            let places: [PlacePayload]?
        }
        let payload = try? JSONDecoder().decode(Payload.self, from: data)

        switch statusCode {
        case 200:
            guard let video = payload?.video else { return .retryLater }
            let places = (payload?.places ?? []).map {
                ResolvedSharePlace(location: $0.location, tags: $0.tags)
            }
            return .resolved(video: video, places: places)
        case 400 where payload?.error == "missing_city":
            return .needsCity(video: payload?.video)
        case 400, 422:
            return .unavailable
        default:
            return .retryLater
        }
    }
}
