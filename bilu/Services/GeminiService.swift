//
//  GeminiService.swift
//  bilu

import Foundation

enum SearchFailure: Equatable {
    case noMatches       // server returned an empty result
    case transportError  // network / HTTP / decode failure
}

struct VibeFetchOutcome {
    let result: VibeResult
    let failure: SearchFailure?
}

enum GeminiService {
    private static let emptyResult = VibeResult(recommendations: [], groundingPlaces: [], relaxed: nil)

    // Phase 1 — fast: Gemini recommendations only (no Places enrichment)
    static func getVibeRecommendations(selection: VibeSelection) async -> VibeFetchOutcome {
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
            var request = URLRequest(url: URL(string: "\(Config.apiBaseURL)/recommendations")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !Config.supabaseAnonKey.isEmpty {
                request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 45
            request.httpBody = httpBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[GeminiService] recommendations HTTP \(code): \(body)")
                #endif
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
            return VibeFetchOutcome(result: emptyResult, failure: .transportError)
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
                 "explanation": $0.explanation, "mapsUrl": $0.mapsUrl]
            },
            "groundingPlaces": groundingPlaces.map {
                ["placeId": $0.placeId, "title": $0.title, "uri": $0.uri]
            }
        ]
        if !location.isEmpty { body["location"] = location }

        do {
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                return recommendations
            }
            var request = URLRequest(url: URL(string: "\(Config.apiBaseURL)/enrich")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !Config.supabaseAnonKey.isEmpty {
                request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 30
            request.httpBody = httpBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[GeminiService] enrich HTTP \(code): \(body)")
                #endif
                return recommendations
            }
            let decoded = try JSONDecoder().decode(VibeResult.self, from: data)
            return decoded.recommendations
        } catch {
            return recommendations
        }
    }

    // Phase 3 — lazy: fetch gallery photos for a place on demand
    static func fetchGalleryPhotos(placeId: String) async -> [String] {
        guard let url = URL(string: "\(Config.apiBaseURL)/photos") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        guard let body = try? JSONSerialization.data(withJSONObject: ["placeId": placeId]) else { return [] }
        request.httpBody = body

        do {
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
}
