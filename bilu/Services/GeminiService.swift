//
//  GeminiService.swift
//  bilu

import Foundation

enum GeminiService {
    private static let fallbackResult = VibeResult(
        recommendations: [
            Recommendation(
                name: "The Local Spot",
                dish: "Signature Dish",
                image: nil,
                explanation: "Because the API is taking a coffee break, but this place is always a vibe.",
                mapsUrl: "https://www.google.com/maps/search/restaurants+near+me",
                latitude: nil,
                longitude: nil
            )
        ],
        groundingPlaces: []
    )

    // Phase 1 — fast: Gemini recommendations only (no Places enrichment)
    static func getVibeRecommendations(selection: VibeSelection) async -> VibeResult {
        let prompt = PromptBuilder.getPrompt(selection: selection)
        let body: [String: Any] = [
            "occasion": selection.occasion,
            "vibe": selection.vibe,
            "hunger": selection.hunger,
            "location": selection.location,
            "googleSearch": selection.googleSearch,
            "thinkingLevel": selection.thinkingLevel,
            "prompt": prompt
        ]

        do {
            guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
                return fallbackResult
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
                return fallbackResult
            }
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[GeminiService] RAW RESPONSE (first 2000 chars):\n\(raw.prefix(2000))")
            }
            #endif
            return try JSONDecoder().decode(VibeResult.self, from: data)
        } catch {
            return fallbackResult
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
}
