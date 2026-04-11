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
        var body: [String: Any] = [
            "occasion": selection.occasion,
            "vibe": selection.vibe,
            "hunger": selection.hunger,
            "location": selection.location,
            "googleSearch": selection.googleSearch,
            "thinkingLevel": selection.thinkingLevel,
            "prompt": prompt,
            "radiusMiles": selection.radiusMiles
        ]
        if let lat = selection.latitude  { body["latitude"]  = lat }
        if let lng = selection.longitude { body["longitude"] = lng }

        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("[GeminiService] Sending recommendation request")
        print("  lat:         \(selection.latitude.map { String($0) } ?? "nil")")
        print("  lng:         \(selection.longitude.map { String($0) } ?? "nil")")
        print("  radiusMiles: \(selection.radiusMiles)")
        print("  location:    \(selection.location.isEmpty ? "(empty)" : selection.location)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif

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
                let rawBody = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[GeminiService] recommendations HTTP \(code): \(rawBody)")
                #endif
                return fallbackResult
            }
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[GeminiService] RECOMMENDATIONS RAW (first 3000):\n\(raw.prefix(3000))")
            }
            #endif
            let result = try JSONDecoder().decode(VibeResult.self, from: data)
            #if DEBUG
            for rec in result.recommendations {
                print("[GeminiService] GEMINI REC \"\(rec.name)\": tips=\(rec.tips?.count ?? 0) [\(rec.tips?.joined(separator: " | ").prefix(80) ?? "none")]")
            }
            #endif
            return result
        } catch {
            #if DEBUG
            print("[GeminiService] recommendations DECODE ERROR: \(error)")
            #endif
            return fallbackResult
        }
    }

    // Phase 2 — background: Places enrichment (photos + coordinates)
    static func enrichRecommendations(
        _ recommendations: [Recommendation],
        groundingPlaces: [GroundingPlace],
        location: String
    ) async -> [Recommendation] {
        // Pass tips through so the backend can round-trip them in the response
        var body: [String: Any] = [
            "recommendations": recommendations.map { rec -> [String: Any] in
                var d: [String: Any] = [
                    "name": rec.name,
                    "dish": rec.dish,
                    "image": rec.image ?? "",
                    "explanation": rec.explanation,
                    "mapsUrl": rec.mapsUrl
                ]
                if let tips = rec.tips { d["tips"] = tips }
                return d
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
                let rawBody = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[GeminiService] enrich HTTP \(code): \(rawBody)")
                #endif
                return recommendations
            }

            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[GeminiService] ENRICH RAW (first 3000):\n\(raw.prefix(3000))")
            }
            #endif

            let decoded = try JSONDecoder().decode(VibeResult.self, from: data)

            #if DEBUG
            for rec in decoded.recommendations {
                print("""
                [GeminiService] ENRICHED "\(rec.name)":
                  photos=\(rec.photos?.count ?? 0)  rating=\(rec.rating.map(String.init) ?? "nil")  reviews=\(rec.reviews?.count ?? 0)
                  address=\(rec.address ?? "nil")
                  phone=\(rec.phone ?? "nil")  website=\(rec.website.map { String($0.prefix(50)) } ?? "nil")
                  isOpen=\(rec.isOpen.map(String.init) ?? "nil")  tips=\(rec.tips?.count ?? 0)
                """)
            }
            #endif

            return decoded.recommendations
        } catch {
            #if DEBUG
            print("[GeminiService] enrich DECODE ERROR: \(error)")
            #endif
            return recommendations
        }
    }
}
