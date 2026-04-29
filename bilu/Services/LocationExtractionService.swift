//
//  LocationExtractionService.swift
//  bilu
//

import Foundation

struct LocationExtractionResult {
    let locations: [SearchLocation]
    let unresolvedVideoIds: [String]
}

enum LocationExtractionService {

    static func extractLocations(
        videos: [TikTokVideo],
        searchQuery: String,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) async -> LocationExtractionResult {
        guard !videos.isEmpty,
              let url = URL(string: "\(Config.apiBaseURL)/tiktok-locations") else {
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

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !Config.supabaseAnonKey.isEmpty {
            request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[LocationExtractionService] HTTP \(code): \(bodyText.prefix(400))")
                #endif
                return LocationExtractionResult(locations: [], unresolvedVideoIds: videos.map { $0.videoId })
            }

            struct Payload: Decodable {
                let locations: [SearchLocation]
                let unresolved: [String]
            }
            let decoded = try JSONDecoder().decode(Payload.self, from: data)
            #if DEBUG
            print("[LocationExtractionService] \(decoded.locations.count) locations, \(decoded.unresolved.count) unresolved")
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
