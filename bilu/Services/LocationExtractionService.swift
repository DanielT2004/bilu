//
//  LocationExtractionService.swift
//  bilu
//

import Foundation

struct LocationExtractionResult {
    let locations: [SearchLocation]
    let unresolvedVideoIds: [String]
    /// Server returned 400 missing_city — the query had no recognizable city.
    let missingCity: Bool
    /// City suggestions returned by the server (only meaningful when missingCity == true).
    let suggestedCities: [String]?

    init(
        locations: [SearchLocation],
        unresolvedVideoIds: [String],
        missingCity: Bool = false,
        suggestedCities: [String]? = nil
    ) {
        self.locations = locations
        self.unresolvedVideoIds = unresolvedVideoIds
        self.missingCity = missingCity
        self.suggestedCities = suggestedCities
    }
}

enum LocationExtractionService {

    static func extractLocations(
        videos: [TikTokVideo],
        searchQuery: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async -> LocationExtractionResult {
        guard !videos.isEmpty else {
            return LocationExtractionResult(locations: [], unresolvedVideoIds: videos.map { $0.videoId })
        }

        #if DEBUG
        print("[LocationExtractionService] Sending \(videos.count) videos for query: \"\(searchQuery)\"")
        for (i, v) in videos.enumerated() {
            print("  [\(i)] id:\(v.videoId) desc:\"\(v.desc.prefix(120))\" views:\(v.viewCount)")
        }
        #endif

        var body: [String: Any] = [
            "videos": videos.map { v -> [String: Any] in
                var dict: [String: Any] = [
                    "videoId": v.videoId,
                    "desc": v.desc,
                    "viewCount": v.viewCount,
                    "shareUrl": v.shareUrl
                ]
                if let url = v.transcriptUrl { dict["transcriptUrl"] = url }
                if let d = v.debug, !d.anchors.isEmpty {
                    dict["anchors"] = d.anchors.map { a -> [String: Any] in
                        var out: [String: Any] = ["keyword": a.keyword]
                        if let c = a.categoryName { out["categoryName"] = c }
                        if let p = a.poiClassName { out["poiClassName"] = p }
                        if let lat = a.lat { out["lat"] = lat }
                        if let lng = a.lng { out["lng"] = lng }
                        return out
                    }
                }
                return dict
            },
            "searchQuery": searchQuery
        ]
        if let lat = latitude  { body["latitude"]  = lat }
        if let lng = longitude { body["longitude"] = lng }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return LocationExtractionResult(locations: [], unresolvedVideoIds: videos.map { $0.videoId })
        }

        do {
            var request = try await AuthenticatedAPIRequest.post(path: "tiktok-locations", timeout: 30)
            request.httpBody = httpBody
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1

            // Server signals "missing city" via HTTP 400 + { error: "missing_city", suggestedCities: [...] }
            if code == 400 {
                struct MissingCityPayload: Decodable {
                    let error: String?
                    let message: String?
                    let suggestedCities: [String]?
                }
                if let payload = try? JSONDecoder().decode(MissingCityPayload.self, from: data),
                   payload.error == "missing_city" {
                    #if DEBUG
                    print("[LocationExtractionService] Server rejected: missing_city")
                    #endif
                    return LocationExtractionResult(
                        locations: [],
                        unresolvedVideoIds: videos.map { $0.videoId },
                        missingCity: true,
                        suggestedCities: payload.suggestedCities
                    )
                }
            }

            guard (200...299).contains(code) else {
                #if DEBUG
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                print("[LocationExtractionService] HTTP \(code): \(bodyText.prefix(400))")
                #endif
                return LocationExtractionResult(locations: [], unresolvedVideoIds: videos.map { $0.videoId })
            }

            struct Payload: Decodable {
                let locations: [SearchLocation]
                let unresolved: [String]
                let queryCity: String?
            }
            let decoded = try JSONDecoder().decode(Payload.self, from: data)
            #if DEBUG
            print("[LocationExtractionService] \(decoded.locations.count) locations, \(decoded.unresolved.count) unresolved, queryCity=\(decoded.queryCity ?? "nil")")
            #endif
            return LocationExtractionResult(
                locations: decoded.locations,
                unresolvedVideoIds: decoded.unresolved
            )
        } catch {
            #if DEBUG
            print("[LocationExtractionService] Error: \(error)")
            #endif
            return LocationExtractionResult(locations: [], unresolvedVideoIds: videos.map { $0.videoId })
        }
    }
}
