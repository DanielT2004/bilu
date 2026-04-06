//
//  PromptBuilder.swift
//  bilu
//

import Foundation

enum PromptBuilder {
    static func effectiveLocation(for selection: VibeSelection) -> String {
        let t = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Los Angeles, CA" : t
    }

    static func getPrompt(selection: VibeSelection) -> String {
        let locationLine = Self.effectiveLocation(for: selection)
        let discoveryRules = PromptConstants.getApplicableDiscoveryRules(selection: selection)
        let discoverySection: String
        if discoveryRules.isEmpty {
            discoverySection = ""
        } else {
            discoverySection = "Discovery Logic:\n" + discoveryRules.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\n\n"
        }

        let priceSection = selection.pricePoints.isEmpty ? "" :
            "- Price range: \(selection.pricePoints.sorted().joined(separator: ", "))\n"

        let partySizeSection = selection.partySize > 1 ?
            "- Party size: \(selection.partySize) people\n" : ""

        let openNowSection = selection.openNow ?
            "- Must be open right now\n" : ""

        let fineTuneSection = priceSection + partySizeSection + openNowSection

        return """
         DIRECTIVE: You are the 'VibeCheck Architect.' Your goal is to find high-flavor, high-soul, and culturally relevant dining near the user's area: \(locationLine).


        USER CONTEXT:
        - Occasion: \(selection.occasion)
        - Key question answer: \(selection.keyQuestionAnswer)\(selection.keyQuestionTimeWindow.map { " (\($0))" } ?? "")\(selection.keyQuestionDate.map { " (\($0))" } ?? "")
        - Food feeling: \(selection.foodFeeling)
        - Location: \(locationLine)
        \(fineTuneSection.isEmpty ? "" : fineTuneSection)

        \(discoverySection)REJECTION CRITERIA (CRITICAL):
        - STERNLY EXCLUDE: McDonald's, Shake Shack, Burger King, Chipotle, Subway, or any global fast-food franchise.
        - REJECT: Any location that is currently "Closed" or "Closing in <30 mins."\(selection.openNow ? "\n        - REJECT: Any spot that is not currently open." : "")
        - REJECT: "Happy Hour" suggestions if the current time is outside the venue's verified HH window.

        RECOGNITION CRITERIA:
        - PRIORITIZE: 4.0+ star places with substantial reviews.

        TASK:
        1. DISCOVER: Provide 5 elite recommendations. For 'image', use a real restaurant/food image URL when found via search; otherwise use: https://source.unsplash.com/featured/?food,[DishName] (no fabricated URLs).
        2. EXPLAIN: In 'explanation', mention the current vibe and why it fits the specific "Hunger Path" (e.g., the 'handheld weight' or the 'broth depth').

        Return as JSON: { "recommendations": [{ "name": "", "dish": "", "image": "", "explanation": "", "mapsUrl": "" }] }
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
