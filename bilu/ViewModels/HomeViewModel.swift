//
//  HomeViewModel.swift
//  bilu
//

import Foundation
import Combine

enum Step: String, CaseIterable {
    case occasion
    case keyQuestion
    case foodFeeling
    case location
    case loading
    case reveal
}

struct VibeOption {
    let key: String
    let displayTitle: String
    let desc: String
    let systemImage: String
}

struct HungerOption {
    let key: String
    let displayTitle: String
    let desc: String
    let systemImage: String
}

enum KeyQuestionSubPicker: Equatable {
    case none
    case timeWindows(options: [String])
    case date
}

struct KeyQuestionOption: Equatable {
    let key: String
    let icon: String
    let title: String
    let desc: String
    let badge: String?
    let subPicker: KeyQuestionSubPicker
}

struct KeyQuestion: Equatable {
    let columnLabel: String
    let question: String
    let insight: String
    let options: [KeyQuestionOption]
}

struct FoodFeelingOption: Equatable {
    let key: String
    let title: String
    let desc: String
    let exampleMatches: [String]
    let isSurprise: Bool
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var step: Step = .occasion
    @Published var selection: VibeSelection
    @Published var recommendations: [Recommendation] = []
    @Published var loadingPhase: String = "Scanning the streets\nfor your vibe..."

    init() {
        self.selection = VibeSelection()
    }

    // MARK: - Navigation

    func handleOccasion(_ occasion: String) {
        selection.occasion = occasion
        selection.keyQuestionAnswer = ""
        selection.keyQuestionTimeWindow = nil
        selection.keyQuestionDate = nil
        selection.foodFeeling = ""
        selection.location = ""
        selection.pricePoints = ["$$", "$$$"]
        selection.partySize = 2
        selection.openNow = false
        step = .keyQuestion
    }

    func goBack() {
        switch step {
        case .keyQuestion: step = .occasion
        case .foodFeeling: step = .keyQuestion
        case .location: step = .foodFeeling
        default: break
        }
    }

    func selectKeyQuestionAnswer(_ key: String) {
        selection.keyQuestionAnswer = key
        selection.keyQuestionTimeWindow = nil
        selection.keyQuestionDate = nil
    }

    func selectKeyQuestionTimeWindow(_ value: String) {
        selection.keyQuestionTimeWindow = value
    }

    func selectKeyQuestionDate(_ value: String) {
        selection.keyQuestionDate = value
    }

    func selectFoodFeeling(_ key: String) {
        selection.foodFeeling = key
        if fineTuneType == "none" {
            Task {
                try? await Task.sleep(nanoseconds: 260_000_000)
                await submitSurvey()
            }
        } else {
            step = .location
        }
    }

    // MARK: - Fine-tune

    var fineTuneType: String {
        switch selection.occasion {
        case "Quick Bite":                     return "none"
        case "Date Night":                     return "price"
        case "Sit Down Meal", "Big Group", "Celebration": return "full"
        case "Cafe", "Happy Hour":             return "opennow"
        default:                               return "opennow"
        }
    }

    var fineTuneTitle: String {
        fineTuneType == "opennow" ? "Almost\nthere" : "Fine-tune\nyour search"
    }

    var showPriceSection: Bool { fineTuneType == "price" || fineTuneType == "full" }
    var showPartySizeSection: Bool { fineTuneType == "full" }

    var canContinueFromKeyQuestion: Bool {
        guard !selection.keyQuestionAnswer.isEmpty else { return false }
        guard let kq = keyQuestion,
              let opt = kq.options.first(where: { $0.key == selection.keyQuestionAnswer }) else { return false }
        switch opt.subPicker {
        case .none:        return true
        case .timeWindows: return selection.keyQuestionTimeWindow != nil
        case .date:        return selection.keyQuestionDate != nil
        }
    }

    func togglePrice(_ tier: String) {
        if selection.pricePoints.contains(tier) {
            if selection.pricePoints.count > 1 {
                selection.pricePoints.removeAll { $0 == tier }
            }
        } else {
            selection.pricePoints.append(tier)
        }
    }

    func adjustPartySize(_ delta: Int) {
        selection.partySize = max(1, min(20, selection.partySize + delta))
    }

    func toggleOpenNow() {
        selection.openNow.toggle()
    }

