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
    /// Explore's entry: the feed plus the action button that opens the intent sheet.
    case feed
    case keyQuestion
    case foodFeeling
    case location
    case loading
    case reveal
}

/// The six intents in the action-button sheet. Every intent goes through the
/// same sheet and `HomeViewModel.applyIntent`; none skips a step the others get.
enum FeedIntent: String, CaseIterable, Identifiable {
    case cafe, food, drinks, lateNight, brunch, sweet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cafe:      return "Café to lock in"
        case .food:      return "Food"
        case .drinks:    return "Drinks"
        case .lateNight: return "Late night"
        case .brunch:    return "Brunch"
        case .sweet:     return "Something sweet"
        }
    }

    var systemImage: String {
        switch self {
        case .cafe:      return "cup.and.saucer.fill"
        case .food:      return "fork.knife"
        case .drinks:    return "wineglass.fill"
        case .lateNight: return "moon.stars.fill"
        case .brunch:    return "sun.horizon.fill"
        case .sweet:     return "birthday.cake.fill"
        }
    }

    var refinements: [IntentRefinement] {
        switch self {
        case .cafe:
            return [IntentRefinement("Work or study"), IntentRefinement("Great coffee"),
                    IntentRefinement("Catching up"), IntentRefinement("Coffee & food")]
        case .food:
            return [IntentRefinement("Quick bite", occasion: "Casual"),
                    IntentRefinement("Sit down", occasion: "Sit Down")]
        case .drinks:
            return [IntentRefinement("Cocktail bar"), IntentRefinement("Wine bar"),
                    IntentRefinement("Rooftop"), IntentRefinement("Low key bar")]
        case .lateNight, .brunch:
            return []
        case .sweet:
            return [IntentRefinement("Ice cream"), IntentRefinement("Cookies & baked"),
                    IntentRefinement("Cake & fancy"),
                    // The prompt table keys boba on the old sub-flow label.
                    IntentRefinement("Boba", answer: "Boba & sweet drinks"),
                    IntentRefinement("Fresh baked", occasion: "Bakery")]
        }
    }

    /// Pre-selected refinement, if any. Intents with refinements but no default
    /// need an explicit pick before "Find spots" enables.
    var defaultRefinement: IntentRefinement? {
        self == .cafe ? refinements.first : nil
    }

    /// "Late night" also works as a modifier on Drinks and Café.
    var supportsLateNight: Bool { self == .drinks || self == .cafe }

    /// True when the sheet submits the discovery directly; false when it hands
    /// off to the existing food-feeling step.
    var submitsDirectly: Bool {
        switch self {
        case .cafe, .drinks, .sweet:       return true
        case .food, .lateNight, .brunch:   return false
        }
    }
}

/// A refinement chip under an intent. `answer` becomes `keyQuestionAnswer`;
/// `occasion` overrides the intent's occasion (Food's Quick bite / Sit down,
/// Something sweet's Fresh baked).
struct IntentRefinement: Equatable, Hashable, Identifiable {
    let label: String
    let answer: String
    let occasion: String?

    var id: String { label }

    init(_ label: String, answer: String? = nil, occasion: String? = nil) {
        self.label = label
        self.answer = answer ?? label
        self.occasion = occasion
    }
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
    @Published var step: Step = .feed
    @Published var selection: VibeSelection
    @Published var recommendations: [Recommendation] = []
    @Published var showingRewardGate = false
    /// Explains a reopened reward gate when the backend rejected a reward the
    /// user just earned, so the gate never reappears without a reason.
    @Published private(set) var rewardGateNotice: String?
    @Published var showingPurchaseGate = false
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
    private var resolvedUserLocationLabel: String?
    private var didRequestLocation = false
    @Published var cuisineMode: CuisineMode = .vibe
    @Published var selectedVibe: String = ""
    /// Drives the intent sheet from the feed's action button and empty-state card.
    @Published var isShowingIntentSheet = false
    /// Explore's "Where to search" sheet, opened when a search has no area yet.
    @Published var isShowingLocationSheet = false
    /// Why the location sheet opened on its own; cleared when it closes.
    @Published private(set) var locationSheetNotice: String?
    /// Places resolved from shared TikToks, from the app root's
    /// `PendingSharesModel` (local results only; the feed never resolves).
    @Published private(set) var tikTokPlaces: [FeedTikTokPlace] = []
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
    private var enrichmentTask: Task<EnrichmentOutcome, Never>?
    /// The paid recommendations behind a "Couldn't load place details" card,
    /// kept so its retry re-runs only Places enrichment.
    private var retainedForPlaceDetails: RetainedRecommendations?
    private var activeDiscoveryID: UUID?
    private var latestDiscoveryID: UUID?
    private var isRewardUnlockPending = false
    private var surveySubmissionStep: Step = .foodFeeling
    let loadingAds: LoadingAdController
    private let allowance: DiscoveryAllowance
    private let commerceEnabled: () -> Bool
    private let fetchRecommendations: (VibeSelection, String?) async -> VibeFetchOutcome
    private let enrich: ([Recommendation], [GroundingPlace], String) async -> EnrichmentOutcome
    private let readinessTimeout: TimeInterval

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

