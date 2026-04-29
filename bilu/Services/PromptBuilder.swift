//
//  PromptBuilder.swift
//  bilu
//

import Foundation

enum PromptBuilder {

    static func effectiveLocation(for selection: VibeSelection) -> String {
        let t = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let lat = selection.latitude, let lng = selection.longitude {
            return String(format: "%.4f° N, %.4f° W", lat, abs(lng))
        }
        return "your area"
    }

    // MARK: - Occasion-aware field visibility
    // Returns which survey steps were actually shown for this occasion.

    private static func showsCuisine(for occasion: String) -> Bool {
        !HomeViewModel.drinksOccasions.contains(occasion)
    }

    private static func showsPrice(for occasion: String) -> Bool {
        switch occasion {
        case "Date Night", "Sit Down Meal", "Big Group", "Celebration", "Sit Down", "No Rush": return true
        default: return false
        }
    }

    private static func showsPartySize(for occasion: String) -> Bool {
        switch occasion {
        case "Sit Down Meal", "Big Group", "Celebration", "Sit Down", "No Rush": return true
        default: return false
        }
    }

    // MARK: - Prompt assembly

    static func getPrompt(selection: VibeSelection) -> String {
        let location = effectiveLocation(for: selection)
        let openingLine: String = {
            if selection.useRadiusSearch,
               let lat = selection.latitude,
               let lng = selection.longitude {
                let coordLine = " (\(String(format: "%.4f", lat))° N, \(String(format: "%.4f", abs(lng)))° W)"
                return "Find 5 exceptional spots for \(selection.occasion) near \(location)\(coordLine), within \(String(format: "%.1f", selection.radiusMiles)) miles."
            }
            return "Find 5 exceptional spots for \(selection.occasion) in the greater \(location) area."
        }()

        // --- Mission lines (replaces both USER CONTEXT and Discovery Logic) ---
        var missionLines: [String] = []

        if let occasionPrompt = PromptConstants.occasionPrompts[selection.occasion] {
            missionLines.append(occasionPrompt)
        }

        if let kqPrompt = PromptConstants.keyQuestionPrompts[selection.keyQuestionAnswer], !kqPrompt.isEmpty {
            // Avoid repeating if same text somehow ended up in both
            if missionLines.last != kqPrompt {
                missionLines.append(kqPrompt)
            }
        }

        // Append time window / date detail if present
        if let tw = selection.keyQuestionTimeWindow { missionLines.append("Time preference: \(tw).") }
        if let dt = selection.keyQuestionDate       { missionLines.append("Date: \(dt).") }

        // Cuisine / food feeling first — "5 smash burger spots that are viral" beats
        // "5 viral places that serve smash burgers". Food type anchors the search.
        if showsCuisine(for: selection.occasion) {
            if selection.cuisineMode == "country", !selection.selectedCountry.isEmpty,
               let cp = PromptConstants.countryPrompts[selection.selectedCountry] {
                missionLines.append(cp)
            } else {
                for feeling in selection.foodFeelings {
                    let subs = selection.selectedSubOptions[feeling] ?? []
                    if subs.isEmpty {
                        // No sub-option drill-down: use category-level prompt.
                        if let fp = PromptConstants.foodFeelingPrompts[feeling] {
                            missionLines.append(fp)
                        }
                    } else {
                        // Use each selected sub-option's specific prompt.
                        for sub in subs {
                            if let fp = PromptConstants.foodFeelingPrompts[sub] {
                                missionLines.append(fp)
                            }
                        }
                    }
                }
            }
        }

        // Vibe filter comes after food type — it modifies how to rank, not what to find
        if !selection.selectedVibe.isEmpty,
           let vp = PromptConstants.vibePrompts[selection.selectedVibe] {
            missionLines.append(vp)
        }

        let mission = missionLines.joined(separator: "\n")

        // --- Constraints — only included when user explicitly applied fine-tune ---
        var constraints: [String] = []

        if selection.fineTuneApplied {
            if showsPrice(for: selection.occasion), !selection.pricePoints.isEmpty {
                constraints.append("Price range: \(selection.pricePoints.sorted().joined(separator: ", "))")
            }

            if showsPartySize(for: selection.occasion), selection.partySize > 1 {
                constraints.append("Party of \(selection.partySize)")
            }

            if selection.openNow {
                constraints.append("Must be open right now — reject any spot that is not currently open")
            }

            if !selection.parking.isEmpty {
                constraints.append("Parking: \(selection.parking.joined(separator: " or ")) available")
            }

            if selection.outdoorSeating {
                constraints.append("Must have confirmed outdoor seating")
            }

            if selection.petFriendly {
                constraints.append("Must be pet-friendly")
            }

            if selection.wheelchairAccess {
                constraints.append("Must have wheelchair-accessible entrance and seating")
            }
        }

        let constraintBlock = constraints.isEmpty ? "" :
            "\n\nConstraints:\n" + constraints.map { "- \($0)" }.joined(separator: "\n")

        // --- Recognition / chain preference ---
        // Strong preference, never a hard reject — model must always return results, never refuse.
        let chainNote: String
        if selection.keyQuestionAnswer == "Best quality nearby"
            || selection.keyQuestionAnswer == "Something new & trendy"
            || selection.selectedVibe == "⭐ Best rated"
            || selection.selectedVibe == "🔥 Trending" {
            chainNote = " Avoid corporate fast-casual franchise rollouts (e.g. Dave's Hot Chicken, Raising Cane's) when better options exist; chef-driven groups with a handful of locations that grew organically from a cult original are welcome."
        } else {
            chainNote = ""
        }

        let recognitionBlock = """

        Strongly prefer independent spots and small local groups with editorial recognition (Eater, Infatuation, Beli, Michelin Bib Gourmand, James Beard) or cult following. Include a chain only if no quality independents fit — never refuse the request.\(chainNote)
        """

        // --- Task ---
        let taskBlock = """

        Return up to 5 results as JSON: { "recommendations": [{ "name": "", "dish": "", "explanation": "", "mapsUrl": "" }] }
        Fewer than 5 is fine. If nothing fits, return { "recommendations": [] }. Always respond with JSON only — never refuse, never apologize, never write prose.
        Each explanation should name the vibe and why the spot fits.
        """

        return """
        \(openingLine)

        \(mission)\(constraintBlock)\(recognitionBlock)\(taskBlock)
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
