import XCTest

/// Release gate: a persistent-store open failure must never look like a
/// successful save. `-SimulatePersistenceFailure YES` (DEBUG only) forces the
/// in-memory fallback without touching the real store.
@MainActor
final class PersistenceFailureUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testProfileExplainsSavesAreNotKeptWhenStoreFails() {
        let app = XCUIApplication()
        app.launchArguments = ["-SimulatePersistenceFailure", "YES"]
        app.launch()
        openProfile(app)

        let banner = app.descendants(matching: .any)["saves-not-kept-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(banner.label.contains("Saves won't be kept right now"))
        XCTAssertTrue(banner.label.contains("only until you close the app"))
        XCTAssertTrue(banner.isHittable)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "saves-not-kept-banner-light"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testProfileHasNoBannerWhenStoreOpens() {
        let app = XCUIApplication()
        app.launch()
        openProfile(app)

        XCTAssertTrue(app.buttons["tab-profile"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["saves-not-kept-banner"].waitForExistence(timeout: 2))
    }

    /// Reaches a real detail sheet through the DEBUG recovery fixture (no provider
    /// calls), then saves: the save must read as session-only, never as kept.
    func testDetailSaveSaysItIsNotKeptWhenStoreFails() {
        let app = XCUIApplication()
        app.launchArguments = ["-SimulatePersistenceFailure", "YES"]
        app.launchEnvironment["BILU_UI_TEST_RECOVERY"] = "timedOut"
        app.launch()

        let retry = app.buttons["search-recovery-action"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recovered Bakery'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let banner = app.descendants(matching: .any)["saves-not-kept-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        XCTAssertTrue(banner.label.contains("Saves last only until you close Bilu"))

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(save.frame.height, 44)
        save.tap()

        let savedValue = NSPredicate(format: "value == %@", "Saved until you close Bilu")
        expectation(for: savedValue, evaluatedWith: save)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(banner.label.contains("Saved for now, not kept after you close Bilu"))
        XCTAssertTrue(banner.label.contains("restart Bilu, then save it again"))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "detail-save-degraded-light"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDetailSaveIsNormalWhenStoreOpens() {
        let app = XCUIApplication()
        app.launchEnvironment["BILU_UI_TEST_RECOVERY"] = "timedOut"
        app.launch()

        let retry = app.buttons["search-recovery-action"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Recovered Bakery'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["saves-not-kept-banner"].exists)
    }

    private func openProfile(_ app: XCUIApplication) {
        let deferLocation = app.buttons["Maybe later"]
        if deferLocation.waitForExistence(timeout: 3) {
            deferLocation.tap()
        }
        let profileTab = app.buttons["tab-profile"]
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10))
        profileTab.tap()
    }
}
