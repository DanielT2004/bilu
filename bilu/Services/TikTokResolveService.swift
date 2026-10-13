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
    case resolved(video: ResolvedShareVideo, places: [SearchLocation])
    /// The video was read but no city is known; ask for one and retry.
    case needsCity(video: ResolvedShareVideo?)
    /// Not a TikTok link, or the video is private or deleted. Safe to dismiss.
    case unavailable
    /// Quota, auth, network or server trouble. Keep the share and retry later.
    case retryLater
}

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
        struct Payload: Decodable {
            let error: String?
            let video: ResolvedShareVideo?
            let places: [SearchLocation]?
        }
        let payload = try? JSONDecoder().decode(Payload.self, from: data)

        switch statusCode {
        case 200:
            guard let video = payload?.video else { return .retryLater }
            return .resolved(video: video, places: payload?.places ?? [])
        case 400 where payload?.error == "missing_city":
            return .needsCity(video: payload?.video)
        case 400, 422:
            return .unavailable
        default:
            return .retryLater
        }
    }
}
