//
//  HomeViewModel.swift
//  bilu
//

import Foundation
import Combine
import CoreLocation
import MapKit
import SwiftUI

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
    let imageURL: String?

    init(key: String, emoji: String, label: String, imageURL: String? = nil) {
        self.key = key
        self.emoji = emoji
        self.label = label
        self.imageURL = imageURL ?? FoodSubOption.defaultImageURL(for: key)
    }

    static func defaultImageURL(for key: String) -> String? {
        switch key {
        // Handheld
        case "Burger":        return "https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=900&auto=format&fit=crop&q=80"
        case "Taco":          return "https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=900&auto=format&fit=crop&q=80"
        case "Shawarma":      return "https://images.unsplash.com/photo-1599487488170-d11ec9c172f0?w=900&auto=format&fit=crop&q=80"
        case "Sandwich":      return "https://images.unsplash.com/photo-1528735602780-2552fd46c7af?w=900&auto=format&fit=crop&q=80"
        // Asian noodles & broth
        case "Ramen":         return "https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=900&auto=format&fit=crop&q=80"
        case "Pho":           return "https://images.unsplash.com/photo-1585032226651-759b368d7246?w=900&auto=format&fit=crop&q=80"
        case "Udon":          return "https://images.unsplash.com/photo-1591814468924-caf88d1232e1?w=900&auto=format&fit=crop&q=80"
        case "Laksa":         return "https://images.unsplash.com/photo-1626804475297-41608ea09aeb?w=900&auto=format&fit=crop&q=80"
        // Italian & pizza
        case "Pizza":         return "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=900&auto=format&fit=crop&q=80"
        case "Pasta":         return "https://images.unsplash.com/photo-1551183053-bf91a1d81141?w=900&auto=format&fit=crop&q=80"
        case "Risotto":       return "https://images.unsplash.com/photo-1633964913849-96bb09cfc0c6?w=900&auto=format&fit=crop&q=80"
        case "Italian":       return "https://images.unsplash.com/photo-1481931098730-318b6f776db0?w=900&auto=format&fit=crop&q=80"
        // Meaty
        case "Steak":         return "https://images.unsplash.com/photo-1546964124-0cce460f38ef?w=900&auto=format&fit=crop&q=80"
        case "BBQ":           return "https://images.unsplash.com/photo-1529193591184-b1d58069ecdd?w=900&auto=format&fit=crop&q=80"
        case "Korean BBQ":    return "https://images.unsplash.com/photo-1583224944844-5b268c057b72?w=900&auto=format&fit=crop&q=80"
        case "Kebab":         return "https://images.unsplash.com/photo-1599487488170-d11ec9c172f0?w=900&auto=format&fit=crop&q=80"
        // Bowls & stews
        case "Curry":         return "https://images.unsplash.com/photo-1455619452474-d2be8b1e70cd?w=900&auto=format&fit=crop&q=80"
        case "Ethiopian":     return "https://images.unsplash.com/photo-1567982047351-76b6f93e38ee?w=900&auto=format&fit=crop&q=80"
        case "Tagine":        return "https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?w=900&auto=format&fit=crop&q=80"
        case "Bibimbap":      return "https://images.unsplash.com/photo-1590301157890-4810ed352733?w=900&auto=format&fit=crop&q=80"
        // Fresh & light
        case "Sushi":         return "https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=900&auto=format&fit=crop&q=80"
        case "Poke":          return "https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=900&auto=format&fit=crop&q=80"
        case "Ceviche":       return "https://images.unsplash.com/photo-1559847844-5315695dadae?w=900&auto=format&fit=crop&q=80"
        case "Vietnamese":    return "https://images.unsplash.com/photo-1583224944844-5b268c057b72?w=900&auto=format&fit=crop&q=80"
        // Eggy & savory
        case "Eggs benny":    return "https://images.unsplash.com/photo-1608039829572-78524f79c4c7?w=900&auto=format&fit=crop&q=80"
        case "Shakshuka":     return "https://images.unsplash.com/photo-1590412200988-a436970781fa?w=900&auto=format&fit=crop&q=80"
        case "Omelette":      return "https://images.unsplash.com/photo-1510693206972-df098062cb71?w=900&auto=format&fit=crop&q=80"
        case "Avo toast":     return "https://images.unsplash.com/photo-1588137378633-dea1336ce1e2?w=900&auto=format&fit=crop&q=80"
        // Doughy & warm
        case "Pancakes":      return "https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=900&auto=format&fit=crop&q=80"
        case "French toast":  return "https://images.unsplash.com/photo-1484723091739-30a097e8f929?w=900&auto=format&fit=crop&q=80"
        case "Waffles":       return "https://images.unsplash.com/photo-1562376552-0d160a2f238d?w=900&auto=format&fit=crop&q=80"
        case "Brioche":       return "https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=900&auto=format&fit=crop&q=80"
        // Sweet & flaky
        case "Croissant":     return "https://images.unsplash.com/photo-1555507036-ab1f4038808a?w=900&auto=format&fit=crop&q=80"
        case "Pastry":        return "https://images.unsplash.com/photo-1509440159596-0249088772ff?w=900&auto=format&fit=crop&q=80"
        case "Danish":        return "https://images.unsplash.com/photo-1509365465985-25d11c17e812?w=900&auto=format&fit=crop&q=80"
        case "Donut":         return "https://images.unsplash.com/photo-1551024601-bec78aea704b?w=900&auto=format&fit=crop&q=80"
        default: return nil
        }
    }
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

