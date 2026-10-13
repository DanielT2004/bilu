import XCTest
import UIKit

@MainActor
final class LoadingAdvertisementUITests: XCTestCase {
    func testQuickResultsNeverWaitForAdvertisement() {
        let app = launch("quick")
        XCTAssertTrue(app.staticTexts["loading-preview-results"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["loading-preview-banner"].exists)
    }

    func testBannerDisappearsWhenResultsArrive() {
        let app = launch("success")
        XCTAssertTrue(app.staticTexts["loading-preview-banner"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Advertisement"].exists)
        XCTAssertTrue(app.staticTexts["loading-preview-results"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["loading-preview-banner"].exists)
    }

    func testFailedBannerStillReachesResults() {
        let app = launch("failed")
        XCTAssertTrue(app.staticTexts["loading-preview-results"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["loading-preview-banner"].exists)
    }

    func testSlowDiscoveryCanCancelWithBannerVisible() {
        let app = launch("slow")
        XCTAssertTrue(app.staticTexts["loading-preview-banner"].waitForExistence(timeout: 5))
        app.buttons["loading-preview-cancel"].tap()
        XCTAssertTrue(app.staticTexts["loading-preview-cancelled"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["loading-preview-banner"].exists)
    }

    func testLoadingLayoutAtAccessibilityTextSize() {
        let app = launch("slow", accessibility: true)
        XCTAssertTrue(app.staticTexts["discovery-loading-title"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons["loading-preview-cancel"].frame.height, 44)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Loading with accessibility text size"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLoadingLayoutScreenshot() {
        let app = launch("slow")
        let banner = app.staticTexts["loading-preview-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(banner.isHittable)
        XCTAssertLessThanOrEqual(banner.frame.maxY, app.frame.maxY)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Loading banner layout (fixture, not live AdMob)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Opt-in smoke test; not part of deterministic CI. No real AI is invoked.
    func testGoogleTestBannerSmoke() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BILU_RUN_ADMOB_SMOKE"] == "1")
        let app = launch("sdk")
        XCTAssertTrue(app.staticTexts["Advertisement"].waitForExistence(timeout: 45),
                      "Google test banner did not load; consent/network/fill needs manual verification")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Google test banner"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launch(_ scenario: String, accessibility: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BILU_UI_TEST_LOADING_SCENARIO"] = scenario
        if scenario == "sdk" { app.launchEnvironment["BILU_TEST_UMP_GEOGRAPHY"] = "other" }
        if accessibility {
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue]
        }
        app.launch()
        return app
    }
}
