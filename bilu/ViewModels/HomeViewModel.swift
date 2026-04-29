//
//  HomeViewModel.swift
//  bilu
//

import Foundation
import Combine
import CoreLocation
import MapKit

enum Step: String, CaseIterable {
    case occasion
    case keyQuestion
    case foodFeeling
    case drinksSubFlow
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

struct FoodSubOption: Equatable {
    let key: String
    let emoji: String
    let label: String
}

struct FoodCategoryOption: Equatable {
    let key: String
    let emoji: String
    let title: String
    let subtitle: String
    let isSurprise: Bool
    let isFullWidth: Bool
    let subOptions: [FoodSubOption]
}

enum CuisineMode {
    case vibe
    case country
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var step: Step = .occasion
    @Published var selection: VibeSelection
    @Published var recommendations: [Recommendation] = []
    @Published var lastSearchFailure: SearchFailure? = nil
    @Published var lastSearchWasRelaxed: Bool = false
    @Published var isEnriching: Bool = false
    @Published var loadingPhase: String = "Scanning the streets\nfor your vibe..."
    @Published var detectedLocation: String = ""
    @Published var cuisineMode: CuisineMode = .vibe
    @Published var serviceCategory: String = "eat"
    @Published var selectedVibe: String = ""
    @Published var selectedNoRushOccasion: String = "🍽 Best food"
    @Published var drinksSubType: String = ""
    @Published var tikTokVideos: [String: [TikTokVideo]] = [:]

    /// Tracks the active search so it can be cancelled when the user exits mid-search.
    private var searchTask: Task<Void, Never>?

    static let newTimeOccasions: Set<String> = ["Casual", "Sit Down", "No Rush", "Brunch", "Late Night"]
    static let drinksOccasions:  Set<String> = ["Cafe", "Bakery", "Dessert", "Drinks"]

    static let countries: [(flag: String, name: String)] = [
        ("🇺🇸", "American"), ("🇮🇹", "Italian"), ("🇲🇽", "Mexican"),
        ("🇯🇵", "Japanese"), ("🇨🇳", "Chinese"), ("🇮🇳", "Indian"),
        ("🇹🇭", "Thai"), ("🇰🇷", "Korean"), ("🌊", "Mediterranean"),
        ("🇫🇷", "French"), ("🇬🇷", "Greek"), ("🇻🇳", "Vietnamese"),
        ("🥙", "Middle Eastern"), ("🇪🇸", "Spanish"), ("🇧🇷", "Brazilian"),
        ("🇪🇹", "Ethiopian"), ("🇵🇪", "Peruvian")
    ]

    init() {
        self.selection = VibeSelection()
    }

    // MARK: - Navigation

    func handleOccasion(_ occasion: String) {
        selection.occasion = occasion
        selection.keyQuestionAnswer = ""
        selection.keyQuestionTimeWindow = nil
        selection.keyQuestionDate = nil
        selection.foodFeelings = []
        selection.selectedSubOptions = [:]
        selection.selectedCountry = ""
        selection.cuisineMode = "vibe"
        cuisineMode = .vibe
        selection.fineTuneApplied = false
        selection.parking = []
        selection.outdoorSeating = false
        selection.petFriendly = false
        selection.wheelchairAccess = false
        selection.location = ""
        selection.pricePoints = ["$$", "$$$"]
        selection.partySize = 2
        selection.openNow = false

        if Self.drinksOccasions.contains(occasion) {
            if occasion == "Bakery" {
                selection.foodFeelings = ["Surprise me"]
                searchTask = Task { await submitSurvey() }
            } else {
                step = .drinksSubFlow
            }
        } else if Self.newTimeOccasions.contains(occasion) {
            if occasion == "No Rush" {
                selectedNoRushOccasion = "🍽 Best food"
                selection.selectedVibe = "🍽 Best food"
            } else {
                selectedVibe = defaultVibe(for: occasion)
                selection.selectedVibe = selectedVibe
            }
            step = .foodFeeling
        } else {
            step = .keyQuestion
        }
    }

