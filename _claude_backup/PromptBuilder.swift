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

        let qualityChainSection: String
        if selection.keyQuestionAnswer == "Best quality nearby" || selection.keyQuestionAnswer == "Something new & trendy" {
            qualityChainSection = "\n        - REJECT: Corporate fast-casual or nationally franchised chains that expanded via investor or franchise rollout (e.g. Dave's Hot Chicken, Raising Cane's). These belong on 'fastest near me' — not 'best quality' or 'new & trendy' paths.\n        - ALLOW even if multi-location: Small chef-driven groups (2–8 locations) that grew organically from a cult local original and are independently owned with editorial recognition (e.g. Gjusta, Jon & Vinny's). Multiple locations do NOT disqualify a place if it is founder-led, press-recognized, and earned its expansion from a genuine local following."
        } else {
            qualityChainSection = ""
        }

        let coordLine: String = {
            if let lat = selection.latitude, let lng = selection.longitude {
                return " (\(String(format: "%.4f", lat))° N, \(String(format: "%.4f", abs(lng)))° W)"
            }
            return ""
        }()
        let radiusLine = "- Search radius: \(String(format: "%.1f", selection.radiusMiles)) miles from this location\n"

        return """
         DIRECTIVE: You are the 'VibeCheck Architect.' Your goal is to find high-flavor, high-soul, and culturally relevant dining near the user's area: \(locationLine)\(coordLine).


        USER CONTEXT:
        - Occasion: \(selection.occasion)
        - Key question answer: \(selection.keyQuestionAnswer)\(selection.keyQuestionTimeWindow.map { " (\($0))" } ?? "")\(selection.keyQuestionDate.map { " (\($0))" } ?? "")
        - Food feeling: \(selection.foodFeelings.joined(separator: " + "))
        - Location: \(locationLine)\(coordLine)
        \(radiusLine)\(fineTuneSection.isEmpty ? "" : fineTuneSection)

        \(discoverySection)REJECTION CRITERIA (CRITICAL):
        - STERNLY EXCLUDE: McDonald's, Shake Shack, Burger King, Chipotle, Subway, or any global fast-food franchise.
        - REJECT: Any location that is currently "Closed" or "Closing in <30 mins."\(selection.openNow ? "\n        - REJECT: Any spot that is not currently open." : "")
        - REJECT: "Happy Hour" suggestions if the current time is outside the venue's verified HH window.\(qualityChainSection)

        RECOGNITION CRITERIA:
        - PRIORITIZE: Independent or small-local-group spots with 2,000+ Google reviews. A one-location spot with 4,000 reviews is a cult institution — weight this heavily over any chain.
        - PRIORITIZE: Places with editorial coverage (Eater, LA Times, Infatuation, Beli, Michelin Bib Gourmand, James Beard nominations).
        - DEPRIORITIZE: Corporate or nationally franchised chains, even if highly rated. A chain with 2,000 reviews signals consistent chain quality. An independent with 2,000+ reviews signals a true local legend.

        TASK:
        1. DISCOVER: Provide 5 elite recommendations.
        2. EXPLAIN: In 'explanation', mention the current vibe and why it fits the specific "Hunger Path" (e.g., the 'handheld weight' or the 'broth depth').

        Return as JSON: { "recommendations": [{ "name": "", "dish": "", "explanation": "", "mapsUrl": "", "tips": ["insider tip 1", "insider tip 2", "insider tip 3"] }] }
        Each tip should be a short, practical insider tip about visiting this specific restaurant (best time to visit, what to order, hidden gem info, local secrets, etc.).
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