/// Drives the staged reveal of recommendations: header → map → cards.
/// Comparable so views can gate content on `>= .headerIn` etc.
enum RevealPhase: Int, Comparable {
    case sealed, headerIn, mapIn, cardsIn
    static func < (a: RevealPhase, b: RevealPhase) -> Bool { a.rawValue < b.rawValue }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var step: Step = .occasion
    @Published var selection: VibeSelection
    @Published var recommendations: [Recommendation] = []
    /// "Trending Now" row on the Home screen — separate from `recommendations`
    /// so it survives independently of whatever the survey flow is doing.
    @Published var trendingRecommendations: [Recommendation] = []
    @Published var isLoadingTrending: Bool = false
    @Published var lastSearchFailure: SearchFailure? = nil
    @Published var lastSearchWasRelaxed: Bool = false
    @Published var isEnriching: Bool = false
    @Published var loadingPhase: String = "Scanning the streets\nfor your vibe..."
    @Published var detectedLocation: String = ""
    /// Drives the soft location pre-prompt card on the home screen.
    @Published var showLocationPrompt = false
    /// The user's resolved coordinate; nil until GPS resolves. The map widget adopts this once.
    @Published var initialMapCenter: CLLocationCoordinate2D? = nil
    private var didRequestLocation = false
    @Published var cuisineMode: CuisineMode = .vibe
    @Published var serviceCategory: String = "eat"
    @Published var selectedVibe: String = ""
    @Published var drinksSubType: String = ""
    @Published var tikTokVideos: [String: [TikTokVideo]] = [:]
    @Published var revealPhase: RevealPhase = .sealed
    /// Mirrors `@Environment(\.accessibilityReduceMotion)`; the View writes it on appear/change
    /// so the ViewModel can branch animation logic without touching UIKit accessibility directly.
    @Published var reduceMotionPreference: Bool = false
    /// Vibes the user has saved from the reveal screen. Mirrors the persisted
    /// SwiftData store (hydrated on `attach`); writes go through `savedStore`.
    @Published var savedVibes: [VibeSelection] = []

    /// The persistence seam, injected from HomeView's environment via `attach`.
    private weak var savedStore: SavedPlacesStore?

    /// Tracks the active search so it can be cancelled when the user exits mid-search.
    private var searchTask: Task<Void, Never>?