    init(loadingAds: LoadingAdController? = nil,
         allowance: DiscoveryAllowance? = nil,
         commerceEnabled: (() -> Bool)? = nil,
         fetchRecommendations: ((VibeSelection, String?) async -> VibeFetchOutcome)? = nil,
         enrich: (([Recommendation], [GroundingPlace], String) async -> [Recommendation])? = nil,
         enrichPlaces: (([Recommendation], [GroundingPlace], String) async -> EnrichmentOutcome)? = nil,
         readinessTimeout: TimeInterval = 8) {
        self.selection = VibeSelection()
        #if DEBUG
        if fetchRecommendations == nil, let fixture = RecoveryFixture.current {
            // Deterministic UI-test seam: no provider calls, no ads, and a
            // throwaway allowance so the device's real discovery is never spent.
            self.loadingAds = LoadingAdController(frequency: LoadingAdFrequencyStore(defaults: fixture.defaults),
                eligible: { false }, record: { _, _, _, _, _, _, _, _ in }, observeEnvironment: false)
            self.allowance = fixture.allowance
            self.commerceEnabled = { false }
            self.fetchRecommendations = fixture.fetch
            self.enrich = fixture.enrich
            self.readinessTimeout = 0
            didRequestLocation = true
            reduceMotionPreference = true
            selection.occasion = "Bakery"
            selection.foodFeelings = ["Surprise me"]
            selection.location = "Los Angeles"
            searchTask = Task { [weak self] in await self?.submitSurvey() }
            return
        }
        #endif
        self.loadingAds = loadingAds ?? LoadingAdController()
        self.allowance = allowance ?? .shared
        self.commerceEnabled = commerceEnabled ?? { PurchaseConfiguration.current.commerceEnabled }
        self.fetchRecommendations = fetchRecommendations ?? {
            await GeminiService.getVibeRecommendations(selection: $0, rewardedAccessToken: $1)
        }
        if let enrichPlaces {
            self.enrich = enrichPlaces
        } else if let enrich {
            // Simple seam: a list is a Places answer with nothing unverified.
            self.enrich = { .verified(await enrich($0, $1, $2), unverifiedCount: 0) }
        } else {
            self.enrich = { await GeminiService.enrichRecommendations($0, groundingPlaces: $1, location: $2) }
        }
        self.readinessTimeout = max(0, readinessTimeout)
    }

    // MARK: - Navigation

    /// Builds the `VibeSelection` for an intent-sheet choice and moves on: Café,
    /// Drinks and Something sweet submit; Food, Late night and Brunch continue to
    /// the food-feeling step. "Late night" on Drinks or Café only sets
    /// `keyQuestionTimeWindow` (never `openNow`, which needs `fineTuneApplied`).
    func applyIntent(_ intent: FeedIntent, refinement: IntentRefinement?, lateNight: Bool) {
        // A direct-submit intent with no search area stays in the sheet (its
        // location chip and copy ask for one) rather than dismissing into a
        // search that `submitSurvey` would refuse anyway.
        if intent.submitsDirectly && !hasUsableLocation { return }
        cancelDiscovery()
        isShowingIntentSheet = false
        selection = Self.selection(for: intent, refinement: refinement, lateNight: lateNight, base: selection)
        cuisineMode = .vibe
        selectedVibe = selection.selectedVibe
        if intent.submitsDirectly {
            searchTask = Task { await submitSurvey() }
        } else {
            step = .foodFeeling
        }
    }

    /// The intent table. Starts from a clean survey but keeps the map's search
    /// area (radius, center, mode) from `base`.
    static func selection(for intent: FeedIntent, refinement: IntentRefinement?,
                          lateNight: Bool, base: VibeSelection = VibeSelection()) -> VibeSelection {
        var next = VibeSelection()
        next.radiusMiles = base.radiusMiles
        next.latitude = base.latitude
        next.longitude = base.longitude
        next.useRadiusSearch = base.useRadiusSearch
        let chip = refinement ?? intent.defaultRefinement
        switch intent {
        case .cafe:
            next.occasion = "Cafe"
            next.keyQuestionAnswer = chip?.answer ?? ""
            next.foodFeelings = ["Surprise me"]
        case .food:
            next.occasion = chip?.occasion ?? "Casual"
            next.selectedVibe = defaultVibe(for: next.occasion)
        case .drinks:
            next.occasion = "Drinks"
            next.keyQuestionAnswer = chip?.answer ?? ""
            next.foodFeelings = ["Surprise me"]
        case .lateNight:
            next.occasion = "Late Night"
            next.selectedVibe = defaultVibe(for: next.occasion)
        case .brunch:
            next.occasion = "Brunch"
            next.selectedVibe = defaultVibe(for: next.occasion)
        case .sweet:
            next.occasion = chip?.occasion ?? "Dessert"
            next.keyQuestionAnswer = chip?.answer ?? ""
            next.foodFeelings = ["Surprise me"]
        }
        if lateNight && intent.supportsLateNight {
            next.keyQuestionTimeWindow = lateNightTimeWindow
        }
        return next
    }

