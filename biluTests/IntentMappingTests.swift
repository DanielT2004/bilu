import CoreLocation
import Foundation
import XCTest
@testable import bilu

/// The intent sheet's table (build/feedback-redesign/d3a/PLAN.md §2): one test
/// per row, plus Drinks + Late night. Each test drives `applyIntent` on a real
/// HomeViewModel with an injected fetcher, so no provider is ever called.
@MainActor
final class IntentMappingTests: XCTestCase {
    private let suite = "IntentMappingTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!
    private var allowance: DiscoveryAllowance!
    private var fetcher: RecordingFetcher!

    override func setUp() async throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        allowance = DiscoveryAllowance(defaults: defaults)
        fetcher = RecordingFetcher()
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        allowance = nil
        fetcher = nil
    }

    // MARK: - One test per table row

    func testCafeSubmitsWithDefaultWorkOrStudy() async throws {
        let model = home()
        model.applyIntent(.cafe, refinement: nil, lateNight: false)
        let sent = try await submitted()
        XCTAssertEqual(sent.occasion, "Cafe")
        XCTAssertEqual(sent.keyQuestionAnswer, "Work or study")
        XCTAssertEqual(sent.foodFeelings, ["Surprise me"])
        XCTAssertNil(sent.keyQuestionTimeWindow)
        XCTAssertEqual(FeedIntent.cafe.refinements.map(\.label),
                       ["Work or study", "Great coffee", "Catching up", "Coffee & food"])
    }

    func testFoodQuickBiteAndSitDownContinueToFoodFeelingStep() {
        let model = home()
        model.applyIntent(.food, refinement: refinement(.food, "Quick bite"), lateNight: false)
        XCTAssertEqual(model.step, .foodFeeling)
        XCTAssertEqual(model.selection.occasion, "Casual")
        XCTAssertEqual(model.selection.selectedVibe, HomeViewModel.defaultVibe(for: "Casual"))
        XCTAssertEqual(model.selectedVibe, "🔥 Trending")

        model.applyIntent(.food, refinement: refinement(.food, "Sit down"), lateNight: false)
        XCTAssertEqual(model.step, .foodFeeling)
        XCTAssertEqual(model.selection.occasion, "Sit Down")
        XCTAssertEqual(model.selection.selectedVibe, "⭐ Best rated")
        XCTAssertTrue(model.selection.foodFeelings.isEmpty, "The food step asks for the feeling")
        XCTAssertTrue(fetcher.selections.isEmpty, "Food never submits from the sheet")
    }

    func testDrinksSubmitsWithChosenBar() async throws {
        let model = home()
        model.applyIntent(.drinks, refinement: refinement(.drinks, "Wine bar"), lateNight: false)
        let sent = try await submitted()
        XCTAssertEqual(sent.occasion, "Drinks")
        XCTAssertEqual(sent.keyQuestionAnswer, "Wine bar")
        XCTAssertEqual(sent.foodFeelings, ["Surprise me"])
        XCTAssertNil(sent.keyQuestionTimeWindow)
        XCTAssertEqual(FeedIntent.drinks.refinements.map(\.label),
                       ["Cocktail bar", "Wine bar", "Rooftop", "Low key bar"])
    }

    func testLateNightContinuesToFoodFeelingWithTrending() {
        let model = home()
        model.applyIntent(.lateNight, refinement: nil, lateNight: false)
        XCTAssertEqual(model.step, .foodFeeling)
        XCTAssertEqual(model.selection.occasion, "Late Night")
        XCTAssertEqual(model.selection.selectedVibe, "🔥 Trending")
        XCTAssertNil(model.selection.keyQuestionTimeWindow)
        XCTAssertTrue(fetcher.selections.isEmpty)
    }

    func testBrunchContinuesToFoodFeelingWithBestRated() {
        let model = home()
        model.applyIntent(.brunch, refinement: nil, lateNight: false)
        XCTAssertEqual(model.step, .foodFeeling)
        XCTAssertEqual(model.selection.occasion, "Brunch")
        XCTAssertEqual(model.selection.selectedVibe, "⭐ Best rated")
        XCTAssertTrue(fetcher.selections.isEmpty)
    }

    func testSomethingSweetSubmitsDessertAndFreshBakedSubmitsBakery() async throws {
        let model = home()
        model.applyIntent(.sweet, refinement: refinement(.sweet, "Ice cream"), lateNight: false)
        let dessert = try await submitted()
        XCTAssertEqual(dessert.occasion, "Dessert")
        XCTAssertEqual(dessert.keyQuestionAnswer, "Ice cream")
        XCTAssertEqual(dessert.foodFeelings, ["Surprise me"])

        // Fresh baked goes through the same sheet and the same submit as the rest.
        model.reset()
        model.applyIntent(.sweet, refinement: refinement(.sweet, "Fresh baked"), lateNight: false)
        let bakery = try await submitted(count: 2)
        XCTAssertEqual(bakery.occasion, "Bakery")
        XCTAssertEqual(bakery.keyQuestionAnswer, "Fresh baked")
        XCTAssertEqual(bakery.foodFeelings, ["Surprise me"])

        // Boba keeps the prompt key the old sub-flow used.
        XCTAssertEqual(refinement(.sweet, "Boba").answer, "Boba & sweet drinks")
    }

    // MARK: - Combining

    func testDrinksPlusLateNightSetsOnlyTheTimeWindow() async throws {
        let model = home()
        model.applyIntent(.drinks, refinement: refinement(.drinks, "Cocktail bar"), lateNight: true)
        let sent = try await submitted()
        XCTAssertEqual(sent.occasion, "Drinks")
        XCTAssertEqual(sent.keyQuestionAnswer, "Cocktail bar")
        XCTAssertEqual(sent.keyQuestionTimeWindow, "Late night, after 10pm")
        XCTAssertFalse(sent.openNow, "openNow is only read with fineTuneApplied")
        XCTAssertFalse(sent.fineTuneApplied, "Fine-tune would add a default price constraint")
        XCTAssertTrue(PromptBuilder.getPrompt(selection: sent).contains("Time preference: Late night, after 10pm."))
    }

    func testLateNightModifierOnlyAppliesToDrinksAndCafe() {
        XCTAssertEqual(FeedIntent.allCases.filter(\.supportsLateNight), [.cafe, .drinks])
        let food = HomeViewModel.selection(for: .food, refinement: nil, lateNight: true)
        XCTAssertNil(food.keyQuestionTimeWindow)
        let cafe = HomeViewModel.selection(for: .cafe, refinement: nil, lateNight: true)
        XCTAssertEqual(cafe.keyQuestionTimeWindow, HomeViewModel.lateNightTimeWindow)
    }

    // MARK: - Flow guarantees

    func testIntentKeepsTheSearchAreaFromTheLocationChip() {
        let model = home()
        model.selection.useRadiusSearch = true
        model.selection.radiusMiles = 5
        model.selection.latitude = 34.05
        model.selection.longitude = -118.24
        model.applyIntent(.brunch, refinement: nil, lateNight: false)
        XCTAssertTrue(model.selection.useRadiusSearch)
        XCTAssertEqual(model.selection.radiusMiles, 5)
        XCTAssertEqual(model.selection.latitude, 34.05)
        XCTAssertEqual(model.locationChipLabel, "Near you · 5 mi")
    }

    func testLegacySavedVibeReRunsThroughSubmitSurveyUnchanged() async throws {
        let model = home()
        let legacy = VibeSelection(occasion: "Date Night", keyQuestionAnswer: "Tonight",
                                   foodFeelings: ["Fresh & crisp"], location: "Pasadena",
                                   pricePoints: ["$$$"], fineTuneApplied: true)
        model.restore(legacy)
        let sent = try await submitted()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(sent), try encoder.encode(legacy))
    }

    func testBackFromFoodStepReturnsToFeedAndExploreStartsOnFeed() {
        let model = home()
        XCTAssertEqual(model.step, .feed)
        model.applyIntent(.food, refinement: refinement(.food, "Quick bite"), lateNight: false)
        model.goBack()
        XCTAssertEqual(model.step, .feed)
    }

    func testOpeningTheFeedMakesNoDiscoveryCalls() async {
        let share = PendingTikTokShare(id: "a", urlString: "https://www.tiktok.com/t/a", dateAdded: .now,
            resolution: .resolved(video: ResolvedShareVideo(videoId: "1", caption: "Tacos", canonicalUrl: "",
                                                            authorName: nil, thumbnailUrl: nil),
                                  places: [ResolvedSharePlace(placeId: "p1", name: "Sonoratown", address: "DTLA",
                                                              latitude: 34.04, longitude: -118.25)]))
        let model = home()
        model.showSharedPlaces(from: [share])
        await Task.yield()
        XCTAssertEqual(model.tikTokPlaces.map(\.place.name), ["Sonoratown"])
        XCTAssertTrue(fetcher.selections.isEmpty)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
        XCTAssertEqual(model.discoveryAllowanceStatus, "1 free today")
    }

    func testTikTokPlacesSkipUnresolvedSharesAndDuplicates() {
        let video = ResolvedShareVideo(videoId: "1", caption: "", canonicalUrl: "", authorName: nil, thumbnailUrl: nil)
        let place = ResolvedSharePlace(placeId: "p1", name: "Sonoratown", address: "", latitude: 0, longitude: 0)
        let shares = [
            PendingTikTokShare(id: "a", urlString: "", dateAdded: .now, resolution: .resolved(video: video, places: [place])),
            PendingTikTokShare(id: "b", urlString: "", dateAdded: .now.addingTimeInterval(-60),
                               resolution: .resolved(video: video, places: [place])),
            PendingTikTokShare(id: "c", urlString: "", dateAdded: .now, resolution: .needsCity),
            PendingTikTokShare(id: "d", urlString: "", dateAdded: .now, resolution: .pending)
        ]
        XCTAssertEqual(FeedTikTokPlace.from(shares).map(\.id), ["p1"])
    }

    func testWantToGoNearYouIsNearestFirstAndCappedAtSix() {
        func place(_ id: String, _ lat: Double?, list: SavedListType = .wantToGo) -> SavedPlace {
            SavedPlace(from: Recommendation(name: id, dish: "", image: nil, explanation: "", mapsUrl: "",
                latitude: lat, longitude: lat == nil ? nil : -118.24, rating: nil, reviewCount: nil, isOpen: nil,
                photos: nil, address: nil, phone: nil, website: nil, parking: nil, placeId: id, photoRefs: nil,
                reviews: nil), listType: list)
        }
        let origin = CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24)
        let places = [place("far", 34.50), place("near", 34.06), place("saved", 34.05, list: .saved),
                      place("noCoords", nil)] + (1...6).map { place("mid\($0)", 34.1 + Double($0) / 100) }
        let result = HomeViewModel.nearestWantToGo(places, from: origin)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.first?.name, "near")
        XCTAssertFalse(result.contains { $0.name == "saved" }, "Only Want to Go")
        XCTAssertFalse(result.contains { $0.name == "far" || $0.name == "noCoords" })
    }

    // MARK: - Every refinement reaches the prompt (P2-1)

    func testEveryRefinementAnswerHasPromptText() {
        for intent in FeedIntent.allCases {
            for chip in intent.refinements {
                let selection = HomeViewModel.selection(for: intent, refinement: chip, lateNight: false)
                // Food's chips pick an occasion instead of an answer.
                if selection.keyQuestionAnswer.isEmpty {
                    XCTAssertNotNil(chip.occasion, "\(intent) / \(chip.label) changes nothing")
                    XCTAssertNotNil(PromptConstants.occasionPrompts[selection.occasion], "\(chip.label)")
                    continue
                }
                guard let text = PromptConstants.keyQuestionPrompts[selection.keyQuestionAnswer] else {
                    XCTFail("\(intent) / \(chip.label) has no prompt text for \(selection.keyQuestionAnswer)")
                    continue
                }
                XCTAssertTrue(PromptBuilder.getPrompt(selection: selection).contains(text), "\(chip.label)")
            }
        }
    }

    func testFreshBakedPromptAsksForAMorningBake() {
        let selection = HomeViewModel.selection(for: .sweet, refinement: refinement(.sweet, "Fresh baked"),
                                                lateNight: false)
        let prompt = PromptBuilder.getPrompt(selection: selection)
        XCTAssertTrue(prompt.contains("The user wants a great bakery."))
        XCTAssertTrue(prompt.contains("bread, croissants and pastries"))
        XCTAssertTrue(prompt.contains("morning bake"))
    }

    // MARK: - No search area, no discovery (P1-1)

    func testDirectIntentsWithoutAnAreaStayInTheSheetAndSpendNothing() async {
        for intent in FeedIntent.allCases where intent.submitsDirectly {
            let model = home(withArea: false)
            model.isShowingIntentSheet = true
            model.applyIntent(intent, refinement: intent.refinements.first, lateNight: false)
            for _ in 0..<50 { await Task.yield() }
            XCTAssertTrue(model.isShowingIntentSheet, "\(intent) keeps the sheet open to set an area")
            XCTAssertEqual(model.step, .feed, "\(intent)")
        }
        XCTAssertTrue(fetcher.selections.isEmpty)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
    }

    func testFoodStepIntentsWithoutAnAreaAskForOneInsteadOfSearching() async throws {
        for intent in FeedIntent.allCases where !intent.submitsDirectly {
            let model = home(withArea: false)
            model.applyIntent(intent, refinement: intent.refinements.first, lateNight: false)
            XCTAssertEqual(model.step, .foodFeeling, "\(intent)")
            model.selectFoodFeeling("Surprise me")
            model.continueFromFoodFeeling()
            try await eventually { model.isShowingLocationSheet }
            XCTAssertEqual(model.locationSheetNotice, HomeViewModel.searchAreaRequiredNotice)
            XCTAssertEqual(model.step, .foodFeeling, "\(intent) keeps the user's choices")
            XCTAssertFalse(model.showingRewardGate, "no reward gate for a search that can't run")
            model.locationSheetDismissed()
            XCTAssertNil(model.locationSheetNotice)
        }
        XCTAssertTrue(fetcher.selections.isEmpty)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
    }

    func testFineTuneWithoutAnAreaNeverSendsYourArea() async throws {
        let model = home(withArea: false)
        model.applyIntent(.food, refinement: refinement(.food, "Sit down"), lateNight: false)
        model.selectFoodFeeling("Surprise me")
        model.openFineTune()
        model.proceedWithFineTune()
        try await eventually { model.isShowingLocationSheet }
        XCTAssertEqual(model.selection.location, "")
        XCTAssertTrue(fetcher.selections.isEmpty)
    }

    func testUnsetLocationPlaceholderIsNotASearchArea() async {
        let model = home(withArea: false)
        model.detectedLocation = HomeViewModel.unsetLocationLabel
        XCTAssertFalse(model.hasUsableLocation)
        XCTAssertEqual(model.effectiveLocation, "your area", "never the placeholder text")
        await model.submitSurvey()
        XCTAssertTrue(model.isShowingLocationSheet)
        XCTAssertTrue(fetcher.selections.isEmpty)
    }

    func testLegacySavedVibeWithoutAPlaceAsksForAnAreaThenUsesIt() async throws {
        let model = home(withArea: false)
        let legacy = VibeSelection(occasion: "Late Night", foodFeelings: ["Handheld"], location: "",
                                   selectedVibe: "🔥 Trending")
        model.restore(legacy)
        try await eventually { model.isShowingLocationSheet }
        XCTAssertTrue(fetcher.selections.isEmpty)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)

        // The user picks a place in the sheet, then runs it back again.
        model.chooseSearchCenter(CLLocationCoordinate2D(latitude: 34.15, longitude: -118.14))
        model.commitSearchAreaLabel("Pasadena")
        model.restore(legacy)
        let sent = try await submitted()
        XCTAssertEqual(sent.location, "Pasadena")
        XCTAssertEqual(sent.latitude, 34.15)
        XCTAssertEqual(sent.occasion, "Late Night")
        XCTAssertEqual(sent.foodFeelings, ["Handheld"])
    }

    // MARK: - Location sheet state (P1-5)

    func testNoAreaUntilAPlaceIsChosenAndReopeningStartsThere() {
        let model = home(withArea: false)
        XCTAssertNil(model.searchAreaCenter, "no GPS, nothing chosen: the sheet has no center to commit")
        XCTAssertNil(model.searchAreaLabel)
        XCTAssertFalse(model.hasUsableLocation)
        XCTAssertEqual(model.locationChipLabel, "Set location")

        // Turning on radius mode alone doesn't invent an area.
        model.setRadiusMode(true)
        XCTAssertFalse(model.hasUsableLocation)
        XCTAssertEqual(model.locationChipLabel, "Set location")
        model.setRadiusMode(false)
        model.commitSearchAreaLabel("  ")
        XCTAssertFalse(model.hasUsableLocation)

        // A picked place in city mode: center and label are kept.
        let picked = CLLocationCoordinate2D(latitude: 34.0195, longitude: -118.4912)
        model.chooseSearchCenter(picked)
        model.commitSearchAreaLabel("Santa Monica")
        XCTAssertFalse(model.selection.useRadiusSearch)
        XCTAssertEqual(model.searchAreaCenter?.latitude, picked.latitude)
        XCTAssertEqual(model.searchAreaLabel, "Santa Monica")
        XCTAssertEqual(model.locationChipLabel, "Santa Monica")

        // Toggling radius off keeps the center; a new journey keeps it too.
        model.setSearchRadius(3, center: picked)
        model.setRadiusMode(false)
        model.reset()
        XCTAssertEqual(model.searchAreaCenter?.longitude, picked.longitude)
        XCTAssertTrue(model.hasUsableLocation)
    }

    // MARK: - Re-running a saved vibe (P2-2)

    func testRestoredVibeAdjustsFromTheFeedNotThePreviousJourney() async throws {
        let model = home()
        model.applyIntent(.food, refinement: refinement(.food, "Quick bite"), lateNight: false)
        model.selectFoodFeeling("Surprise me")
        model.continueFromFoodFeeling()   // waits ~260 ms before submitting
        try await eventually { self.fetcher.selections.count == 1 && model.step == .reveal }

        let vibe = VibeSelection(occasion: "Brunch", foodFeelings: ["Eggy & savory"], location: "Pasadena",
                                 selectedVibe: "⭐ Best rated")
        model.restore(vibe)
        _ = try await submitted(count: 2)
        try await eventually { model.step == .reveal }
        model.adjustVibe()
        XCTAssertEqual(model.step, .feed, "not the food step the previous journey used")
        XCTAssertTrue(model.isShowingIntentSheet)
        XCTAssertEqual(model.selection.occasion, "Brunch")
    }

    // MARK: - Helpers

    private func refinement(_ intent: FeedIntent, _ label: String) -> IntentRefinement {
        guard let match = intent.refinements.first(where: { $0.label == label }) else {
            XCTFail("\(intent) has no \(label) chip")
            return IntentRefinement(label)
        }
        return match
    }

    func testTikTokCityNeverUsesTheLocationPlaceholder() async {
        let model = home(withArea: false)
        model.detectedLocation = HomeViewModel.unsetLocationLabel
        let fromPlaceholder = await model.cityForTikTok()
        XCTAssertEqual(fromPlaceholder, "")
        model.selection.location = "your area"
        let fromTypedPlaceholder = await model.cityForTikTok()
        XCTAssertEqual(fromTypedPlaceholder, "")
        model.selection.location = "Echo Park, Los Angeles, CA"
        let fromRealPlace = await model.cityForTikTok()
        XCTAssertEqual(fromRealPlace, "Los Angeles, CA")
    }

    private func home(withArea: Bool = true) -> HomeViewModel {
        let ads = LoadingAdController(frequency: LoadingAdFrequencyStore(defaults: defaults), eligible: { false },
            record: { _, _, _, _, _, _, _, _ in }, observeEnvironment: false)
        let fetcher = self.fetcher!
        let model = HomeViewModel(loadingAds: ads, allowance: allowance, commerceEnabled: { false },
            fetchRecommendations: { selection, _ in await fetcher.fetch(selection) },
            enrich: { recommendations, _, _ in recommendations }, readinessTimeout: 60)
        model.reduceMotionPreference = true
        if withArea { model.detectedLocation = "Los Angeles" }
        return model
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Expected asynchronous state did not arrive", file: file, line: line)
        throw URLError(.timedOut)
    }

    private func submitted(count: Int = 1, file: StaticString = #filePath, line: UInt = #line) async throws -> VibeSelection {
        for _ in 0..<5_000 {
            if fetcher.selections.count >= count { return fetcher.selections[count - 1] }
            await Task.yield()
        }
        XCTFail("Expected \(count) submitted discovery", file: file, line: line)
        throw URLError(.timedOut)
    }
}

@MainActor
private final class RecordingFetcher {
    private(set) var selections: [VibeSelection] = []

    func fetch(_ selection: VibeSelection) async -> VibeFetchOutcome {
        selections.append(selection)
        // A transport failure is never billed, so one test can submit twice.
        return VibeFetchOutcome(result: VibeResult(recommendations: [], groundingPlaces: [], relaxed: false),
                                failure: .transportError)
    }
}