    static let newTimeOccasions: Set<String> = ["Casual", "Sit Down", "Brunch", "Late Night"]
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
        selection.dateNight = false
        selection.specialOccasion = false
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
            selectedVibe = defaultVibe(for: occasion)
            selection.selectedVibe = selectedVibe
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
        case "Sit Down":                                   return "full"
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
        drinksSubType = ""
        tikTokVideos = [:]
        revealPhase = .sealed
    }

    // MARK: - Saved Vibes

    /// Connects the persistence store and hydrates `savedVibes` so save-state
    /// survives launches. Called from HomeView.onAppear (idempotent).
    func attach(store: SavedPlacesStore) {
        savedStore = store
        savedVibes = store.savedVibeSelections()
    }

    /// Restore a saved vibe (from the Profile re-run flow) and kick the search.
    func restore(_ selection: VibeSelection) {
        self.selection = selection
        cuisineMode = selection.cuisineMode == "country" ? .country : .vibe
        selectedVibe = selection.selectedVibe
        searchTask = Task { await submitSurvey() }
    }

    /// True iff the current `selection` is already saved (matched on user-meaningful fields).
    var currentVibeIsSaved: Bool {
        savedVibes.contains { $0.matches(selection) }
    }

    /// Toggle save state for the current selection. Haptics live in the store.
    func toggleSaveCurrentVibe() {
        savedStore?.toggleVibe(selection)
        if let store = savedStore {
            savedVibes = store.savedVibeSelections()
        } else {
            // No store attached (e.g. previews) — keep the in-memory fallback.
            Haptics.medium()
            if let idx = savedVibes.firstIndex(where: { $0.matches(selection) }) {
                savedVibes.remove(at: idx)
            } else {
                savedVibes.append(selection)
                Haptics.success()
            }
        }
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

        lastSearchFailure = outcome.failure
        lastSearchWasRelaxed = outcome.result.relaxed ?? false

        let initial = outcome.result.recommendations
        let groundingPlaces = outcome.result.groundingPlaces ?? []
        let canEnrich = outcome.failure != .transportError && !initial.isEmpty

        // Short-circuit: empty results, transport error, or reduce-motion all
        // skip the wait+prefetch window and reveal immediately on Phase 1 data.
        if !canEnrich || reduceMotionPreference {
            recommendations = initial
            step = .reveal
            revealPhase = .sealed
            await stageReveal(reduceMotion: reduceMotionPreference)
            return
        }

        // Bridge phrase ("curated" appears in both states) so the loading→reveal
        // handoff doesn't flicker.
        loadingPhase = "Curating your\nperfect shortlist..."

        // Kick off the single shared enrichment task. We'll either await it (if it
        // beats the cap) or hand it off as a background fallback (if it doesn't).
        let enrichTask = Task<[Recommendation], Never> {
            await GeminiService.enrichRecommendations(
                initial,
                groundingPlaces: groundingPlaces,
                location: effectiveLocation
            )
        }

        let outcome2 = await raceEnrichmentAgainstCap(
            enrichTask: enrichTask,
            initial: initial
        )
        guard step == .loading else {
            enrichTask.cancel()
            return
        }

        recommendations = outcome2.recs
        step = .reveal
        revealPhase = .sealed

        if outcome2.isEnriched {
            // Synchronized happy path — everything in hand before reveal animates.
            isEnriching = false
            await stageReveal(reduceMotion: reduceMotionPreference)
        } else {
            // Cap fired before enrichment finished. Reveal now on Phase-1 data and
            // let enrichment land in the background — old behavior as a safety net.
            isEnriching = true
            Task { [weak self] in
                let enriched = await enrichTask.value
                guard let self else { return }
                await MainActor.run {
                    if self.step == .reveal && !enriched.isEmpty {
                        self.recommendations = enriched
                    }
                    self.isEnriching = false
                }
            }
            await stageReveal(reduceMotion: reduceMotionPreference)
        }
    }

    /// Holds on the loading screen while enrichment + image prefetch run, capped
    /// at `revealReadinessCapNanos` so a slow Places API can't strand the user.
    /// Returns the recs to reveal with and whether enrichment beat the cap.
    private static let revealReadinessCapNanos: UInt64 = 8_000_000_000  // 8s
    private static let prefetchTimeout: TimeInterval = 1.2

    private struct ReadinessOutcome {
        let recs: [Recommendation]
        let isEnriched: Bool
    }

    @MainActor
    private func raceEnrichmentAgainstCap(
        enrichTask: Task<[Recommendation], Never>,
        initial: [Recommendation]
    ) async -> ReadinessOutcome {
        let phase1URLs = initial.compactMap { $0.image.flatMap(URL.init(string:)) }

        // Warm Phase-1 image cache in parallel with the enrichment race.
        async let _ = ImagePrefetcher.warm(urls: phase1URLs, timeout: Self.prefetchTimeout)

        // Race the enrichment task against the cap timer.
        let enrichedOrNil: [Recommendation]? = await withTaskGroup(of: [Recommendation]?.self) { group in
            group.addTask {
                let recs = await enrichTask.value
                return recs.isEmpty ? nil : recs
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: Self.revealReadinessCapNanos)
                return nil  // sentinel: cap fired
            }
            let first = (await group.next()) ?? nil
            group.cancelAll()
            return first
        }

        guard let enriched = enrichedOrNil else {
            // Cap fired first. Don't cancel enrichTask — the caller hands it off
            // as a background write so the map and images still appear after reveal.
            return ReadinessOutcome(recs: initial, isEnriched: false)
        }

        // Enrichment beat the cap. Warm any new URLs briefly so the cards land hot.
        let enrichedURLs = enriched.compactMap { $0.image.flatMap(URL.init(string:)) }
        let newURLs = Set(enrichedURLs).subtracting(phase1URLs)
        if !newURLs.isEmpty {
            await ImagePrefetcher.warm(urls: Array(newURLs), timeout: 0.6)
        }
        return ReadinessOutcome(recs: enriched, isEnriched: true)
    }

    /// Drives the staged reveal of the recommendations screen.
    /// Three beats: header → map → cards, each with an escalating haptic.
    /// Short-circuits to a single `.cardsIn` jump (with one success haptic) when reduceMotion is on,
    /// or when results are empty (the staging beats only make sense when there's a list to reveal).
    private func stageReveal(reduceMotion: Bool) async {
        if reduceMotion || recommendations.isEmpty {
            Haptics.success()
            revealPhase = .cardsIn
            return
        }
        Haptics.success()
        withAnimation(AnimationProfile.stepTransition.animation(reduceMotion: false)) {
            revealPhase = .headerIn
        }
        try? await Task.sleep(nanoseconds: 280_000_000)
        guard step == .reveal else { return }
        Haptics.light()
        withAnimation(AnimationProfile.stepTransition.animation(reduceMotion: false)) {
            revealPhase = .mapIn
        }
        try? await Task.sleep(nanoseconds: 320_000_000)
        guard step == .reveal else { return }
        Haptics.rigid()
        withAnimation(AnimationProfile.listReveal.animation(reduceMotion: false)) {
            revealPhase = .cardsIn
        }
    }

    // MARK: - Trending Now

    private func trendingSelection() -> VibeSelection {
        var sel = VibeSelection()
        sel.occasion = "Casual"
        sel.foodFeelings = ["Surprise me"]
        sel.selectedVibe = "🔥 Trending"
        sel.location = effectiveLocation
        return sel
    }

    /// Loads the Home screen's "Trending Now" row once. Safe to call repeatedly —
    /// no-ops once populated or while already in flight.
    func loadTrendingIfNeeded() async {
        guard trendingRecommendations.isEmpty, !isLoadingTrending else { return }
        isLoadingTrending = true
        defer { isLoadingTrending = false }
        let outcome = await GeminiService.getVibeRecommendations(selection: trendingSelection())
        trendingRecommendations = Array(outcome.result.recommendations.prefix(6))
    }

    /// "View all" on the Trending Now row — runs the same search as the row itself
    /// through the normal loading → reveal flow so the user sees the full list.
    func viewAllTrending() {
        selection = trendingSelection()
        searchTask = Task { await submitSurvey() }
    }

    func fetchTikTokVideos(for rec: Recommendation) async -> [TikTokVideo] {
        if let cached = tikTokVideos[rec.id], !cached.isEmpty { return cached }
        let city = await cityForTikTok()
        let query = city.isEmpty ? rec.name : "\(rec.name) \(city)"
        let videos = await TikTokService.fetchVideos(query: query)
        tikTokVideos[rec.id] = videos
        return videos
    }

    // MARK: - Location

    /// Called once on home load. Shows the soft pre-prompt only when iOS permission is
    /// still .notDetermined; resolves silently when already granted, no-ops when denied.
    func primeLocationIfNeeded() async {
        guard !didRequestLocation else { return }
        switch LocationService.shared.authorizationStatus {
        case .notDetermined:
            showLocationPrompt = true
        case .authorizedWhenInUse, .authorizedAlways:
            await resolveCurrentLocation()
        default:
            if detectedLocation.isEmpty { detectedLocation = "Set your location" }
        }
    }

    /// Resolves the user's location and adopts it. Triggers the iOS dialog when the user
    /// taps "Use my location" on the pre-prompt; also used directly when already authorized.
    func resolveCurrentLocation() async {
        guard !didRequestLocation else { return }
        didRequestLocation = true
        showLocationPrompt = false
        do {
            let resolved = try await LocationService.shared.currentLocation()
            initialMapCenter = resolved.coordinate
            detectedLocation = resolved.cityLabel
            if selection.location.isEmpty { selection.location = resolved.cityLabel }
        } catch {
            // Denied or failed — don't imply a hard-coded city. Keep the label neutral
            // and leave selection.location empty so search treats it as unset.
            if detectedLocation.isEmpty { detectedLocation = "Set your location" }
        }
    }

    /// User tapped "Maybe later" — never fire the iOS dialog, keep the label neutral.
    func dismissLocationPrompt() {
        showLocationPrompt = false
        didRequestLocation = true
        if detectedLocation.isEmpty { detectedLocation = "Set your location" }
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

    func toggleDateNight() {
        selection.dateNight.toggle()
        if selection.dateNight { selection.specialOccasion = false }
    }

    func toggleSpecialOccasion() {
        selection.specialOccasion.toggle()
        if selection.specialOccasion { selection.dateNight = false }
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
