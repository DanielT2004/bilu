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
        occasion != "Cafe"
    }

    private static func showsPrice(for occasion: String) -> Bool {
        switch occasion {
        case "Date Night", "Sit Down Meal", "Big Group", "Celebration": return true
        default: return false
        }
    }

    private static func showsPartySize(for occasion: String) -> Bool {
        switch occasion {
        case "Sit Down Meal", "Big Group", "Celebration": return true
        default: return false
        }
    }

    // MARK: - Prompt assembly

    static func getPrompt(selection: VibeSelection) -> String {
        let location = effectiveLocation(for: selection)
        let coordLine: String = {
            if let lat = selection.latitude, let lng = selection.longitude {
                return " (\(String(format: "%.4f", lat))° N, \(String(format: "%.4f", abs(lng)))° W)"
            }
            return ""
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

        // Cuisine / food feeling — only if that step was shown
        if showsCuisine(for: selection.occasion) {
            if selection.cuisineMode == "country", !selection.selectedCountry.isEmpty,
               let cp = PromptConstants.countryPrompts[selection.selectedCountry] {
                missionLines.append(cp)
            } else {
                for feeling in selection.foodFeelings {
                    if let fp = PromptConstants.foodFeelingPrompts[feeling] {
                        missionLines.append(fp)
                    }
                }
            }
        }

        let mission = missionLines.joined(separator: " ")

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

        // --- Recognition / chain filter ---
        // Extra chain guidance for paths where quality is the explicit priority
        let chainNote: String
        if selection.keyQuestionAnswer == "Best quality nearby" || selection.keyQuestionAnswer == "Something new & trendy" {
            chainNote = " Reject corporate fast-casual chains that expanded via franchise rollout (e.g. Dave's Hot Chicken, Raising Cane's). Allow chef-driven groups of 2–8 locations that grew organically from a cult original with editorial recognition."
        } else {
            chainNote = ""
        }

        let recognitionBlock = """

        // Prioritize independent or small-local-group spots with strong local reputation — high review count, editorial coverage (Eater, Infatuation, Beli, Michelin Bib Gourmand, James Beard), or cult following. Deprioritize national chains.\(chainNote)
        """

        // --- Task ---
        let taskBlock = """

        Find 5 results. For each, write an 'explanation' that names the vibe and why it matches what the user is after.

        Return as JSON: { "recommendations": [{ "name": "", "dish": "", "explanation": "", "mapsUrl": "" }] }
        """

        return """
        Find 5 exceptional spots for \(selection.occasion) near \(location)\(coordLine), within \(String(format: "%.1f", selection.radiusMiles)) miles.

        \(mission)\(constraintBlock)\(recognitionBlock)\(taskBlock)
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
