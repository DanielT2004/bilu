import XCTest
@testable import bilu

final class ExploreAccessibilityTests: XCTestCase {
    func testCardSummaryReadsAsOneSentence() {
        let summary = RecommendationCard.accessibilitySummary(
            name: "Luigi's", rating: 4.5, distance: "0.4 mi", area: "Mission",
            cuisine: "Italian", price: "$$", parking: "Street")
        XCTAssertEqual(summary, "Luigi's, rating 4.5, 0.4 mi, Mission, Italian, moderate price, Parking: Street")
    }

    func testCardSummarySkipsMissingFields() {
        let summary = RecommendationCard.accessibilitySummary(
            name: "Recovered Bakery", rating: nil, distance: nil, area: nil,
            cuisine: nil, price: nil, parking: "Parking not confirmed")
        XCTAssertEqual(summary, "Recovered Bakery, Parking not confirmed")
    }

    func testPriceTiersAreSpokenAsWords() {
        XCTAssertEqual(RecommendationCard.spokenPrice("$"), "inexpensive")
        XCTAssertEqual(RecommendationCard.spokenPrice("$$"), "moderate price")
        XCTAssertEqual(RecommendationCard.spokenPrice("$$$"), "expensive")
        XCTAssertEqual(RecommendationCard.spokenPrice("$$$$"), "very expensive")
        XCTAssertNil(RecommendationCard.spokenPrice("cheap"))
    }
}
