import XCTest
@testable import bilu

/// VoiceOver copy for the restaurant detail screen (audit P1-5).
@MainActor
final class DetailAccessibilityTests: XCTestCase {
    func testWholeStarRatingsReadAsIntegers() {
        XCTAssertEqual(RestaurantDetailView.starRatingLabel(4), "Rated 4 of 5")
        XCTAssertEqual(RestaurantDetailView.starRatingLabel(5), "Rated 5 of 5")
        XCTAssertEqual(RestaurantDetailView.starRatingLabel(0), "Rated 0 of 5")
    }

    func testFractionalStarRatingsKeepOneDecimal() {
        XCTAssertEqual(RestaurantDetailView.starRatingLabel(4.5), "Rated 4.5 of 5")
    }

    func testOutOfRangeStarRatingsAreClamped() {
        XCTAssertEqual(RestaurantDetailView.starRatingLabel(7), "Rated 5 of 5")
        XCTAssertEqual(RestaurantDetailView.starRatingLabel(-1), "Rated 0 of 5")
    }
}
