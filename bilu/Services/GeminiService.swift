//
//  GeminiService.swift
//  bilu

import Foundation

enum SearchFailure: Equatable {
    case noMatches       // server returned an empty result
    case rewardRequired  // server has no free or verified rewarded access left
    case capacityUnavailable // upstream quota/spending cap is exhausted
    case usageLimitExceeded // per-user or global paid API budget is exhausted
    case timedOut        // the search exceeded the user-facing latency budget
    case transportError  // network / HTTP / decode failure
}

struct VibeFetchOutcome {
    let result: VibeResult
    let failure: SearchFailure?
}

enum GeminiService {
    private static let emptyResult = VibeResult(recommendations: [], groundingPlaces: [], relaxed: nil)
    private static let recommendationTimeout: TimeInterval = 15
    private static let enrichmentTimeout: TimeInterval = 8

    // Phase 1 — fast: Gemini recommendations only (no Places enrichment)
    static func getVibeRecommendations(
        selection: VibeSelection,
        rewardedAccessToken: String? = nil
    ) async -> VibeFetchOutcome {
        let prompt = PromptBuilder.getPrompt(selection: selection)
        var body: [String: Any] = [
            "occasion": selection.occasion,
            "vibe": selection.vibe,
            "hunger": selection.hunger,
            "location": selection.location,
            "googleSearch": selection.googleSearch,
            "thinkingLevel": selection.thinkingLevel,
            "prompt": prompt
        ]
        if selection.useRadiusSearch {
            body["radiusMiles"] = selection.radiusMiles
            if let lat = selection.latitude  { body["latitude"]  = lat }
            if let lng = selection.longitude { body["longitude"] = lng }
        }

        do {
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                return VibeFetchOutcome(result: emptyResult, failure: .transportError)
            }
            var request = try await AuthenticatedAPIRequest.post(
                path: "recommendations",
                timeout: recommendationTimeout
            )
            if let rewardedAccessToken {
                request.setValue(rewardedAccessToken, forHTTPHeaderField: "X-Rewarded-Access-Token")
            }
            request.httpBody = httpBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[GeminiService] recommendations HTTP \(code): \(body)")
                #endif
                struct ErrorResponse: Decodable { let code: String? }
                let errorCode = try? JSONDecoder().decode(ErrorResponse.self, from: data).code
                if (response as? HTTPURLResponse)?.statusCode == 503 && errorCode == "UPSTREAM_CAPACITY" {
                    return VibeFetchOutcome(result: emptyResult, failure: .capacityUnavailable)
                }
                if (response as? HTTPURLResponse)?.statusCode == 402 && errorCode == "REWARDED_AD_REQUIRED" {
                    return VibeFetchOutcome(result: emptyResult, failure: .rewardRequired)
                }
                if (response as? HTTPURLResponse)?.statusCode == 429 && errorCode == "USAGE_LIMIT_EXCEEDED" {
                    return VibeFetchOutcome(result: emptyResult, failure: .usageLimitExceeded)
                }
                if (response as? HTTPURLResponse)?.statusCode == 429 && errorCode == "GLOBAL_BUDGET_EXCEEDED" {
                    return VibeFetchOutcome(result: emptyResult, failure: .capacityUnavailable)
                }
                if (response as? HTTPURLResponse)?.statusCode == 504 && errorCode == "UPSTREAM_TIMEOUT" {
                    return VibeFetchOutcome(result: emptyResult, failure: .timedOut)
                }
                return VibeFetchOutcome(result: emptyResult, failure: .transportError)
            }
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[GeminiService] RAW RESPONSE (first 2000 chars):\n\(raw.prefix(2000))")
            }
            #endif
            let decoded = try JSONDecoder().decode(VibeResult.self, from: data)
            let failure: SearchFailure? = decoded.recommendations.isEmpty ? .noMatches : nil
            return VibeFetchOutcome(result: decoded, failure: failure)
        } catch {
            let failure: SearchFailure = isTimeout(error) ? .timedOut : .transportError
            return VibeFetchOutcome(result: emptyResult, failure: failure)
        }
    }

    // Phase 2 — background: Places enrichment (photos + coordinates)
    static func enrichRecommendations(
        _ recommendations: [Recommendation],
        groundingPlaces: [GroundingPlace],
        location: String
    ) async -> [Recommendation] {
        var body: [String: Any] = [
            "recommendations": recommendations.map {
                ["name": $0.name, "dish": $0.dish, "image": $0.image ?? "",
                 "explanation": $0.explanation, "mapsUrl": $0.mapsUrl,
                 "parking": $0.parking ?? "Not confirmed"]
            },
            "groundingPlaces": groundingPlaces.map {
                ["placeId": $0.placeId, "title": $0.title, "uri": $0.uri]
            }
        ]
        if !location.isEmpty { body["location"] = location }

        do {
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                return []
            }
            var request = try await AuthenticatedAPIRequest.post(
                path: "enrich",
                timeout: enrichmentTimeout
            )
            request.httpBody = httpBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[GeminiService] enrich HTTP \(code): \(body)")
                #endif
                return []
            }
            let decoded = try JSONDecoder().decode(VibeResult.self, from: data)
            // Defense in depth: the backend filters too, but the app never
            // publishes a restaurant without an explicit open confirmation.
            return decoded.recommendations.verifiedOpenRecommendations
        } catch {
            return []
        }
    }

    // Phase 3 — lazy: fetch gallery photos for a place on demand
    static func fetchGalleryPhotos(placeId: String) async -> [String] {
        guard let body = try? JSONSerialization.data(withJSONObject: ["placeId": placeId]) else { return [] }

        do {
            var request = try await AuthenticatedAPIRequest.post(path: "photos", timeout: 20)
            request.httpBody = body
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return []
            }
            struct PhotosResponse: Decodable { let photos: [String] }
            let decoded = try JSONDecoder().decode(PhotosResponse.self, from: data)
            return decoded.photos
        } catch {
            return []
        }
    }

    private static func isTimeout(_ error: Error) -> Bool {
        let urlError = error as? URLError
        return urlError?.code == .timedOut
            || (error as NSError).code == NSURLErrorTimedOut
    }
}
