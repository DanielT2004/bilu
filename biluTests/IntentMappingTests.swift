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
        let model = home(sharedPlaces: { FeedTikTokPlace.from([share]) })
        model.refreshFeed()
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

    // MARK: - Helpers

    private func refinement(_ intent: FeedIntent, _ label: String) -> IntentRefinement {
        guard let match = intent.refinements.first(where: { $0.label == label }) else {
            XCTFail("\(intent) has no \(label) chip")
            return IntentRefinement(label)
        }
        return match
    }

    private func home(sharedPlaces: @escaping () -> [FeedTikTokPlace] = { [] }) -> HomeViewModel {
        let ads = LoadingAdController(frequency: LoadingAdFrequencyStore(defaults: defaults), eligible: { false },
            record: { _, _, _, _, _, _, _, _ in }, observeEnvironment: false)
        let fetcher = self.fetcher!
        let model = HomeViewModel(loadingAds: ads, allowance: allowance, commerceEnabled: { false },
            fetchRecommendations: { selection, _ in await fetcher.fetch(selection) },
            enrich: { recommendations, _, _ in recommendations }, readinessTimeout: 60,
            loadSharedPlaces: sharedPlaces)
        model.reduceMotionPreference = true
        model.detectedLocation = "Los Angeles"
        return model
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
