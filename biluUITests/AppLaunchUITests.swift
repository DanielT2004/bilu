import XCTest
import UIKit

@MainActor
final class AppLaunchUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// An empty native search field reports its placeholder (or nothing) as its value.
    private func isEmpty(_ field: XCUIElement) -> Bool {
        let value = field.value as? String ?? ""
        return value.isEmpty || value == field.placeholderValue
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
        XCTAssertTrue(app.tabBars.buttons["Explore"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Search"].exists)
        XCTAssertTrue(app.tabBars.buttons["Profile"].exists)
    }

    func testSearchQueryPersistsAcrossTabChanges() {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Search"].tap()

        let queryField = app.searchFields.firstMatch
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        queryField.tap()
        // No city, so submitting stays on the client-side guidance (no backend
        // call) and dismisses the keyboard, which covers the native tab bar.
        queryField.typeText("Best ramen\n")
        XCTAssertTrue(app.staticTexts["Add a city to search"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["feed-title"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Search"].tap()
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        XCTAssertEqual(queryField.value as? String, "Best ramen")
        XCTAssertTrue(app.staticTexts["Add a city to search"].exists)
    }

    /// Re-selecting Explore returns the journey to its start (the native TabView's
    /// selection Binding routes through RootTabView.selectTab, which bumps
    /// `homeReselectCount`; HomeView calls `viewModel.reset()`). The tab bar is
    /// hidden on survey steps, so the journey enters a step through the intent
    /// sheet, backs out to the feed, and re-selects Explore there. Never reaches a
    /// live discovery: Food hands off to the food-feeling step without searching.
    func testReselectingExploreReturnsJourneyToStart() {
        let app = XCUIApplication()
        app.launch()
        deferLocationPrompt(app)

        let feedTitle = app.staticTexts["feed-title"]
        let exploreTab = app.tabBars.buttons["Explore"]
        XCTAssertTrue(feedTitle.waitForExistence(timeout: 10))
        XCTAssertTrue(exploreTab.exists)

        // Enter the journey: action button → Food → Quick bite → food step.
        openIntentSheet(app)
        app.buttons["intent-food"].tap()
        app.buttons["refinement-Quick bite"].tap()
        app.buttons["intent-find-spots"].tap()

        // Mid-survey: the tab bar is hidden, so Explore cannot be re-selected here.
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What are you feeling?"].exists)
        XCTAssertTrue(exploreTab.waitForNonExistence(timeout: 5))

        // Step back out: the feed and the tab bar return.
        back.tap()
        XCTAssertTrue(feedTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(exploreTab.waitForExistence(timeout: 5))

        // Re-selecting Explore lands on the feed with its action button.
        exploreTab.tap()
        XCTAssertTrue(feedTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feed-action-button"].exists)
        XCTAssertFalse(back.exists)
    }

    /// Results keep the tab bar, so re-selecting Explore there resets to the feed.
    /// Uses the DEBUG recovery fixture: no provider call, no real allowance.
    func testReselectingExploreFromResultsReturnsToFeed() {
        let app = XCUIApplication()
        app.launchEnvironment["BILU_UI_TEST_RECOVERY"] = "timedOut"
        app.launch()

        let recoveryTitle = app.staticTexts["search-recovery-title"]
        XCTAssertTrue(recoveryTitle.waitForExistence(timeout: 10))
        app.tabBars.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["feed-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(recoveryTitle.waitForNonExistence(timeout: 5))
    }

    /// The action button is a labelled 44+ pt target; the sheet shows all six
    /// intents, refinements gate "Find spots", and "Late night" is a modifier
    /// on Drinks and Café only. Nothing here submits a discovery.
    func testIntentSheetIntentsRefinementsAndLateNightModifier() {
        let app = XCUIApplication()
        app.launch()
        deferLocationPrompt(app)
        XCTAssertTrue(app.staticTexts["feed-title"].waitForExistence(timeout: 10))

        let action = app.buttons["feed-action-button"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.label, "Find spots")
        XCTAssertGreaterThanOrEqual(action.frame.width, 44)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)

        openIntentSheet(app)
        for intent in ["cafe", "food", "drinks", "lateNight", "brunch", "sweet"] {
            XCTAssertTrue(app.buttons["intent-\(intent)"].exists, "Missing intent \(intent)")
        }
        let findSpots = app.buttons["intent-find-spots"]
        XCTAssertFalse(findSpots.isEnabled, "Nothing picked yet")

        app.buttons["intent-drinks"].tap()
        XCTAssertTrue(app.buttons["modifier-late-night"].waitForExistence(timeout: 3))
        XCTAssertFalse(findSpots.isEnabled, "Drinks needs a bar type")
        app.buttons["intent-brunch"].tap()
        XCTAssertTrue(app.buttons["modifier-late-night"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(findSpots.isEnabled)
        app.buttons["intent-cafe"].tap()
        XCTAssertTrue(app.buttons["modifier-late-night"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["refinement-Work or study"].isSelected, "Café defaults to Work or study")
    }

    private func deferLocationPrompt(_ app: XCUIApplication) {
        let deferLocation = app.buttons["Maybe later"]
        if deferLocation.waitForExistence(timeout: 2) {
            deferLocation.tap()
        }
    }

    private func openIntentSheet(_ app: XCUIApplication) {
        let action = app.buttons["feed-action-button"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.tap()
        XCTAssertTrue(app.buttons["intent-food"].waitForExistence(timeout: 5))
    }

    func testSearchKeepsKeyboardVisibleAfterEveryCharacter() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Search"].tap()

        // Native `.searchable` field in Search's navigation bar.
        let queryField = app.searchFields.firstMatch
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
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
        XCTAssertTrue(isEmpty(queryField))
        XCTAssertTrue(keyboard.exists, "Deleting back to an empty query must keep focus")
        queryField.typeText("ramen")
        queryField.typeText(" in Los Angeles")
        XCTAssertEqual((queryField.value as? String)?.lowercased(), "ramen in los angeles")
        XCTAssertTrue(keyboard.exists)
    }

    func testSearchCanSubmitEditAndClearWithoutLosingText() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Search"].tap()

        let queryField = app.searchFields.firstMatch
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

        // The native clear (x) button empties the field and the city guidance.
        queryField.buttons["Clear text"].tap()
        XCTAssertTrue(isEmpty(queryField))
        XCTAssertTrue(guidance.waitForNonExistence(timeout: 5))

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
        app.tabBars.buttons["Search"].tap()

        // Native search field: sized by the system; VoiceOver reads the prompt.
        let queryField = app.searchFields.firstMatch
        XCTAssertTrue(queryField.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(queryField.frame.height, 36)
        XCTAssertEqual(queryField.label, "Try: matcha in San Diego")
        queryField.tap()
        queryField.typeText("ramen")

        XCTAssertEqual((queryField.value as? String)?.lowercased(), "ramen")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(queryField.buttons["Clear text"].exists)
    }

    func testRewardedDiscoveryPaywallIsReachable() {
        let app = XCUIApplication()
        app.launch()

        let deferLocation = app.buttons["Maybe later"]
        if deferLocation.waitForExistence(timeout: 2) {
            deferLocation.tap()
        }

        app.tabBars.buttons["Profile"].tap()
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

            app.tabBars.buttons["Search"].tap()

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
