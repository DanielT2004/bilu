import XCTest

/// VoiceOver semantics of the Explore survey, fine-tune and result card
/// (audit P0-1/2/3, P1-2/3/4). Uses no live discovery: the results case runs
/// on the DEBUG `BILU_UI_TEST_RECOVERY` fixture.
@MainActor
final class ExploreAccessibilityUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testFoodCardAndFineTuneAnnounceRoleAndState() {
        let app = XCUIApplication()
        app.launch()
        let deferLocation = app.buttons["Maybe later"]
        if deferLocation.waitForExistence(timeout: 3) { deferLocation.tap() }

        // Reach the food step the redesign way: action button → Food → Sit down.
        let action = app.buttons["feed-action-button"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        XCTAssertTrue(app.buttons["intent-food"].waitForExistence(timeout: 5))
        app.buttons["intent-food"].tap()
        let sitDown = app.buttons["refinement-Sit down"]
        XCTAssertTrue(sitDown.waitForExistence(timeout: 5))
        sitDown.tap()
        app.buttons["intent-find-spots"].tap()

        let italian = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Italian & pizza'")).firstMatch
        XCTAssertTrue(italian.waitForExistence(timeout: 5))
        XCTAssertFalse(italian.isSelected)
        italian.tap()
        XCTAssertTrue(italian.isSelected, "A picked food category must expose the selected trait")
        // Siblings are dimmed while a category is open and are hidden from VoiceOver.
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Meaty'")).firstMatch
            .waitForNonExistence(timeout: 3))

        let fineTune = app.buttons["explore-fine-tune"]
        XCTAssertTrue(fineTune.waitForExistence(timeout: 5))
        XCTAssertEqual(fineTune.label, "Fine-tune")
        fineTune.tap()

        XCTAssertTrue(app.otherElements["explore-progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["explore-progress"].value as? String, "Step 4 of 4")

        let moderate = app.buttons["fine-tune-price-2"]
        XCTAssertEqual(moderate.label, "Moderate price")
        // Sit Down pre-selects some tiers; tapping must flip the announced state.
        let wasSelected = moderate.isSelected
        moderate.tap()
        XCTAssertNotEqual(moderate.isSelected, wasSelected)

        let partySize = app.staticTexts["fine-tune-party-size"]
        XCTAssertEqual(partySize.label, "2 people")
        let more = app.buttons["fine-tune-party-increase"]
        XCTAssertEqual(more.label, "More people")
        more.tap()
        XCTAssertEqual(partySize.label, "3 people")
        XCTAssertEqual(app.buttons["fine-tune-party-decrease"].label, "Fewer people")

        let street = app.buttons["Street"]
        XCTAssertGreaterThanOrEqual(street.frame.height, 44)
        street.tap()
        XCTAssertTrue(street.isSelected)

        let wheelchair = app.switches["fine-tune-extra-wheelchair-access"]
        XCTAssertTrue(wheelchair.waitForExistence(timeout: 5), "Extras must be real switches")
        XCTAssertEqual(wheelchair.value as? String, "0")
        // Coordinate taps don't scroll, so bring the row on screen first.
        app.swipeUp()
        XCTAssertTrue(wheelchair.isHittable)
        // The switch itself…
        wheelchair.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(wheelchair.value as? String, "1")
        // …and the rest of the row both toggle it exactly once.
        wheelchair.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertEqual(wheelchair.value as? String, "0")

        XCTAssertGreaterThanOrEqual(app.buttons["Remove fine-tune"].frame.height, 44)
    }

    func testResultCardIsOneButtonWithSeparateDirections() {
        let app = XCUIApplication()
        app.launchEnvironment["BILU_UI_TEST_RECOVERY"] = "timedOut"
        app.launch()
        let retry = app.buttons["search-recovery-action"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()

        let card = app.buttons["recommendation-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.hasPrefix("Recovered Bakery"), card.label)
        XCTAssertTrue(card.label.contains("Parking not confirmed"), card.label)

        let directions = app.buttons["Take Me There"]
        XCTAssertTrue(directions.exists)
        XCTAssertGreaterThanOrEqual(directions.frame.height, 44)
        XCTAssertEqual(app.buttons["explore-share"].label, "Share these spots")
    }
}
