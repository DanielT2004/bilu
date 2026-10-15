import XCTest

/// Drives the real Explore results card through the DEBUG
/// `BILU_UI_TEST_RECOVERY` fixture: the first search fails with the scenario,
/// a retry succeeds. No provider calls, ads, or real allowance are used.
@MainActor
final class RecommendationRecoveryUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testRetryableFailuresShowDistinctCopyAndRecover() {
        let cases: [(scenario: String, title: String, message: String)] = [
            ("timedOut", "Search took too long",
             "We stopped waiting so you wouldn't be stuck here. This search wasn't counted — try again for a fresh one."),
            ("capacity", "Search is at capacity",
             "Our search provider is temporarily at its limit. Give it a minute, then try again. This search wasn't counted."),
            ("offline", "You're offline",
             "Check your internet connection, then try again. This search wasn't counted."),
            ("sessionRejected", "Couldn't verify this device",
             "We refreshed your session but couldn't confirm it. Try again in a moment."),
            ("transport", "Couldn't reach us",
             "Something went wrong on our end. Tap retry — usually works the second time.")
        ]
        for testCase in cases {
            let app = launch(testCase.scenario)
            assertCard(app, title: testCase.title, message: testCase.message, action: "Try again")
            app.buttons["search-recovery-action"].tap()
            XCTAssertTrue(recoveredCard(app).waitForExistence(timeout: 10),
                          "\(testCase.scenario) retry should reveal results")
            XCTAssertFalse(app.staticTexts["search-recovery-title"].exists)
            app.terminate()
        }
    }

    func testNoMatchOffersAdjustVibe() {
        let app = launch("noMatches")
        assertCard(app, title: "Nothing matched, yet",
                   message: "Try a different vibe or widen your search — there's always something nearby worth trying.",
                   action: "Adjust your vibe")
        app.buttons["search-recovery-action"].tap()
        XCTAssertTrue(app.staticTexts["search-recovery-title"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(recoveredCard(app).exists, "Adjusting must not run another search")
    }

    func testUsageLimitOffersBackToExplore() {
        let app = launch("usageLimit")
        assertCard(app, title: "Search limit reached",
                   message: "This account has used its current search allowance. Please try again after the limit resets.",
                   action: "Back to Explore")
        app.buttons["search-recovery-action"].tap()
        XCTAssertTrue(app.buttons["tab-explore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["search-recovery-title"].exists)
    }

    func testRejectedRewardReopensGateWithNotice() {
        let app = launch("rewardRejected")
        XCTAssertTrue(app.staticTexts["We couldn't verify your ad reward. Watch another ad to try again."]
            .waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Unlock another discovery"].exists)
        XCTAssertFalse(app.staticTexts["search-recovery-title"].exists)
    }

    /// The result card is one button whose label starts with the place name.
    private func recoveredCard(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recovered Bakery'")).firstMatch
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BILU_UI_TEST_RECOVERY"] = scenario
        app.launch()
        return app
    }

    private func assertCard(_ app: XCUIApplication, title: String, message: String, action: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let titleText = app.staticTexts["search-recovery-title"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(titleText.label, title, file: file, line: line)
        XCTAssertEqual(app.staticTexts["search-recovery-message"].label, message, file: file, line: line)
        XCTAssertEqual(app.buttons["search-recovery-action"].label, action, file: file, line: line)
    }
}