    static let lateNightTimeWindow = "Late night, after 10pm"

    func goBack() {
        searchTask?.cancel()
        switch step {
        case .keyQuestion:    step = .feed
        case .foodFeeling:
            if Self.newTimeOccasions.contains(selection.occasion) {
                step = .feed
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
            do { try await Task.sleep(nanoseconds: 260_000_000) } catch { return }
            await submitSurvey()
        }
    }

    func openFineTune() {
        selection.cuisineMode = cuisineMode == .country ? "country" : "vibe"
        step = .location
    }

    func proceedWithFineTune() {
        selection.fineTuneApplied = true
        // Never write the "your area" placeholder in as a place.
        if hasUsableLocation { selection.location = effectiveLocation }
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

    func cancelDiscovery() {
        loadingAds.finish(.cancelled)
        activeDiscoveryID = nil
        latestDiscoveryID = nil
        searchTask?.cancel()
        searchTask = nil
        enrichmentTask?.cancel()
        enrichmentTask = nil
        retainedForPlaceDetails = nil
        isEnriching = false
        if step == .loading { step = .foodFeeling }
    }

    func reset() {
        cancelDiscovery()
        step = .feed
        // A new journey keeps the search area the user set on the location chip.
        var fresh = VibeSelection()
        fresh.radiusMiles = selection.radiusMiles
        fresh.latitude = selection.latitude
        fresh.longitude = selection.longitude
        fresh.useRadiusSearch = selection.useRadiusSearch
        selection = fresh
        recommendations = []
        lastSearchFailure = nil
        lastSearchWasRelaxed = false
        isEnriching = false
        cuisineMode = .vibe
        selectedVibe = ""
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
    /// A re-run starts from the feed, so "Adjust" returns there, never to the
    /// previous journey's step. A vibe saved without a place keeps the search
    /// area the user has set now.
    func restore(_ selection: VibeSelection) {
        cancelDiscovery()
        var restored = selection
        if !Self.hasSearchArea(restored) {
            restored.location = self.selection.location
            restored.latitude = self.selection.latitude
            restored.longitude = self.selection.longitude
            restored.radiusMiles = self.selection.radiusMiles
            restored.useRadiusSearch = self.selection.useRadiusSearch
        }
        self.selection = restored
        cuisineMode = restored.cuisineMode == "country" ? .country : .vibe
        selectedVibe = restored.selectedVibe
        recommendations = []
        lastSearchFailure = nil
        revealPhase = .sealed
        step = .feed
        surveySubmissionStep = .feed
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

    var discoveryLoadingSummary: String {
        [selection.occasion, selection.foodFeelings.joined(separator: ", "),
         selection.pricePoints.joined(separator: " · "), effectiveLocation]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Survey Submit

    /// Records an earned reward; the discovery starts from `rewardGateDismissed`
    /// so a fast backend rejection can reopen the gate after it has fully closed.
    func rewardUnlocked() {
        isRewardUnlockPending = true
        rewardGateNotice = nil
    }

    /// Copy and action for the empty-results card.
    var searchRecovery: SearchRecoveryCopy { SearchRecoveryCopy(failure: lastSearchFailure) }

    func performRecoveryAction() async {
        switch searchRecovery.action {
        case .retry, .checkDiscovery:
            await submitSurvey()
        case .retryPlaceDetails:
            await retryPlaceDetails()
        case .viewDiscoveries:
            showingPurchaseGate = true
        case .unlockWithAd:
            rewardGateNotice = nil
            showingRewardGate = true
        case .adjustVibe:
            adjustVibe()
        case .startOver:
            reset()
        }
    }

    /// Returns to the step that submitted the search with every choice kept,
    /// so the user can widen or change it.
    func adjustVibe() {
        cancelDiscovery()
        recommendations = []
        lastSearchFailure = nil
        lastSearchWasRelaxed = false
        revealPhase = .sealed
        step = surveySubmissionStep
        // Searches started from the intent sheet adjust in the sheet.
        if step == .feed { isShowingIntentSheet = true }
    }

    func rewardGateDismissed() async {
        guard isRewardUnlockPending else { return }
        isRewardUnlockPending = false
        await submitSurvey()
    }

    func submitSurvey() async {
        guard !Task.isCancelled, activeDiscoveryID == nil else { return }
        // The single choke point for every journey (intent sheet, food step,
        // fine-tune, Run it back, retries): no real search area, no request,
        // no reward gate and no discovery spent. Ask for an area instead.
        guard hasUsableLocation else {
            requestSearchArea()
            return
        }
        guard commerceEnabled() || allowance.canRunDiscovery else {
            rewardGateNotice = nil
            showingRewardGate = true
            return
        }
        let rewardToken = allowance.remainingFreeDiscoveries > 0
            ? nil
            : allowance.rewardedAccessToken
        // A retry from the results card returns to the survey step that
        // started the search, never to a stale results screen.
        if step != .loading && step != .reveal { surveySubmissionStep = step }
        let submissionStep = surveySubmissionStep
        let id = UUID()
        enrichmentTask?.cancel()
        enrichmentTask = nil
        retainedForPlaceDetails = nil
        isEnriching = false
        activeDiscoveryID = id
        latestDiscoveryID = id
        step = .loading
        loadingAds.begin(id: id, allowAds: rewardToken == nil)
        let task = Task { await performDiscovery(id: id, rewardToken: rewardToken, submissionStep: submissionStep) }
        searchTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if activeDiscoveryID == id {
            if Task.isCancelled { cancelDiscovery() }
            activeDiscoveryID = nil
            searchTask = nil
        }
    }

    private func performDiscovery(id: UUID, rewardToken: String?, submissionStep: Step) async {
        guard !Task.isCancelled, activeDiscoveryID == id else { return }
        step = .loading
        lastSearchFailure = nil
        lastSearchWasRelaxed = false
        let messages = [
            "Finding your next\nfavorite spot...",
            "Matching places to\nyour cravings...",
            "Looking for your\nkind of atmosphere...",
            "Curating your\nperfect shortlist..."
        ]
        loadingPhase = messages[0]

        let ticker = Task {
            var idx = 0
            while activeDiscoveryID == id && step == .loading {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                idx = (idx + 1) % messages.count
                if activeDiscoveryID == id && step == .loading { loadingPhase = messages[idx] }
            }
        }
        defer { ticker.cancel() }

        // applyIntent starts each journey with an empty selection.location — restore
        // from the geocoded city name before building the prompt, but never send
        // the "Set your location" placeholder as a place.
        if selection.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           hasResolvedLocationLabel {
            selection.location = detectedLocation
        }

        // Phase 1: Gemini results — show cards immediately
        let outcome = await fetchRecommendations(selection, rewardToken)
        // If the user exited mid-search (reset/back), don't transition to results.
        guard !Task.isCancelled, activeDiscoveryID == id, step == .loading else { return }

        if outcome.failure == .purchaseRequired {
            loadingAds.finish(.failed)
            step = submissionStep
            showingPurchaseGate = true
            return
        }

        if outcome.failure == .rewardRequired {
            loadingAds.finish(.failed)
            allowance.reconcileRewardRequired()
            step = submissionStep
            rewardGateNotice = rewardToken == nil
                ? nil
                : "We couldn't verify your ad reward. Watch another ad to try again."
            showingRewardGate = true
            return
        }

        if !commerceEnabled() && (outcome.failure == nil || outcome.failure == .noMatches) {
            allowance.recordDiscovery(usedRewardToken: rewardToken)
        }

        lastSearchFailure = outcome.failure
        lastSearchWasRelaxed = outcome.result.relaxed ?? false

        let initial = outcome.result.recommendations
        let groundingPlaces = outcome.result.groundingPlaces ?? []
        let canEnrich = outcome.failure != .transportError && !initial.isEmpty

        if commerceEnabled() {
            // The wallet endpoint returns only final verified results and already
            // settled the allowance. Never enrich or debit them a second time.
            recommendations = initial.verifiedOpenRecommendations
            isEnriching = false
            loadingAds.finish(outcome.failure == nil || outcome.failure == .noMatches ? .completed : .failed)
            step = .reveal
            revealPhase = .sealed
            await stageReveal(id: id, reduceMotion: reduceMotionPreference)
            return
        }

        // Raw Gemini results do not contain a trustworthy live opening status.
        // Never reveal them before Places verification, including when Reduce
        // Motion is enabled.
        if !canEnrich {
            recommendations = []
            loadingAds.finish(outcome.failure == nil || outcome.failure == .noMatches ? .completed : .failed)
            step = .reveal
            revealPhase = .sealed
            await stageReveal(id: id, reduceMotion: reduceMotionPreference)
            return
        }

        // Bridge phrase ("curated" appears in both states) so the loading→reveal
        // handoff doesn't flicker.
        loadingPhase = "Curating your\nperfect shortlist..."

        // Kick off the single shared enrichment task. We'll either await it (if it
        // beats the cap) or hand it off as a background fallback (if it doesn't).
        let enrich = self.enrich
        let enrichmentLocation = effectiveLocation
        // The allowance is already spent for these results. Keep them so a
        // Places failure can be retried without another paid search.
        retainedForPlaceDetails = RetainedRecommendations(discoveryID: id, recommendations: initial,
            groundingPlaces: groundingPlaces, location: enrichmentLocation)
        let enrichTask = Task<EnrichmentOutcome, Never> {
            await enrich(initial, groundingPlaces, enrichmentLocation)
        }
        enrichmentTask = enrichTask

        let outcome2 = await withTaskCancellationHandler {
            await raceEnrichmentAgainstCap(enrichTask: enrichTask, initial: initial)
        } onCancel: {
            enrichTask.cancel()
        }
        guard !Task.isCancelled, activeDiscoveryID == id, step == .loading else {
            enrichTask.cancel()
            return
        }

        if let enrichment = outcome2.enrichment {
            recommendations = publish(enrichment)
        } else {
            recommendations = []
        }
        loadingAds.finish(.completed)
        step = .reveal
        revealPhase = .sealed

        if outcome2.enrichment != nil {
            // Synchronized happy path — everything in hand before reveal animates.
            enrichmentTask = nil
            isEnriching = false
            await stageReveal(id: id, reduceMotion: reduceMotionPreference)
        } else {
            // End loading at the cap, keeping unverified cards hidden while the
            // existing provider task finishes for this results screen.
            isEnriching = true
            Task { [weak self] in
                let enriched = await enrichTask.value
                guard !enrichTask.isCancelled, let self else { return }
                await MainActor.run {
                    guard self.latestDiscoveryID == id else { return }
                    self.enrichmentTask = nil
                    if self.step == .reveal {
                        self.recommendations = self.publish(enriched)
                    }
                    self.isEnriching = false
                }
            }
            await stageReveal(id: id, reduceMotion: reduceMotionPreference)
        }
    }

    /// Holds on the loading screen while enrichment + image prefetch run, capped
    /// at `readinessTimeout` so a slow Places API can't strand the user.
    /// Returns the recs to reveal with and whether enrichment beat the cap.
    private static let prefetchTimeout: TimeInterval = 1.2

    /// `nil` when the readiness cap fired before Places answered.
    private struct ReadinessOutcome {
        let enrichment: EnrichmentOutcome?
    }

    private struct RetainedRecommendations {
        let discoveryID: UUID
        let recommendations: [Recommendation]
        let groundingPlaces: [GroundingPlace]
        let location: String
    }

    private enum EnrichmentRaceResult {
        case finished(EnrichmentOutcome)
        case timedOut
        case cancelled
    }

    /// Main-actor serialization ensures exactly one observer resumes the waiter,
    /// including cancellation before its continuation has been installed.
    @MainActor
    private final class EnrichmentReadinessGate {
        private var result: EnrichmentRaceResult?
        private var continuation: CheckedContinuation<EnrichmentRaceResult, Never>?

        func value() async -> EnrichmentRaceResult {
            if let result { return result }
            return await withCheckedContinuation { continuation = $0 }
        }

        func resolve(_ result: EnrichmentRaceResult) {
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    @MainActor
    private func raceEnrichmentAgainstCap(
        enrichTask: Task<EnrichmentOutcome, Never>,
        initial: [Recommendation]
    ) async -> ReadinessOutcome {
        let phase1URLs = initial.compactMap { $0.image.flatMap(URL.init(string:)) }

        // Warm Phase-1 image cache in parallel with the enrichment race.
        async let _ = ImagePrefetcher.warm(urls: phase1URLs, timeout: Self.prefetchTimeout)

        // A task group waits for every child when leaving its scope, including
        // one awaiting this independent provider task. Resume on the first result
        // instead, so the readiness cap does not wait for the losing observer.
        let gate = EnrichmentReadinessGate()
        let observer = Task {
            let recs = await enrichTask.value
            guard !Task.isCancelled else { return }
            gate.resolve(.finished(recs))
        }
        let timer = Task {
            do { try await Task.sleep(for: .seconds(readinessTimeout)) } catch { return }
            gate.resolve(.timedOut)
        }
        defer {
            observer.cancel()
            timer.cancel()
        }
        let raceResult = await withTaskCancellationHandler {
            await gate.value()
        } onCancel: {
            enrichTask.cancel()
            Task { @MainActor in gate.resolve(.cancelled) }
        }

        guard case .finished(let enriched) = raceResult else {
            // Cap fired first. Don't cancel enrichTask — the caller hands it off
            // as a background write. Fail closed while status is unknown.
            return ReadinessOutcome(enrichment: nil)
        }

        // Enrichment beat the cap. Warm any new URLs briefly so the cards land hot.
        let enrichedRecs: [Recommendation]
        if case .verified(let recs, _) = enriched { enrichedRecs = recs } else { enrichedRecs = [] }
        let enrichedURLs = enrichedRecs.compactMap { $0.image.flatMap(URL.init(string:)) }
        let newURLs = Set(enrichedURLs).subtracting(phase1URLs)
        if !newURLs.isEmpty {
            await ImagePrefetcher.warm(urls: Array(newURLs), timeout: 0.6)
        }
        return ReadinessOutcome(enrichment: enriched)
    }

    /// Turns a Places answer into what the results screen shows. Confirmed
    /// places are always shown, even when others could not be confirmed. With
    /// none confirmed, an unconfirmed lookup is "Couldn't load place details"
    /// (retryable without a new search); only places Places confirmed closed
    /// read as "Nothing matched".
    private func publish(_ enrichment: EnrichmentOutcome) -> [Recommendation] {
        let verified: [Recommendation]
        let lookupFailed: Bool
        switch enrichment {
        case .verified(let recs, let unverifiedCount):
            verified = recs.verifiedOpenRecommendations
            lookupFailed = verified.isEmpty && unverifiedCount > 0
        case .unavailable:
            verified = []
            lookupFailed = true
        }
        lastSearchFailure = lookupFailed ? .placeDetailsUnavailable : nil
        if !lookupFailed { retainedForPlaceDetails = nil }
        return verified
    }

    /// Re-runs only Places enrichment for the results that are already paid
    /// for. Never calls the recommendations endpoint or touches the allowance.
    func retryPlaceDetails() async {
        guard let retained = retainedForPlaceDetails, !isEnriching, step == .reveal,
              latestDiscoveryID == retained.discoveryID else { return }
        lastSearchFailure = nil
        recommendations = []
        revealPhase = .sealed
        isEnriching = true
        let enrich = self.enrich
        let task = Task<EnrichmentOutcome, Never> {
            await enrich(retained.recommendations, retained.groundingPlaces, retained.location)
        }
        enrichmentTask = task
        let outcome = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard !task.isCancelled, latestDiscoveryID == retained.discoveryID, step == .reveal else { return }
        enrichmentTask = nil
        isEnriching = false
        recommendations = publish(outcome)
        await stageReveal(id: retained.discoveryID, reduceMotion: reduceMotionPreference)
    }

    /// Drives the staged reveal of the recommendations screen.
    /// Three beats: header → map → cards, each with an escalating haptic.
    /// Short-circuits to a single `.cardsIn` jump (with one success haptic) when reduceMotion is on,
    /// or when results are empty (the staging beats only make sense when there's a list to reveal).
    private func stageReveal(id: UUID, reduceMotion: Bool) async {
        guard !Task.isCancelled, latestDiscoveryID == id, step == .reveal else { return }
        if reduceMotion || recommendations.isEmpty {
            Haptics.success()
            revealPhase = .cardsIn
            return
        }
        Haptics.success()
        withAnimation(AnimationProfile.stepTransition.animation(reduceMotion: false)) {
            revealPhase = .headerIn
        }
        do { try await Task.sleep(nanoseconds: 280_000_000) } catch { return }
        guard !Task.isCancelled, latestDiscoveryID == id, step == .reveal else { return }
        Haptics.light()
        withAnimation(AnimationProfile.stepTransition.animation(reduceMotion: false)) {
            revealPhase = .mapIn
        }
        do { try await Task.sleep(nanoseconds: 320_000_000) } catch { return }
        guard !Task.isCancelled, latestDiscoveryID == id, step == .reveal else { return }
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

    /// There is no separate, allowance-free Trending endpoint. Opening Explore
    /// must not call /recommendations, which spends a UTC discovery server-side.
    /// An explicit "View all" continues through the normal allowance gate.
    func loadTrendingIfNeeded() async { }

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
        let videos = (try? await TikTokService.fetchVideos(query: query)) ?? []
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
            resolvedUserLocationLabel = resolved.cityLabel
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

    // MARK: - Feed

    static let unsetLocationLabel = "Set your location"
    /// Labels that only stand in for a place and must never be searched.
    static let placeholderLocations: Set<String> = ["your area", unsetLocationLabel]
    static let searchAreaRequiredNotice =
        "Choose where to search first: search for a place or drag the map, then try again. No discovery was used."

    /// True once GPS or the map has produced a real place name.
    var hasResolvedLocationLabel: Bool {
        !detectedLocation.isEmpty && detectedLocation != Self.unsetLocationLabel
    }

    /// True when a discovery has somewhere real to search.
    var hasUsableLocation: Bool {
        Self.hasSearchArea(selection) || hasResolvedLocationLabel
    }

    /// A typed or picked place, or a chosen map center.
    static func hasSearchArea(_ selection: VibeSelection) -> Bool {
        let typed = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!typed.isEmpty && !placeholderLocations.contains(typed))
            || (selection.latitude != nil && selection.longitude != nil)
    }

    /// Where the location sheet opens: the chosen center (either mode), else GPS.
    var searchAreaCenter: CLLocationCoordinate2D? {
        if let lat = selection.latitude, let lng = selection.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return initialMapCenter
    }

    /// The committed area's name for the sheet, or nil when there is none yet.
    var searchAreaLabel: String? {
        let typed = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty && !Self.placeholderLocations.contains(typed) { return typed }
        return hasResolvedLocationLabel ? detectedLocation : nil
    }

    // Writes from the location sheet. Only GPS, a picked place or a pan reach
    // these; the map's placeholder region never does.

    func chooseSearchCenter(_ coordinate: CLLocationCoordinate2D) {
        selection.latitude = coordinate.latitude
        selection.longitude = coordinate.longitude
    }

    func commitSearchAreaLabel(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        detectedLocation = trimmed
        selection.location = trimmed
    }

    func setSearchRadius(_ miles: Double, center: CLLocationCoordinate2D) {
        selection.radiusMiles = miles
        chooseSearchCenter(center)
        selection.useRadiusSearch = true
    }

    func setRadiusMode(_ isRadiusMode: Bool) {
        selection.useRadiusSearch = isRadiusMode
    }

    /// Opens the location sheet with copy explaining why. No request is made.
    func requestSearchArea() {
        isShowingIntentSheet = false
        locationSheetNotice = Self.searchAreaRequiredNotice
        isShowingLocationSheet = true
    }

    func locationSheetDismissed() {
        locationSheetNotice = nil
    }

    /// The location chip: "Near you · 2 mi" in radius mode, else the city name.
    var locationChipLabel: String {
        if selection.useRadiusSearch && selection.latitude != nil && selection.longitude != nil {
            return "Near you · \(Self.formattedMiles(selection.radiusMiles))"
        }
        let typed = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return hasResolvedLocationLabel ? detectedLocation : "Set location"
    }

    static func formattedMiles(_ miles: Double) -> String {
        let rounded = (miles * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) mi"
            : String(format: "%.1f mi", rounded)
    }

    /// The allowance line shown wherever a tap spends a discovery (the intent
    /// sheet and Run it back). Nil when purchases replace the free allowance.
    var discoveryAllowanceStatus: String? {
        guard !commerceEnabled() else { return nil }
        let remaining = allowance.remainingFreeDiscoveries
        if remaining > 0 { return "\(remaining) free today" }
        return allowance.hasRewardedDiscovery ? "1 unlocked with an ad" : "Watch an ad for another"
    }

    /// Where "near you" is measured from: the map's pin in radius mode, else GPS.
    var feedOrigin: CLLocationCoordinate2D? {
        if selection.useRadiusSearch, let lat = selection.latitude, let lng = selection.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        return initialMapCenter
    }

    /// Shows the places resolved from shared TikToks. No network.
    func showSharedPlaces(from shares: [PendingTikTokShare]) {
        let places = FeedTikTokPlace.from(shares)
        if places != tikTokPlaces { tikTokPlaces = places }
    }

    /// Up to `limit` Want to Go places, nearest first when a location is known;
    /// places without coordinates (or with no origin) follow, newest first.
    static func nearestWantToGo(_ places: [SavedPlace], from origin: CLLocationCoordinate2D?,
                                limit: Int = 6) -> [SavedPlace] {
        let wantToGo = places.filter { $0.listType == .wantToGo }
        let originLocation = origin.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        func distance(_ place: SavedPlace) -> CLLocationDistance? {
            guard let originLocation, let lat = place.latitude, let lng = place.longitude else { return nil }
            return originLocation.distance(from: CLLocation(latitude: lat, longitude: lng))
        }
        let sorted = wantToGo.sorted { lhs, rhs in
            switch (distance(lhs), distance(rhs)) {
            case let (l?, r?): return l < r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.dateSaved > rhs.dateSaved
            }
        }
        return Array(sorted.prefix(limit))
    }

    /// Miles from `origin` to a coordinate, for the feed cards.
    static func milesLabel(from origin: CLLocationCoordinate2D?, latitude: Double?, longitude: Double?) -> String? {
        guard let origin, let latitude, let longitude else { return nil }
        let meters = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: latitude, longitude: longitude))
        return String(format: "%.1f mi", meters / 1609.34)
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
        if !typed.isEmpty && !Self.placeholderLocations.contains(typed) {
            let parts = typed.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2 {
                // Drop the first part (neighborhood/street) and rejoin the rest
                return parts.dropFirst().joined(separator: ", ")
            }
            return typed
        }

        // 3. detectedLocation (set by the map widget) — same strip logic
        // Never send the "Set your location" placeholder as a city: a paid
        // TikTok search for it can only miss.
        if !detectedLocation.isEmpty && !Self.placeholderLocations.contains(detectedLocation) {
            let parts = detectedLocation.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2 { return parts.dropFirst().joined(separator: ", ") }
            return detectedLocation
        }

        return ""
    }

    var effectiveLocation: String {
        let loc = selection.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !loc.isEmpty { return loc }
        if hasResolvedLocationLabel { return detectedLocation }
        if let lat = selection.latitude, let lng = selection.longitude {
            return String(format: "%.4f° N, %.4f° W", lat, abs(lng))
        }
        return "your area"
    }

    // MARK: - Progress

    var progressStepIndex: Int? {
        switch step {
        case .feed:                  return nil
        case .keyQuestion:           return 1
        case .foodFeeling:
            // New time-based occasions skip keyQuestion — don't show a misleading step count
            if Self.newTimeOccasions.contains(selection.occasion) { return nil }
            return 2
        case .location:              return 3
        case .loading, .reveal:      return nil
        }
    }

    // MARK: - Vibe (new time-based flow)

    static func defaultVibe(for occasion: String) -> String {
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

/// A place from a shared TikTok, as the feed shows it. Built from the share
/// records B1b stores after resolving, so the feed never resolves anything.
struct FeedTikTokPlace: Identifiable, Equatable {
    let place: ResolvedSharePlace
    let caption: String?

    var id: String { place.placeId }
    var recommendation: Recommendation { place.recommendation(caption: caption) }

    /// Flattens resolved shares (newest first), one entry per Places id.
    static func from(_ shares: [PendingTikTokShare]) -> [FeedTikTokPlace] {
        var seen = Set<String>()
        var result: [FeedTikTokPlace] = []
        for share in shares.sorted(by: { $0.dateAdded > $1.dateAdded }) {
            guard case let .resolved(video, places) = share.resolution else { continue }
            for place in places where seen.insert(place.placeId).inserted {
                result.append(FeedTikTokPlace(place: place, caption: video.caption))
            }
        }
        return result
    }
}

#if DEBUG
/// `BILU_UI_TEST_RECOVERY=<scenario>` starts Explore on a fixture search whose
/// first response fails with that scenario and whose retry succeeds. It is not
/// compiled into Release builds.
@MainActor
final class RecoveryFixture {
    static let current: RecoveryFixture? = {
        guard let raw = ProcessInfo.processInfo.environment["BILU_UI_TEST_RECOVERY"],
              let failure = failure(named: raw) else { return nil }
        return RecoveryFixture(failure: failure)
    }()

    static func failure(named name: String) -> SearchFailure? {
        switch name {
        case "noMatches": return .noMatches
        case "timedOut": return .timedOut
        case "capacity": return .capacityUnavailable
        case "offline": return .offline
        case "usageLimit": return .usageLimitExceeded
        case "sessionRejected": return .sessionRejected
        case "transport": return .transportError
        case "rewardRejected": return .rewardRequired
        case "placeDetails": return .placeDetailsUnavailable
        default: return nil
        }
    }

    let defaults: UserDefaults
    let allowance: DiscoveryAllowance
    private let failure: SearchFailure
    private var calls = 0
    private var enrichCalls = 0

    private init(failure: SearchFailure) {
        self.failure = failure
        defaults = UserDefaults(suiteName: "RecoveryFixture.\(UUID().uuidString)") ?? .standard
        allowance = DiscoveryAllowance(defaults: defaults)
        if failure == .rewardRequired {
            allowance.recordDiscovery(usedRewardToken: nil)
            allowance.grantReward(token: "fixture-unverified-reward")
        }
    }

    func fetch(_ selection: VibeSelection, _ token: String?) async -> VibeFetchOutcome {
        calls += 1
        try? await Task.sleep(for: .milliseconds(300))
        let empty = VibeResult(recommendations: [], groundingPlaces: [], relaxed: nil)
        // placeDetails fails in enrichment instead, so the search itself succeeds.
        if calls == 1 && failure != .placeDetailsUnavailable {
            return VibeFetchOutcome(result: empty, failure: failure)
        }
        let place = Recommendation(name: "Recovered Bakery", dish: "Croissant", image: nil,
            explanation: "Fixture result after retry", mapsUrl: "", latitude: nil, longitude: nil,
            rating: nil, reviewCount: nil, isOpen: true, photos: nil, address: nil, phone: nil,
            website: nil, parking: "Not confirmed", placeId: "fixture-recovered", photoRefs: nil, reviews: nil)
        return VibeFetchOutcome(result: VibeResult(recommendations: [place], groundingPlaces: [], relaxed: false), failure: nil)
    }

    /// Places is unavailable once for the placeDetails scenario, then confirms.
    func enrich(_ recommendations: [Recommendation], _ groundingPlaces: [GroundingPlace],
                _ location: String) async -> EnrichmentOutcome {
        enrichCalls += 1
        if failure == .placeDetailsUnavailable && enrichCalls == 1 { return .unavailable }
        return .verified(recommendations, unverifiedCount: 0)
    }
}
#endif

#if DEBUG
extension HomeViewModel {
    /// Launch with `-FeedFixture YES` to seed Want to Go places and a saved vibe
    /// into the local store, centred on Los Angeles, for feed screenshots. No
    /// network, no discovery. Seeding is idempotent (places are keyed by id).
    static var feedFixtureRequested: Bool {
        UserDefaults.standard.bool(forKey: "FeedFixture")
    }

    func seedFeedFixtureIfRequested(store: SavedPlacesStore) {
        guard Self.feedFixtureRequested else { return }
        didRequestLocation = true
        showLocationPrompt = false
        initialMapCenter = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        detectedLocation = "Los Angeles"
        let places: [(String, String, String, Double, Double, [String])] = [
            ("fixture-tsujita", "Tsujita LA Artisan Noodle", "2057 Sawtelle Blvd, Los Angeles, CA", 34.0395, -118.4425, ["Ramen"]),
            ("fixture-bestia", "Bestia", "2121 E 7th Pl, Los Angeles, CA", 34.0336, -118.2292, ["Italian & pizza"]),
            ("fixture-grandcentral", "Grand Central Market", "317 S Broadway, Los Angeles, CA", 34.0508, -118.2489, [])
        ]
        for (id, name, address, lat, lng, tags) in places {
            let rec = Recommendation(name: name, dish: "", image: nil, explanation: "Fixture place",
                mapsUrl: "", latitude: lat, longitude: lng, rating: 4.6, reviewCount: nil, isOpen: nil,
                photos: nil, address: address, phone: nil, website: nil, parking: nil, placeId: id,
                photoRefs: nil, reviews: nil)
            store.add(rec, list: .wantToGo, tags: tags)
        }
        let vibe = VibeSelection(occasion: "Late Night", foodFeelings: ["Handheld"], location: "Los Angeles",
                                 selectedVibe: "🔥 Trending")
        if !store.isVibeSaved(vibe) { store.toggleVibe(vibe) }
        savedVibes = store.savedVibeSelections()
    }
}
#endif
