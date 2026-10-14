import XCTest
import UIKit

@MainActor
final class AppLaunchUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppLaunchesWithPrimaryNavigation() {
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            let allowButton = alert.buttons["Allow While Using App"]
            guard allowButton.exists else { return false }
            allowButton.tap()
            return true
        }

        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // Interact once so XCTest can invoke the permission monitor on a clean CI
        // simulator. Use the top corner so the fallback tap cannot advance the
        // survey and hide the tab bar when no alert is present.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.02)).tap()
        XCTAssertTrue(app.buttons["tab-explore"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab-search"].exists)
        XCTAssertTrue(app.buttons["tab-profile"].exists)
    }

    func testSearchQueryPersistsAcrossTabChanges() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["tab-search"].tap()

        let queryField = app.textFields["search-query-field"]
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        queryField.tap()
        queryField.typeText("Best ramen in Los Angeles")

        app.buttons["tab-explore"].tap()
        XCTAssertTrue(app.staticTexts["How much time"].waitForExistence(timeout: 10))

        app.buttons["tab-search"].tap()
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        XCTAssertEqual(queryField.value as? String, "Best ramen in Los Angeles")
    }

    /// Re-selecting Explore returns the journey to its start (RootTabView.selectTab
    /// bumps `homeReselectCount`, HomeView calls `viewModel.reset()`). The tab bar is
    /// hidden on survey steps, so the reachable mid-journey state with the tab bar
    /// visible is the occasion step after the user has changed the Eat/Drinks mode
    /// and stepped back out of a survey step. Never reaches a live discovery.
    func testReselectingExploreReturnsJourneyToStart() {
        let app = XCUIApplication()
        app.launch()

        let deferLocation = app.buttons["Maybe later"]
        if deferLocation.waitForExistence(timeout: 2) {
            deferLocation.tap()
        }

        let eatTitle = app.staticTexts["How much time"]
        let drinksTitle = app.staticTexts["What are you"]
        let exploreTab = app.buttons["tab-explore"]
        XCTAssertTrue(eatTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(exploreTab.exists)

        // Move into the journey: Drinks mode, then the Cafe survey step.
        app.buttons["Drinks & more"].tap()
        XCTAssertTrue(drinksTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(eatTitle.exists)

        let cafe = app.buttons.containing(.staticText, identifier: "Cafe Vibes").firstMatch
        XCTAssertTrue(cafe.waitForExistence(timeout: 5))
        cafe.tap()

        // Mid-survey: the tab bar is hidden, so Explore cannot be re-selected here.
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(exploreTab.waitForNonExistence(timeout: 5))

        // Step back out: still mid-journey (Drinks mode kept), tab bar visible again.
        back.tap()
        XCTAssertTrue(drinksTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(exploreTab.waitForExistence(timeout: 5))

        // Re-selecting Explore resets the journey to the Eat start screen.
        exploreTab.tap()
        XCTAssertTrue(eatTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(drinksTitle.waitForNonExistence(timeout: 5))
        XCTAssertTrue(exploreTab.exists)
    }

    func testSearchKeepsKeyboardVisibleAfterEveryCharacter() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["tab-search"].tap()

        let queryField = app.textFields["search-query-field"]
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        XCTAssertEqual(queryField.frame.height, 44, accuracy: 1)
        queryField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        var expected = ""
        for character in "ramen" {
            let key = keyboard.keys.matching(
                NSPredicate(format: "label ==[c] %@", String(character))
            ).firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 3))
            key.tap()
            expected.append(character)
            XCTAssertEqual((queryField.value as? String)?.lowercased(), expected)
            XCTAssertTrue(keyboard.exists, "Keyboard dismissed after typing \(expected)")
        }

        queryField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: expected.count))
        XCTAssertFalse(app.buttons["search-clear-button"].exists)
        XCTAssertTrue(keyboard.exists, "Deleting back to an empty query must keep focus")
        queryField.typeText("ramen")
        queryField.typeText(" in Los Angeles")
        XCTAssertEqual((queryField.value as? String)?.lowercased(), "ramen in los angeles")
        XCTAssertTrue(keyboard.exists)
    }

    func testSearchCanSubmitEditAndClearWithoutLosingText() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["tab-search"].tap()

        let queryField = app.textFields["search-query-field"]
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        queryField.tap()
        queryField.typeText("ramen\n")

        let guidance = app.staticTexts["Add a city to search"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        XCTAssertEqual((queryField.value as? String)?.lowercased(), "ramen")
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        queryField.tap()
        queryField.typeText(" noodles")
        XCTAssertEqual((queryField.value as? String)?.lowercased(), "ramen noodles")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        app.buttons["search-clear-button"].tap()
        XCTAssertFalse(app.buttons["search-clear-button"].exists)
        XCTAssertFalse(guidance.exists)

        queryField.tap()
        queryField.typeText("tacos")
        XCTAssertEqual((queryField.value as? String)?.lowercased(), "tacos")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    func testSearchKeepsFocusAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        ]
        app.launch()
        app.buttons["tab-search"].tap()

        let queryField = app.textFields["search-query-field"]
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(queryField.frame.height, 44)
        XCTAssertEqual(queryField.label, "Search food and places")
        queryField.tap()
        queryField.typeText("ramen")

        XCTAssertEqual((queryField.value as? String)?.lowercased(), "ramen")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let clearButton = app.buttons["search-clear-button"]
        XCTAssertGreaterThanOrEqual(clearButton.frame.height, 43.5)
        XCTAssertGreaterThanOrEqual(clearButton.frame.width, 43.5)
    }

    func testRewardedDiscoveryPaywallIsReachable() {
        let app = XCUIApplication()
        app.launch()

        let deferLocation = app.buttons["Maybe later"]
        if deferLocation.waitForExistence(timeout: 2) {
            deferLocation.tap()
        }

        app.buttons["tab-profile"].tap()
        app.swipeUp()

        let rewardedDiscoveries = app.staticTexts["Rewarded discoveries"]
        XCTAssertTrue(rewardedDiscoveries.waitForExistence(timeout: 10))
        rewardedDiscoveries.tap()

        XCTAssertTrue(app.staticTexts["Unlock another discovery"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["rewarded-ad-button"].exists)
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    func testTikTokErrorStatesAndRetry() {
        let cases: [(value: String, title: String, message: String)] = [
            ("offline", "You're offline", "Check your internet connection and try again."),
            ("timedOut", "Search took too long", "The search service didn't respond in time. Please try again."),
            ("unauthorized", "Couldn't start search", "We couldn't verify this search. Please try again."),
            ("rateLimited", "Too many searches", "Please wait about 42 seconds, then try again."),
            ("serverUnavailable", "Search is unavailable", "Our search service is having trouble. Please try again shortly."),
            ("invalidResponse", "Couldn't load results", "The search service returned an unexpected response. Please try again."),
            ("requestFailed", "Couldn't load results", "Something interrupted the search. Please try again.")
        ]

        for testCase in cases {
            let app = XCUIApplication()
            app.launchEnvironment["BILU_UI_TEST_TIKTOK_ERROR"] = testCase.value
            app.launch()

            app.buttons["tab-search"].tap()

            XCTAssertTrue(app.staticTexts[testCase.title].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts[testCase.message].exists)

            let retry = app.buttons["Try Again"]
            XCTAssertTrue(retry.exists)
            retry.tap()
            XCTAssertTrue(app.staticTexts[testCase.title].waitForExistence(timeout: 5))

            app.terminate()
        }
    }
}
