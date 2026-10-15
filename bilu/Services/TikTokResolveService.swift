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
    /// Failed before anything was charged: no response (offline, host not
    /// found), a 429 rate limit, a 401, or a server error marked
    /// `charged: false`. Safe to retry automatically (the model caps it).
    case retryLater
    /// Failed in a way that may have spent the user's quota (a server error
    /// after the paid step, a timeout, a dropped connection). Never retried
    /// automatically; the share card offers "Try again".
    case failed
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

        // No session yet: nothing was sent, so nothing was charged.
        guard var request = try? await AuthenticatedAPIRequest.post(path: "tiktok-resolve", timeout: 30) else {
            return .retryLater
        }
        request.httpBody = httpBody
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            return decode(statusCode: code, data: data)
        } catch {
            return outcome(forTransportError: error)
        }
    }

    /// Only errors that mean the request never reached the server are safe to
    /// retry automatically. A timeout or dropped connection may have arrived
    /// after the server spent the quota unit.
    static func outcome(forTransportError error: Error) -> TikTokResolveOutcome {
        guard let urlError = error as? URLError else { return .failed }
        switch urlError.code {
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .dataNotAllowed, .callIsActive, .secureConnectionFailed,
             .appTransportSecurityRequiresSecureConnection:
            return .retryLater
        default:
            return .failed
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
            /// Set by the function on its own failures: whether the paid step ran.
            let charged: Bool?
        }
        let payload = try? JSONDecoder().decode(Payload.self, from: data)

        switch statusCode {
        case 200:
            // A 200 means the paid step ran; never auto-retry a garbled one.
            guard let video = payload?.video else { return .failed }
            let places = (payload?.places ?? []).map {
                ResolvedSharePlace(location: $0.location, tags: $0.tags)
            }
            return .resolved(video: video, places: places)
        case 400 where payload?.error == "missing_city":
            return .needsCity(video: payload?.video)
        case 400, 422:
            return .unavailable
        case 401, 429:
            // Auth and rate-limit refusals happen before the quota is spent.
            return .retryLater
        default:
            return payload?.charged == false ? .retryLater : .failed
        }
    }
}