    func goBack() {
        switch step {
        case .keyQuestion:    step = .occasion
        case .drinksSubFlow:  step = .occasion
        case .foodFeeling:
            if Self.newTimeOccasions.contains(selection.occasion) {
                step = .occasion
            } else {
                step = .keyQuestion
            }
        case .location:       step = .foodFeeling
        case .loading, .reveal: reset()   // back/X both go home from results or mid-search
        default:              break
        }
    }

    func selectKeyQuestionAnswer(_ key: String) {
        selection.keyQuestionAnswer = key
        selection.keyQuestionTimeWindow = nil
        // Pre-populate today's date for options that use the date sub-picker
        let usesDatePicker = keyQuestion?.options.first(where: { $0.key == key })?.subPicker == .date
        if usesDatePicker {
            let df = DateFormatter()
            df.calendar = Calendar(identifier: .gregorian)
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "yyyy-MM-dd"
            selection.keyQuestionDate = df.string(from: Date())
        } else {
            selection.keyQuestionDate = nil
        }
    }

    func selectKeyQuestionTimeWindow(_ value: String) {
        selection.keyQuestionTimeWindow = value
    }

    func selectKeyQuestionDate(_ value: String) {
        selection.keyQuestionDate = value
    }

    func selectFoodFeeling(_ key: String) {
        if key == "Surprise me" {
            selection.selectedSubOptions = [:]
            selection.foodFeelings = selection.foodFeelings.contains("Surprise me") ? [] : ["Surprise me"]
        } else {
            selection.foodFeelings.removeAll { $0 == "Surprise me" }
            selection.selectedSubOptions.removeValue(forKey: "Surprise me")
            if let idx = selection.foodFeelings.firstIndex(of: key) {
                selection.foodFeelings.remove(at: idx)
                selection.selectedSubOptions.removeValue(forKey: key)
            } else {
                selection.foodFeelings.append(key)
            }
        }
    }

    func selectSubOption(_ subKey: String, forCategory categoryKey: String) {
        if !selection.foodFeelings.contains(categoryKey) {
            selection.foodFeelings.append(categoryKey)
        }
        var subs = selection.selectedSubOptions[categoryKey] ?? []
        if let idx = subs.firstIndex(of: subKey) {
            subs.remove(at: idx)
        } else {
            subs.append(subKey)
        }
        selection.selectedSubOptions[categoryKey] = subs.isEmpty ? nil : subs
    }

    func selectCountry(_ country: String) {
        selection.selectedCountry = country
        selection.foodFeelings = []
    }

    func setCuisineMode(_ mode: CuisineMode) {
        cuisineMode = mode
        if mode == .vibe {
            selection.selectedCountry = ""
            selection.cuisineMode = "vibe"
        } else {
            selection.foodFeelings = []
            selection.cuisineMode = "country"
        }
    }

    func continueFromFoodFeeling() {
        let canContinue = cuisineMode == .vibe
            ? !selection.foodFeelings.isEmpty
            : !selection.selectedCountry.isEmpty
        guard canContinue else { return }
        selection.cuisineMode = cuisineMode == .country ? "country" : "vibe"
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            await submitSurvey()
        }
    }

    func openFineTune() {
        selection.cuisineMode = cuisineMode == .country ? "country" : "vibe"
        step = .location
    }

    func proceedWithFineTune() {
        selection.fineTuneApplied = true
        selection.location = effectiveLocation
        searchTask = Task { await submitSurvey() }
    }

    func removeFineTune() {
        selection.fineTuneApplied = false
        selection.pricePoints = ["$$", "$$$"]
        selection.partySize = 2
        selection.openNow = false
        selection.parking = []
        selection.outdoorSeating = false
        selection.petFriendly = false
        selection.wheelchairAccess = false
        step = .foodFeeling
    }

    var canContinueFromFoodFeeling: Bool {
        cuisineMode == .vibe ? !selection.foodFeelings.isEmpty : !selection.selectedCountry.isEmpty
    }

    // MARK: - Fine-tune

    var fineTuneType: String {
        switch selection.occasion {
        case "Quick Bite":                                 return "none"
        case "Date Night":                                 return "price"
        case "Sit Down Meal", "Big Group", "Celebration":  return "full"
        case "Cafe":                                       return "none"
        case "Happy Hour":                                 return "opennow"
        case "Casual", "Brunch", "Late Night":             return "opennow"
        case "Sit Down", "No Rush":                        return "full"
        default:                                           return "opennow"
        }
    }

