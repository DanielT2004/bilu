import SwiftData
import XCTest
@testable import bilu

@MainActor
final class ModelAndPersistenceTests: XCTestCase {
    func testFreeDiscoveryAllowanceResetsEachCalendarDay() throws {
        let suiteName = "DiscoveryAllowanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var currentDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-17T12:00:00Z"))
        let allowance = DiscoveryAllowance(defaults: defaults, now: { currentDate })

        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
        allowance.recordDiscovery(usedRewardToken: nil)
        allowance.recordDiscovery(usedRewardToken: nil)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 0)
        XCTAssertFalse(allowance.canRunDiscovery)

        currentDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T00:00:00Z"))
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
        XCTAssertTrue(allowance.canRunDiscovery)
    }

    func testRewardTokenIsSingleUse() throws {
        let suiteName = "RewardAllowanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let allowance = DiscoveryAllowance(defaults: defaults)

        allowance.recordDiscovery(usedRewardToken: nil)
        allowance.grantReward(token: "verified-token")
        XCTAssertTrue(allowance.canRunDiscovery)
        XCTAssertTrue(allowance.hasRewardedDiscovery)

        allowance.recordDiscovery(usedRewardToken: "verified-token")
        XCTAssertFalse(allowance.hasRewardedDiscovery)
        XCTAssertFalse(allowance.canRunDiscovery)
    }

    func testBackendRewardRequirementReconcilesStaleLocalAccess() throws {
        let suiteName = "RewardReconciliationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let allowance = DiscoveryAllowance(defaults: defaults)

        allowance.grantReward(token: "expired-token")
        allowance.reconcileRewardRequired()

        XCTAssertEqual(allowance.remainingFreeDiscoveries, 0)
        XCTAssertFalse(allowance.hasRewardedDiscovery)
        XCTAssertFalse(allowance.canRunDiscovery)
    }

    func testParkingDisplayDoesNotClaimUnverifiedParking() {
        XCTAssertEqual(makeRecommendation(parking: nil).parkingDisplayText, "Parking not confirmed")
        XCTAssertEqual(makeRecommendation(parking: "   ").parkingDisplayText, "Parking not confirmed")
        XCTAssertEqual(makeRecommendation(parking: "unknown").parkingDisplayText, "Parking not confirmed")
        XCTAssertEqual(makeRecommendation(parking: "Not confirmed").parkingDisplayText, "Parking not confirmed")
    }

    func testParkingDisplayPreservesVerifiedGuidance() {
        XCTAssertEqual(
            makeRecommendation(parking: "  Private lot  ").parkingDisplayText,
            "Private lot"
        )
    }

    func testRecommendationIdentityPrefersPlaceID() {
        XCTAssertEqual(makeRecommendation(placeId: "google-place-123").identityKey, "google-place-123")
        XCTAssertEqual(makeRecommendation().identityKey, "Test KitchenHouse Special")
    }

    func testOnlyExplicitlyOpenRecommendationsAreFeedEligible() {
        let open = makeRecommendation(isOpen: true)
        let closed = makeRecommendation(name: "Closed Kitchen", isOpen: false)
        let unknown = makeRecommendation(name: "Unknown Kitchen", isOpen: nil)

        XCTAssertTrue(open.isVerifiedOpen)
        XCTAssertFalse(closed.isVerifiedOpen)
        XCTAssertFalse(unknown.isVerifiedOpen)
        XCTAssertEqual(
            [open, closed, unknown].verifiedOpenRecommendations.map(\.name),
            [open.name]
        )
    }

    func testCuisineSearchRequestsSixOptionsAcrossLocations() throws {
        let cases = [
            (cuisine: "Japanese", location: "Los Angeles"),
            (cuisine: "Italian", location: "San Diego, North Park"),
            (cuisine: "Thai", location: "Bishop, California")
        ]
        for testCase in cases {
            let selection = VibeSelection(
                occasion: "Sit Down",
                location: testCase.location,
                cuisineMode: "country",
                selectedCountry: testCase.cuisine
            )
            let prompt = PromptBuilder.getPrompt(selection: selection)

            XCTAssertTrue(prompt.contains("Find up to 6 exceptional spots"))
            XCTAssertTrue(prompt.contains("Return up to 6 results as JSON"))
            XCTAssertTrue(prompt.contains("Aim for 6 distinct matching spots when available"))
            XCTAssertTrue(prompt.contains(testCase.location))
            XCTAssertTrue(prompt.contains(try XCTUnwrap(PromptConstants.countryPrompts[testCase.cuisine])))
            XCTAssertTrue(prompt.contains("Return fewer when there aren't enough suitable places"))
            XCTAssertTrue(prompt.contains(#"If nothing fits, return { "recommendations": [] }"#))
        }
    }

    func testSixOptionRadiusSearchPreservesCuisineAndAppliedFilters() {
        let selection = VibeSelection(
            occasion: "Sit Down",
            foodFeelings: ["Handheld"],
            selectedSubOptions: ["Handheld": ["Taco"]],
            location: "Pasadena",
            pricePoints: ["$$"],
            openNow: true,
            radiusMiles: 2.5,
            latitude: 34.1478,
            longitude: -118.1445,
            useRadiusSearch: true,
            fineTuneApplied: true,
            wheelchairAccess: true
        )
        let prompt = PromptBuilder.getPrompt(selection: selection)

        XCTAssertTrue(prompt.contains("Find up to 6 exceptional spots"))
        XCTAssertTrue(prompt.contains("Return up to 6 results as JSON"))
        XCTAssertTrue(prompt.contains("within 2.5 miles"))
        XCTAssertTrue(prompt.contains("34.1478"))
        XCTAssertTrue(prompt.contains("The user specifically wants tacos"))
        XCTAssertTrue(prompt.contains("Price range: $$"))
        XCTAssertTrue(prompt.contains("Must be open right now"))
        XCTAssertTrue(prompt.contains("Must have wheelchair-accessible entrance and seating"))
    }

    func testSixResultPayloadKeepsAllVerifiedOptionsInOrder() throws {
        let recommendations = (1...6).map { index in
            makeRecommendation(
                name: "Kitchen \(index)",
                placeId: "place-\(index)"
            )
        }
        let payload = VibeResult(recommendations: recommendations, groundingPlaces: [], relaxed: false)
        let decoded = try JSONDecoder().decode(VibeResult.self, from: JSONEncoder().encode(payload))

        XCTAssertEqual(decoded.recommendations.count, 6)
        XCTAssertEqual(
            decoded.recommendations.verifiedOpenRecommendations.map(\.name),
            ["Kitchen 1", "Kitchen 2", "Kitchen 3", "Kitchen 4", "Kitchen 5", "Kitchen 6"]
        )
    }

    func testVibeMatchingIgnoresOrderButDetectsLocationChanges() {
        let first = VibeSelection(
            occasion: "Dinner",
            keyQuestionAnswer: "Best quality nearby",
            foodFeelings: ["Handheld", "Fresh & light"],
            location: "Los Angeles"
        )
        var reordered = first
        reordered.foodFeelings.reverse()
        reordered.partySize = 8

        XCTAssertTrue(first.matches(reordered))

        reordered.location = "Pasadena"
        XCTAssertFalse(first.matches(reordered))
    }

    func testLegacyVibeJSONUsesMigrationSafeDefaults() throws {
        let json = Data(#"{"occasion":"Dinner","keyQuestionAnswer":"Best quality nearby"}"#.utf8)
        let decoded = try JSONDecoder().decode(VibeSelection.self, from: json)

        XCTAssertEqual(decoded.location, "")
        XCTAssertEqual(decoded.foodFeelings, [])
        XCTAssertEqual(decoded.parking, [])
        XCTAssertEqual(decoded.radiusMiles, 2.0)
        XCTAssertFalse(decoded.useRadiusSearch)
        XCTAssertFalse(decoded.fineTuneApplied)
    }

    func testInMemorySwiftDataRoundTrip() throws {
        let container = PersistenceController.previewContainer()
        let context = ModelContext(container)
        let saved = SavedPlace(
            from: makeRecommendation(placeId: "persisted-place", parking: "Street parking nearby"),
            listType: .wantToGo
        )

        context.insert(saved)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<SavedPlace>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.identityKey, "persisted-place")
        XCTAssertEqual(fetched.first?.listType, .wantToGo)
        XCTAssertEqual(fetched.first?.parking, "Street parking nearby")
    }

    private func makeRecommendation(
        name: String = "Test Kitchen",
        placeId: String? = nil,
        parking: String? = nil,
        isOpen: Bool? = true
    ) -> Recommendation {
        Recommendation(
            name: name,
            dish: "House Special",
            image: nil,
            explanation: "A test recommendation.",
            mapsUrl: "https://maps.google.com",
            latitude: 34.05,
            longitude: -118.24,
            rating: 4.7,
            reviewCount: 120,
            isOpen: isOpen,
            photos: nil,
            address: "123 Test Street",
            phone: nil,
            website: nil,
            parking: parking,
            placeId: placeId,
            photoRefs: nil,
            reviews: nil
        )
    }
}
