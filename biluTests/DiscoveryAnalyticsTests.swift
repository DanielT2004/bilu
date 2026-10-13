import XCTest
@testable import bilu

@MainActor
final class DiscoveryAnalyticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "DiscoveryAnalyticsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testNoOptInProducesNoEventsOrRequests() async {
        var uploads = 0
        let analytics = makeAnalytics { _ in uploads += 1; return .accepted }
        analytics.record(.started, discoveryID: UUID())
        await analytics.flush()
        XCTAssertEqual(analytics.pendingEventCount, 0)
        XCTAssertEqual(uploads, 0)
    }

    func testBoundedQueueAndBatchesKeepNewestEvents() async {
        enableConsent()
        var uploaded: [DiscoveryAnalytics.Report] = []
        let analytics = makeAnalytics { batch in uploaded += batch; return .accepted }
        let ids = (0..<110).map { _ in UUID() }
        for id in ids { analytics.record(.started, discoveryID: id) }
        XCTAssertEqual(analytics.pendingEventCount, 100)
        await analytics.flush()
        XCTAssertEqual(uploaded.count, 20)
        XCTAssertEqual(uploaded.first?.discoveryID, ids[10])
        XCTAssertEqual(analytics.pendingEventCount, 80)
    }

    func testOfflineRetriesAreBoundedAndPreserveEventIdentity() async {
        enableConsent()
        var attempts: [UUID] = []
        let analytics = makeAnalytics { batch in attempts.append(batch[0].id); return .retry }
        analytics.record(.started, discoveryID: UUID())
        await analytics.flush()
        await analytics.flush()
        XCTAssertEqual(analytics.pendingEventCount, 1)
        await analytics.flush()
        XCTAssertEqual(analytics.pendingEventCount, 0)
        XCTAssertEqual(attempts.count, 3)
        XCTAssertEqual(Set(attempts).count, 1, "Retries must be deduplicated by the server")
    }

    func testOptOutPurgesPendingEventsBeforeUpload() async {
        enableConsent()
        var uploads = 0
        let analytics = makeAnalytics { _ in uploads += 1; return .accepted }
        analytics.record(.adImpression, discoveryID: UUID(), adVisible: true)
        defaults.set(false, forKey: AppDiagnosticsReporter.consentDefaultsKey)
        analytics.setCollectionEnabled(false)
        await analytics.flush()
        XCTAssertEqual(analytics.pendingEventCount, 0)
        XCTAssertEqual(uploads, 0)
    }

    func testConsentIsRecheckedBeforeUploadingEvenWithoutSettingsCallback() async {
        enableConsent()
        let analytics = makeAnalytics { _ in XCTFail("Must not upload after opt-out"); return .accepted }
        analytics.record(.started, discoveryID: UUID())
        defaults.set(false, forKey: AppDiagnosticsReporter.consentDefaultsKey)
        await analytics.flush()
        XCTAssertEqual(analytics.pendingEventCount, 0)
    }

    func testTypedPayloadBoundsDurationAndKeepsRevenueDecimalPrecision() async throws {
        enableConsent()
        var reports: [DiscoveryAnalytics.Report] = []
        let analytics = makeAnalytics { batch in reports = batch; return .accepted }
        let discoveryID = UUID()
        analytics.record(.completed, discoveryID: discoveryID, duration: 2.7124)
        analytics.record(.completed, discoveryID: discoveryID, duration: .infinity)
        analytics.record(.failed, discoveryID: discoveryID, duration: 9_999, code: Int.max)
        analytics.record(.adRevenue, discoveryID: discoveryID, revenue: Decimal(string: "0.000001"), currency: "USD", precision: 3)
        analytics.record(.adRevenue, discoveryID: discoveryID, revenue: -1, currency: "USD", precision: 3)
        await analytics.flush()
        XCTAssertEqual(reports.count, 4)
        XCTAssertEqual(reports[0].durationMilliseconds, 2712)
        XCTAssertNil(reports[1].durationMilliseconds)
        XCTAssertEqual(reports[2].durationMilliseconds, 3_600_000)
        XCTAssertEqual(reports[2].code, 100_000)
        XCTAssertEqual(reports[3].revenue, "0.000001")
        XCTAssertEqual(reports[3].currency, "USD")
        let encoded = try JSONEncoder().encode(reports[3])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["id", "discoveryID", "event", "capturedAt", "adVisible", "revenue", "currency", "precision"])
    }

    func testNonRevenueEventsDiscardAccidentalRevenueArguments() async {
        enableConsent()
        var reports: [DiscoveryAnalytics.Report] = []
        let analytics = makeAnalytics { batch in reports = batch; return .accepted }
        analytics.record(.started, discoveryID: UUID(), revenue: 1, currency: "USD", precision: 3)
        await analytics.flush()
        XCTAssertNil(reports.first?.revenue)
        XCTAssertNil(reports.first?.currency)
        XCTAssertNil(reports.first?.precision)
    }

    private func enableConsent() {
        defaults.set(true, forKey: AppDiagnosticsReporter.consentDefaultsKey)
    }

    private func makeAnalytics(_ uploader: @escaping DiscoveryAnalytics.Uploader) -> DiscoveryAnalytics {
        DiscoveryAnalytics(defaults: defaults, automaticallyUpload: false, uploader: uploader)
    }
}