    var fineTuneTitle: String {
        fineTuneType == "opennow" ? "Almost\nthere" : "Fine-tune\nyour search"
    }

    var showPriceSection: Bool { fineTuneType == "price" || fineTuneType == "full" }
    var showPartySizeSection: Bool { fineTuneType == "full" }

    func continueFromKeyQuestion() {
        if selection.occasion == "Cafe" {
            selection.foodFeelings = [cafeDefaultFeeling(for: selection.keyQuestionAnswer)]
            searchTask = Task { await submitSurvey() }
        } else {
            step = .foodFeeling
        }
    }

    private func cafeDefaultFeeling(for answer: String) -> String {
        switch answer {
        case "Here to study or work": return "Fresh & crisp"
        case "Brunch & bites too":    return "Doughy & loaded"
        default:                      return "Surprise me"
        }
    }

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

    func toggleParking(_ option: String) {
        if let idx = selection.parking.firstIndex(of: option) {
            selection.parking.remove(at: idx)
        } else {
            selection.parking.append(option)
        }
    }

    func toggleOutdoorSeating() { selection.outdoorSeating.toggle() }
    func togglePetFriendly()    { selection.petFriendly.toggle() }
    func toggleWheelchairAccess() { selection.wheelchairAccess.toggle() }

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
        searchTask?.cancel()
        searchTask = nil
        step = .occasion
        selection = VibeSelection()
        recommendations = []
        lastSearchFailure = nil
        lastSearchWasRelaxed = false
        isEnriching = false
        cuisineMode = .vibe
        serviceCategory = "eat"
        selectedVibe = ""
        selectedNoRushOccasion = "🍽 Best food"
        drinksSubType = ""
        tikTokVideos = [:]
    }

    // MARK: - Survey Submit

    func submitSurvey() async {
        step = .loading
        lastSearchFailure = nil
        lastSearchWasRelaxed = false
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

        // handleOccasion resets selection.location on each occasion tap — restore from
        // the geocoded city name before building the prompt.
        if selection.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !detectedLocation.isEmpty {
            selection.location = detectedLocation
        }

        // Phase 1: Gemini results — show cards immediately
        let outcome = await GeminiService.getVibeRecommendations(selection: selection)
        // If the user exited mid-search (reset/back), don't transition to results.
        guard step == .loading else { return }
        recommendations = outcome.result.recommendations
        lastSearchFailure = outcome.failure
        lastSearchWasRelaxed = outcome.result.relaxed ?? false
        step = .reveal

        // No grounding metadata on transport errors — skip enrichment.
        guard outcome.failure != .transportError else { return }

        // Phase 2: Places enrichment in background — updates images + map pins
        let groundingPlaces = outcome.result.groundingPlaces ?? []
        let location = effectiveLocation
        isEnriching = true
        Task {
            let enriched = await GeminiService.enrichRecommendations(
                outcome.result.recommendations,
                groundingPlaces: groundingPlaces,
                location: location
            )
            recommendations = enriched
            isEnriching = false
        }

    }

    func fetchTikTokVideos(for rec: Recommendation) async -> [TikTokVideo] {
        if let cached = tikTokVideos[rec.id], !cached.isEmpty { return cached }
        let city = await cityForTikTok()
        let query = city.isEmpty ? rec.name : "\(rec.name) \(city)"
        let videos = await TikTokService.fetchVideos(query: query)
        tikTokVideos[rec.id] = videos
        return videos
    }

    // MARK: - Map label

    var mapLocationLabel: String {
        let loc = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loc.isEmpty { return loc }
        return detectedLocation.isEmpty ? "Near pin" : detectedLocation
    }

    /// Returns a city-level string suitable for TikTok search queries.
    /// Prefers reverse-geocoding coordinates to "City, State".
    /// Falls back to extracting the city from the user-typed location string.
    func cityForTikTok() async -> String {
        // 1. Reverse-geocode coordinates if available — most reliable
        if let lat = selection.latitude, let lng = selection.longitude {
            let coord = CLLocation(latitude: lat, longitude: lng)
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(coord).first {
                let city  = placemark.locality ?? ""
                let state = placemark.administrativeArea ?? ""
                if !city.isEmpty {
                    return state.isEmpty ? city : "\(city), \(state)"
                }
            }
        }

        // 2. User typed a location — take the last meaningful comma-separated segment
        //    e.g. "Reynier Village, Los Angeles, CA" → "Los Angeles, CA"
        let typed = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            let parts = typed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2 {
                // Drop the first part (neighborhood/street) and rejoin the rest
                return parts.dropFirst().joined(separator: ", ")
            }
            return typed
        }

        // 3. detectedLocation (set by the map widget) — same strip logic
        if !detectedLocation.isEmpty {
            let parts = detectedLocation.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2 { return parts.dropFirst().joined(separator: ", ") }
            return detectedLocation
        }

        return ""
    }

    var effectiveLocation: String {
        let loc = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loc.isEmpty { return loc }
        if !detectedLocation.isEmpty { return detectedLocation }
        if let lat = selection.latitude, let lng = selection.longitude {
            return String(format: "%.4f° N, %.4f° W", lat, abs(lng))
        }
        return "your area"
    }

    // MARK: - Progress

    var progressStepIndex: Int? {
        switch step {
        case .occasion:              return nil
        case .keyQuestion:           return 1
        case .drinksSubFlow:         return nil
        case .foodFeeling:
            // New time-based occasions skip keyQuestion — don't show a misleading step count
            if Self.newTimeOccasions.contains(selection.occasion) { return nil }
            return 2
        case .location:              return 3
        case .loading, .reveal:      return nil
        }
    }

    static let stepsForProgress: [(id: Step, label: String)] = [
        (.occasion, "OCCASION"),
        (.keyQuestion, "KEY Q"),
        (.foodFeeling, "FOOD FEEL"),
        (.location, "DETAILS")
    ]

    // MARK: - Vibe (new time-based flow)

    func defaultVibe(for occasion: String) -> String {
        switch occasion {
        case "Casual", "Late Night": return "🔥 Trending"
        case "Sit Down", "Brunch":   return "⭐ Best rated"
        default:                     return "🔥 Trending"
        }
    }

    func vibeOptions(for occasion: String) -> [String] {
        switch occasion {
        case "Casual":     return ["🔥 Trending", "⭐ Best rated", "🌟 Hidden gem"]
        case "Sit Down":   return ["🔥 Trending", "⭐ Best rated", "📸 Aesthetic", "🌟 Hidden gem"]
        case "Brunch":     return ["🔥 Trending", "⭐ Best rated", "📸 Aesthetic"]
        case "Late Night": return ["🔥 Trending", "⭐ Best rated", "🌟 Hidden gem"]
        default:           return ["🔥 Trending", "⭐ Best rated", "🌟 Hidden gem"]
        }
    }

    func selectVibe(_ vibe: String) {
        selectedVibe = vibe
        selection.selectedVibe = vibe
    }

    func selectNoRushOccasion(_ val: String) {
        selectedNoRushOccasion = val
        selection.selectedVibe = val
    }

    func selectDrinksSubType(_ subType: String) {
        drinksSubType = subType
        selection.keyQuestionAnswer = subType
        selection.foodFeelings = ["Surprise me"]
        searchTask = Task { await submitSurvey() }
    }

    var drinksSubFlowOptions: [(emoji: String, title: String, sub: String)] {
        switch selection.occasion {
        case "Cafe":
            return [("☕", "Great coffee",     "Specialty, matcha, quality first"),
                    ("💻", "Work or study",    "Wifi, quiet, long stay ok"),
                    ("💬", "Catching up",      "Relaxed, conversational"),
                    ("🥐", "Coffee & food",    "Want a proper bite too")]
        case "Dessert":
            return [("🍦", "Ice cream",         "Scoops, gelato, soft serve"),
                    ("🍪", "Cookies & baked",   "Fresh, warm, out the oven"),
                    ("🎂", "Cake & fancy",       "Patisserie, plated dessert"),
                    ("🧋", "Boba & sweet drinks","Drinks that count as dessert")]
        case "Drinks":
            return [("🍹", "Cocktail bar",  "Craft, aesthetic, worth posting"),
                    ("🍷", "Wine bar",       "Natural wine, grazing, chill"),
                    ("🌇", "Rooftop",        "Views, outdoor, elevated"),
                    ("🍺", "Low key bar",    "Cheap, no pretense, chill")]
        default:
            return []
        }
    }

    // MARK: - Food Categories (new time-based flow)

    private func makeCat(_ key: String, emoji: String, title: String, subtitle: String) -> FoodCategoryOption {
        FoodCategoryOption(key: key, emoji: emoji, title: title, subtitle: subtitle,
                           isSurprise: false, isFullWidth: false, subOptions: foodSubOptions(for: key))
    }

    private func foodSubOptions(for key: String) -> [FoodSubOption] {
        switch key {
        case "Handheld":
            return [FoodSubOption(key: "Burger",    emoji: "🍔", label: "Burger"),
                    FoodSubOption(key: "Taco",      emoji: "🌮", label: "Taco"),
                    FoodSubOption(key: "Shawarma",  emoji: "🥙", label: "Shawarma"),
                    FoodSubOption(key: "Sandwich",  emoji: "🥪", label: "Sandwich")]
        case "Asian noodles & broth":
            return [FoodSubOption(key: "Ramen",  emoji: "🍜", label: "Ramen"),
                    FoodSubOption(key: "Pho",    emoji: "🍲", label: "Pho"),
                    FoodSubOption(key: "Udon",   emoji: "🥢", label: "Udon"),
                    FoodSubOption(key: "Laksa",  emoji: "🫕", label: "Laksa")]
        case "Italian & pizza":
            return [FoodSubOption(key: "Pizza",   emoji: "🍕", label: "Pizza"),
                    FoodSubOption(key: "Pasta",   emoji: "🍝", label: "Pasta"),
                    FoodSubOption(key: "Risotto", emoji: "🧆", label: "Risotto"),
                    FoodSubOption(key: "Italian", emoji: "🫙", label: "Italian")]
        case "Meaty":
            return [FoodSubOption(key: "Steak",      emoji: "🥩", label: "Steak"),
                    FoodSubOption(key: "BBQ",        emoji: "🍖", label: "BBQ"),
                    FoodSubOption(key: "Korean BBQ", emoji: "🥘", label: "Korean BBQ"),
                    FoodSubOption(key: "Kebab",      emoji: "🍢", label: "Kebab")]
        case "Bowls & stews":
            return [FoodSubOption(key: "Curry",     emoji: "🫕", label: "Curry"),
                    FoodSubOption(key: "Ethiopian", emoji: "🍛", label: "Ethiopian"),
                    FoodSubOption(key: "Tagine",    emoji: "🍲", label: "Tagine"),
                    FoodSubOption(key: "Bibimbap",  emoji: "🥗", label: "Bibimbap")]
        case "Fresh & light":
            return [FoodSubOption(key: "Sushi",      emoji: "🍣", label: "Sushi"),
                    FoodSubOption(key: "Poke",       emoji: "🥗", label: "Poke"),
                    FoodSubOption(key: "Ceviche",    emoji: "🍋", label: "Ceviche"),
                    FoodSubOption(key: "Vietnamese", emoji: "🌿", label: "Vietnamese")]
        case "Eggy & savory":
            return [FoodSubOption(key: "Eggs benny", emoji: "🍳", label: "Eggs benny"),
                    FoodSubOption(key: "Shakshuka",  emoji: "🥚", label: "Shakshuka"),
                    FoodSubOption(key: "Omelette",   emoji: "🧀", label: "Omelette"),
                    FoodSubOption(key: "Avo toast",  emoji: "🥑", label: "Avo toast")]
        case "Doughy & warm":
            return [FoodSubOption(key: "Pancakes",     emoji: "🥞", label: "Pancakes"),
                    FoodSubOption(key: "French toast", emoji: "🍞", label: "French toast"),
                    FoodSubOption(key: "Waffles",      emoji: "🧇", label: "Waffles"),
                    FoodSubOption(key: "Brioche",      emoji: "🥖", label: "Brioche")]
        case "Sweet & flaky":
            return [FoodSubOption(key: "Croissant", emoji: "🥐", label: "Croissant"),
                    FoodSubOption(key: "Pastry",    emoji: "🎂", label: "Pastry"),
                    FoodSubOption(key: "Danish",    emoji: "🥧", label: "Danish"),
                    FoodSubOption(key: "Donut",     emoji: "🍩", label: "Donut")]
        default:
            return []
        }
    }

    var foodCategoriesForOccasion: [FoodCategoryOption] {
        let surprise = FoodCategoryOption(key: "Surprise me", emoji: "✨", title: "Surprise me",
                                          subtitle: "Best near me, any style", isSurprise: true,
                                          isFullWidth: true, subOptions: [])

        switch selection.occasion {
        case "Casual":
            return [
                makeCat("Handheld",              emoji: "🌮", title: "Handheld",              subtitle: "Burgers, tacos, wraps"),
                makeCat("Asian noodles & broth", emoji: "🍜", title: "Asian noodles & broth", subtitle: "Ramen, pho, udon"),
                makeCat("Italian & pizza",       emoji: "🍕", title: "Italian & pizza",       subtitle: "Pasta, pizza, risotto"),
                makeCat("Meaty",                 emoji: "🥩", title: "Meaty",                 subtitle: "BBQ, grills, fried chicken"),
                makeCat("Bowls & stews",         emoji: "🍲", title: "Bowls & stews",         subtitle: "Curry, grain bowls, tagine"),
                makeCat("Fresh & light",         emoji: "🥗", title: "Fresh & light",         subtitle: "Sushi, poke, salads"),
                surprise
            ]
        case "Sit Down":
            return [
                makeCat("Italian & pizza",       emoji: "🍕", title: "Italian & pizza",       subtitle: "Pasta, pizza, risotto"),
                makeCat("Meaty",                 emoji: "🥩", title: "Meaty",                 subtitle: "Steakhouse, BBQ, chops"),
                makeCat("Bowls & stews",         emoji: "🍲", title: "Bowls & stews",         subtitle: "Curry, Ethiopian, tagine"),
                makeCat("Asian noodles & broth", emoji: "🍜", title: "Asian noodles & broth", subtitle: "Ramen, izakaya, Korean"),
                makeCat("Fresh & light",         emoji: "🥗", title: "Fresh & light",         subtitle: "Sushi, Mediterranean, salads"),
                makeCat("Handheld",              emoji: "🌮", title: "Handheld",              subtitle: "Tacos, burgers, sandwiches"),
                surprise
            ]
        case "No Rush":
            return [
                makeCat("Meaty",           emoji: "🥩", title: "Meaty",           subtitle: "Steak, omakase, BBQ"),
                makeCat("Italian & pizza", emoji: "🍕", title: "Italian & pizza", subtitle: "Pasta, pizza, trattoria"),
                makeCat("Bowls & stews",   emoji: "🍲", title: "Bowls & stews",   subtitle: "Slow-cooked, braised, saucy"),
                makeCat("Fresh & light",   emoji: "🥗", title: "Fresh & light",   subtitle: "Sushi, seafood, French"),
                makeCat("Handheld",        emoji: "🌮", title: "Handheld",        subtitle: "Upscale tacos, tartine"),
                surprise
            ]
        case "Brunch":
            return [
                makeCat("Eggy & savory", emoji: "🍳", title: "Eggy & savory", subtitle: "Eggs benny, shakshuka, omelette"),
                makeCat("Doughy & warm", emoji: "🥞", title: "Doughy & warm", subtitle: "Pancakes, french toast, waffles"),
                makeCat("Sweet & flaky", emoji: "🥐", title: "Sweet & flaky", subtitle: "Croissant, pastry, danish"),
                makeCat("Fresh & light", emoji: "🥗", title: "Fresh & light", subtitle: "Avocado toast, açaí, granola"),
                surprise
            ]
        case "Late Night":
            return [
                makeCat("Handheld",              emoji: "🌮", title: "Handheld",              subtitle: "Tacos, sliders, street food"),
                makeCat("Asian noodles & broth", emoji: "🍜", title: "Asian noodles & broth", subtitle: "Ramen, pho, late-night noodles"),
                makeCat("Italian & pizza",       emoji: "🍕", title: "Italian & pizza",       subtitle: "Late-night pizza, pasta"),
                makeCat("Meaty",                 emoji: "🥩", title: "Meaty",                 subtitle: "Fried chicken, BBQ, grills"),
                surprise
            ]
        default:
            return []
        }
    }

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
