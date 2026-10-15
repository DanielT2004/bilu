import XCTest

/// Search-tab accessibility gates that don't need a live (paid) TikTok search:
/// selected state on the sort chips, 44 pt targets, and the error retry button.
@MainActor
final class SearchAccessibilityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSortChipsAnnounceSelectionAndMeetTapTargetSize() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["tab-search"].tap()

        let relevant = app.buttons["search-sort-0"]
        let mostLiked = app.buttons["search-sort-1"]
        let mostRecent = app.buttons["search-sort-2"]
        XCTAssertTrue(relevant.waitForExistence(timeout: 10))

        XCTAssertEqual(relevant.label, "Relevant")
        XCTAssertTrue(relevant.isSelected)
        XCTAssertFalse(mostLiked.isSelected)
        XCTAssertFalse(mostRecent.isSelected)

        for chip in [relevant, mostLiked, mostRecent] {
            XCTAssertGreaterThanOrEqual(chip.frame.height, 43.5, chip.label)
        }

        // With no results yet, changing sort applies directly (no confirmation).
        mostLiked.tap()
        XCTAssertTrue(mostLiked.isSelected)
        XCTAssertFalse(relevant.isSelected)
    }

    func testRetryButtonMeetsTapTargetSize() {
        let app = XCUIApplication()
        app.launchEnvironment["BILU_UI_TEST_TIKTOK_ERROR"] = "offline"
        app.launch()
        app.buttons["tab-search"].tap()

        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(retry.frame.height, 43.5)
    }
}
