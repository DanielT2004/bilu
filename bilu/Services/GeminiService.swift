//
//  GeminiService.swift
//  bilu
//

import Foundation

enum GeminiService {
    private static let fallbackRec = Recommendation(
        name: "The Local Spot",
        dish: "Signature Dish",
        image: "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&q=80",
        explanation: "Because the API is taking a coffee break, but this place is always a vibe.",
        mapsUrl: "https://www.google.com/maps/search/restaurants+near+me"
    )

    static func getVibeRecommendations(selection: VibeSelection) async -> [Recommendation] {
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
                return [fallbackRec]
            }
            let url = URL(string: "\(Config.apiBaseURL)/recommendations")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !Config.supabaseAnonKey.isEmpty {
                request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 45
            request.httpBody = httpBody

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return [fallbackRec]
            }
            if !(200...299).contains(http.statusCode) {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[GeminiService] recommendations HTTP \(http.statusCode): \(body)")
                #endif
                return [fallbackRec]
            }
            #if DEBUG
            if let raw = String(data: data, encoding: .utf8) {
                print("[GeminiService] RAW RESPONSE (first 2000 chars):\n\(raw.prefix(2000))")
            }
            #endif
            let decoded = try JSONDecoder().decode(VibeResult.self, from: data)
            #if DEBUG
            for rec in decoded.recommendations {
                print("[GeminiService] REC | name=\(rec.name) | image=\(rec.image)")
            }
            #endif
            return decoded.recommendations
        } catch {
            return [fallbackRec]
        }
    }
}