    // MARK: - Legacy

    func toggleVibe(_ key: String) {
        if selection.vibe.contains(key) {
            selection.vibe.removeAll { $0 == key }
        } else {
            selection.vibe.append(key)
        }
    }

    func toggleHunger(_ key: String) {
        if selection.hunger.contains(key) {
            selection.hunger.removeAll { $0 == key }
        } else {
            selection.hunger.append(key)
        }
    }

    func reset() {
        step = .occasion
        selection = VibeSelection()
        recommendations = []
    }

    // MARK: - Survey Submit

    func submitSurvey() async {
        step = .loading
        let messages = [
            "Scanning the streets\nfor your vibe...",
            "Reading the TikTok\nbuzz near you...",
            "Checking OpenTable\navailability...",
            "Curating your\nperfect shortlist..."
        ]
        loadingPhase = messages[0]

        Task {
            var idx = 0
            while step == .loading {
                try? await Task.sleep(nanoseconds: 900_000_000)
                idx = (idx + 1) % messages.count
                if step == .loading { loadingPhase = messages[idx] }
            }
        }

        recommendations = await GeminiService.getVibeRecommendations(selection: selection)
        step = .reveal
    }

    // MARK: - Map label

    var mapLocationLabel: String {
        let loc = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return loc.isEmpty ? "Los Angeles" : loc
    }

    // MARK: - Progress

    var progressStepIndex: Int? {
        switch step {
        case .occasion:                return nil
        case .keyQuestion:             return 1
        case .foodFeeling:             return 2
        case .location:                return 3
        case .loading, .reveal:        return nil
        }
    }

    static let stepsForProgress: [(id: Step, label: String)] = [
        (.occasion, "OCCASION"),
        (.keyQuestion, "KEY Q"),
        (.foodFeeling, "FOOD FEEL"),
        (.location, "DETAILS")
    ]

    // MARK: - Key Questions

    var keyQuestion: KeyQuestion? {
        switch selection.occasion {
        case "Quick Bite":
            return KeyQuestion(
                columnLabel: "Quick Bite · Priority",
                question: "What matters most\nright now?",
                insight: "Speed vs discovery are completely different restaurants. One question here replaces an entire vibe screen.",
                options: [
                    KeyQuestionOption(key: "Fastest near me", icon: "⚡", title: "Fastest near me", desc: "Hungry now, no time to think", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Best quality nearby", icon: "⭐", title: "Best quality nearby", desc: "Worth a short walk for great food", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Something new & trendy", icon: "🔥", title: "Something new & trendy", desc: "Open to discovering a spot", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Cheap & good", icon: "💸", title: "Cheap & good", desc: "Value is the priority", badge: nil, subPicker: .none)
                ]
            )
        case "Date Night":
            return KeyQuestion(
                columnLabel: "Date Night · Availability",
                question: "When are you\nplanning to go?",
                insight: "Walk-in availability is untrackable — but reservations are. OpenTable confirms real availability for tonight or any future date.",
                options: [
                    KeyQuestionOption(
                        key: "Tonight", icon: "🌙", title: "Tonight",
                        desc: "Find places with open reservations now",
                        badge: "OpenTable live",
                        subPicker: .timeWindows(options: ["Any time", "Early dinner (5–7pm)", "Prime time (7–9pm)", "Late seating (9pm+)"])
                    ),
                    KeyQuestionOption(
                        key: "Planning ahead", icon: "📅", title: "Planning ahead",
                        desc: "Pick a date, find confirmed availability",
                        badge: "OpenTable live",
                        subPicker: .date
                    ),
                    KeyQuestionOption(key: "Outdoor / patio", icon: "🌿", title: "Outdoor / patio", desc: "Want to sit outside, flexible on timing", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "No must-haves", icon: "✨", title: "No must-haves", desc: "Just find the best date night spots", badge: nil, subPicker: .none)
                ]
            )
        case "Sit Down Meal":
            return KeyQuestion(
                columnLabel: "Sit Down Meal · Vibe",
                question: "What does the group\nactually want?",
                insight: "Friend groups care about atmosphere and social value. Aesthetic spots and low-key spots are completely different recommendations.",
                options: [
                    KeyQuestionOption(key: "Aesthetic & worth posting", icon: "📸", title: "Aesthetic & worth posting", desc: "Vibe matters, somewhere that looks great", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Chill & low-key", icon: "😌", title: "Chill & low-key", desc: "No fuss, just great food and good time", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Good value", icon: "💸", title: "Good value", desc: "Splitting the bill, not breaking the bank", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Trendy & buzzy", icon: "🔥", title: "Trendy & buzzy", desc: "New spot, energy, something to talk about", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Just great food", icon: "🍴", title: "Just great food", desc: "No preference on vibe or atmosphere", badge: nil, subPicker: .none)
                ]
            )
        case "Big Group":
            return KeyQuestion(
                columnLabel: "Big Group · Priority",
                question: "What's the\nnon-negotiable?",
                insight: "Logistics come before food for big groups. Private space and reservations are things Google reviews and OpenTable can confirm reliably.",
                options: [
                    KeyQuestionOption(key: "Private or semi-private space", icon: "🏠", title: "Private or semi-private space", desc: "Want our own area, not scattered", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Reservation available", icon: "📋", title: "Reservation available", desc: "Need to book — can't risk a walk-in", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Central & easy to get to", icon: "📍", title: "Central & easy to get to", desc: "Transit, parking, accessible location", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "No must-haves", icon: "👥", title: "No must-haves", desc: "Just find somewhere great for us", badge: nil, subPicker: .none)
                ]
            )
        case "Cafe":
            return KeyQuestion(
                columnLabel: "Cafe · Mission",
                question: "What's the actual reason\nyou're going?",
                insight: "The most critical split in the whole app. A loud trendy cafe ruins a study session. Reviews reliably surface wifi and study-friendliness.",
                options: [
                    KeyQuestionOption(key: "Here to study or work", icon: "💻", title: "Here to study or work", desc: "Quiet, wifi, able to stay long", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Just great coffee", icon: "☕", title: "Just great coffee", desc: "Specialty, quality-first, quick visit", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Catching up with someone", icon: "💬", title: "Catching up with someone", desc: "Relaxed, comfortable, conversational", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Brunch & bites too", icon: "🥐", title: "Brunch & bites too", desc: "Want real food, not just drinks", badge: nil, subPicker: .none)
                ]
            )
        case "Happy Hour":
            return KeyQuestion(
                columnLabel: "Happy Hour · Scene",
                question: "What kind of spot\nare you after?",
                insight: "Happy hour is a scheduled policy — Google reliably lists times and reviews confirm atmosphere. Atmosphere matters more than the deals.",
                options: [
                    KeyQuestionOption(key: "Rooftop or outdoor", icon: "🌇", title: "Rooftop or outdoor", desc: "Views, fresh air, elevated feel", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Trendy cocktail bar", icon: "🍹", title: "Trendy cocktail bar", desc: "Craft drinks, aesthetic, worth posting", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Chill dive bar", icon: "🍺", title: "Chill dive bar", desc: "Low-key, cheap, no pretense", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Wine & grazing", icon: "🍷", title: "Wine & grazing", desc: "Relaxed, charcuterie, conversation-first", badge: nil, subPicker: .none)
                ]
            )
        case "Celebration":
            return KeyQuestion(
                columnLabel: "Celebration · Occasion",
                question: "What are we\ncelebrating?",
                insight: "Birthday dinner and a big night out are completely different restaurants. This single question does the most filtering in the entire survey.",
                options: [
                    KeyQuestionOption(key: "Birthday dinner", icon: "🎂", title: "Birthday dinner", desc: "Special meal, meaningful setting", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Big night out", icon: "🥂", title: "Big night out", desc: "High energy, make memories", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Anniversary", icon: "💍", title: "Anniversary", desc: "Intimate, romantic, pull out all stops", badge: nil, subPicker: .none),
                    KeyQuestionOption(key: "Achievement or graduation", icon: "🎓", title: "Achievement or graduation", desc: "Group celebration, proud moment", badge: nil, subPicker: .none)
                ]
            )
        default:
            return nil
        }
    }

    // MARK: - Food Feelings

    var foodFeelingsForOccasion: [FoodFeelingOption] {
        switch selection.occasion {
        case "Quick Bite":
            return [
                FoodFeelingOption(key: "Fresh & crisp", title: "Fresh & crisp", desc: "Light, clean, bright flavours", exampleMatches: ["Sushi", "Poke bowls", "Vietnamese", "Ceviche", "Greek salads"], isSurprise: false),
                FoodFeelingOption(key: "Doughy & loaded", title: "Doughy & loaded", desc: "Filling, comforting, hands-on", exampleMatches: ["Pizza", "Burgers", "Sandwiches", "Loaded fries"], isSurprise: false),
                FoodFeelingOption(key: "Soupy & warming", title: "Soupy & warming", desc: "Brothy, cozy, deeply comforting", exampleMatches: ["Ramen", "Pho", "Udon", "Dumpling soup"], isSurprise: false),
                FoodFeelingOption(key: "Crispy & crunchy", title: "Crispy & crunchy", desc: "Fried, textured, satisfying crunch", exampleMatches: ["Fried chicken", "Tempura", "Tacos", "Korean fried"], isSurprise: false),
                FoodFeelingOption(key: "Spicy & bold", title: "Spicy & bold", desc: "Heat, depth, punchy flavours", exampleMatches: ["Thai", "Sichuan", "Korean", "Mexican"], isSurprise: false),
                FoodFeelingOption(key: "Surprise me", title: "Surprise me", desc: "Just bring the best near me", exampleMatches: [], isSurprise: true)
            ]
        case "Date Night":
            return [
                FoodFeelingOption(key: "Fresh & crisp", title: "Fresh & crisp", desc: "Light, clean, bright flavours", exampleMatches: ["Sushi", "Poke bowls", "Vietnamese", "Ceviche", "Greek salads"], isSurprise: false),
                FoodFeelingOption(key: "Rich & indulgent", title: "Rich & indulgent", desc: "Decadent, buttery, full-on", exampleMatches: ["Steakhouse", "French bistro", "Pasta", "Wagyu"], isSurprise: false),
                FoodFeelingOption(key: "Stew-y & saucy", title: "Stew-y & saucy", desc: "Slow-cooked, saucy, deeply layered", exampleMatches: ["Curry", "Tagine", "Ethiopian", "Ragu"], isSurprise: false),
                FoodFeelingOption(key: "Smoky & charred", title: "Smoky & charred", desc: "Grilled, BBQ, fire-kissed", exampleMatches: ["BBQ", "Korean BBQ", "Kebabs", "Yakitori"], isSurprise: false),
                FoodFeelingOption(key: "Surprise me", title: "Surprise me", desc: "Just bring the best near me", exampleMatches: [], isSurprise: true)
            ]
        case "Sit Down Meal":
            return [
                FoodFeelingOption(key: "Doughy & loaded", title: "Doughy & loaded", desc: "Filling, comforting, hands-on", exampleMatches: ["Pizza", "Burgers", "Sandwiches", "Loaded fries"], isSurprise: false),
                FoodFeelingOption(key: "Smoky & charred", title: "Smoky & charred", desc: "Grilled, BBQ, fire-kissed", exampleMatches: ["BBQ", "Korean BBQ", "Kebabs", "Yakitori"], isSurprise: false),
                FoodFeelingOption(key: "Spicy & bold", title: "Spicy & bold", desc: "Heat, depth, punchy flavours", exampleMatches: ["Thai", "Sichuan", "Korean", "Mexican"], isSurprise: false),
                FoodFeelingOption(key: "Stew-y & saucy", title: "Stew-y & saucy", desc: "Slow-cooked, saucy, deeply layered", exampleMatches: ["Curry", "Tagine", "Ethiopian", "Ragu"], isSurprise: false),
                FoodFeelingOption(key: "Crispy & crunchy", title: "Crispy & crunchy", desc: "Fried, textured, satisfying crunch", exampleMatches: ["Fried chicken", "Tempura", "Tacos", "Korean fried"], isSurprise: false),
                FoodFeelingOption(key: "Fresh & crisp", title: "Fresh & crisp", desc: "Light, clean, bright flavours", exampleMatches: ["Sushi", "Poke bowls", "Vietnamese", "Ceviche"], isSurprise: false),
                FoodFeelingOption(key: "Surprise me", title: "Surprise me", desc: "Just bring the best near me", exampleMatches: [], isSurprise: true)
            ]
        case "Big Group":
            return [
                FoodFeelingOption(key: "Smoky & charred", title: "Smoky & charred", desc: "Grilled, BBQ, fire-kissed", exampleMatches: ["BBQ", "Korean BBQ", "Kebabs", "Yakitori"], isSurprise: false),
                FoodFeelingOption(key: "Spicy & bold", title: "Spicy & bold", desc: "Heat, depth, punchy flavours", exampleMatches: ["Thai", "Sichuan", "Korean", "Mexican"], isSurprise: false),
                FoodFeelingOption(key: "Soupy & warming", title: "Soupy & warming", desc: "Brothy, cozy, deeply comforting", exampleMatches: ["Ramen", "Pho", "Udon", "Dumpling soup"], isSurprise: false),
                FoodFeelingOption(key: "Stew-y & saucy", title: "Stew-y & saucy", desc: "Slow-cooked, saucy, deeply layered", exampleMatches: ["Curry", "Tagine", "Ethiopian", "Ragu"], isSurprise: false),
                FoodFeelingOption(key: "Doughy & loaded", title: "Doughy & loaded", desc: "Filling, comforting, hands-on", exampleMatches: ["Pizza", "Burgers", "Sandwiches", "Loaded fries"], isSurprise: false),
                FoodFeelingOption(key: "Surprise me", title: "Surprise me", desc: "Just bring the best near me", exampleMatches: [], isSurprise: true)
            ]
        case "Cafe":
            return [
                FoodFeelingOption(key: "Fresh & crisp", title: "Fresh & crisp", desc: "Light, clean, bright flavours", exampleMatches: ["Açaí", "Grain bowls", "Avocado toast", "Smoothies"], isSurprise: false),
                FoodFeelingOption(key: "Doughy & loaded", title: "Doughy & loaded", desc: "Filling, comforting, hands-on", exampleMatches: ["Croissants", "Pastries", "Sandwiches", "Waffles"], isSurprise: false),
                FoodFeelingOption(key: "Surprise me", title: "Surprise me", desc: "Just bring the best near me", exampleMatches: [], isSurprise: true)
            ]
        case "Happy Hour":
            return [
                FoodFeelingOption(key: "Crispy & crunchy", title: "Crispy & crunchy", desc: "Fried, textured, satisfying crunch", exampleMatches: ["Wings", "Fries", "Taquitos", "Calamari"], isSurprise: false),
                FoodFeelingOption(key: "Fresh & crisp", title: "Fresh & crisp", desc: "Light, clean, bright flavours", exampleMatches: ["Oysters", "Ceviche", "Bruschetta", "Tartare"], isSurprise: false),
                FoodFeelingOption(key: "Doughy & loaded", title: "Doughy & loaded", desc: "Filling, comforting, hands-on", exampleMatches: ["Sliders", "Flatbreads", "Nachos", "Quesadillas"], isSurprise: false),
                FoodFeelingOption(key: "Surprise me", title: "Surprise me", desc: "Just bring the best near me", exampleMatches: [], isSurprise: true)
            ]
        case "Celebration":
            return [
                FoodFeelingOption(key: "Rich & indulgent", title: "Rich & indulgent", desc: "Decadent, buttery, full-on", exampleMatches: ["Steakhouse", "French bistro", "Pasta", "Wagyu"], isSurprise: false),
                FoodFeelingOption(key: "Fresh & crisp", title: "Fresh & crisp", desc: "Light, clean, bright flavours", exampleMatches: ["Sushi", "Poke bowls", "Vietnamese", "Ceviche"], isSurprise: false),
                FoodFeelingOption(key: "Smoky & charred", title: "Smoky & charred", desc: "Grilled, BBQ, fire-kissed", exampleMatches: ["BBQ", "Korean BBQ", "Kebabs", "Yakitori"], isSurprise: false),
                FoodFeelingOption(key: "Stew-y & saucy", title: "Stew-y & saucy", desc: "Slow-cooked, saucy, deeply layered", exampleMatches: ["Curry", "Tagine", "Ethiopian", "Ragu"], isSurprise: false),
                FoodFeelingOption(key: "Surprise me", title: "Surprise me", desc: "Just bring the best near me", exampleMatches: [], isSurprise: true)
            ]
        default:
            return []
        }
    }
}
