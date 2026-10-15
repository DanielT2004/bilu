import UIKit
import XCTest
@testable import bilu

@MainActor
final class LoadingAdTests: XCTestCase {
    private var harness: LoadingAdHarness!

    override func setUp() async throws {
        harness = try LoadingAdHarness()
    }

    override func tearDown() async throws {
        harness.removeDefaults()
        harness = nil
    }

    func testQuickCompletionCancelsGraceWithoutRequestingAnAd() async throws {
        let grace = ManualAdGrace()
        defer { grace.releaseAll() }
        let controller = harness.controller(wait: grace.wait)
        controller.begin(id: UUID())
        controller.prepare(width: 390, root: harness.root)
        try await eventually { grace.pendingCount == 1 }
        XCTAssertEqual(grace.delays, [1])

        harness.advance(0.2)
        controller.finish(.completed)
        grace.releaseAll()
        await settle()
        controller.resultsArrived()
        controller.resultsArrived()

        XCTAssertTrue(harness.banners.isEmpty)
        XCTAssertNil(controller.bannerView)
        XCTAssertEqual(harness.count(.adRequested), 0)
        XCTAssertEqual(harness.count(.resultsArrived), 1)
        XCTAssertEqual(try XCTUnwrap(harness.events.first { $0.event == .completed }?.duration), 0.2, accuracy: 0.001)
    }

    func testLoadedBannerDeduplicatesImpressionsRevenueAndResultsArrival() async throws {
        let controller = harness.controller()
        let id = UUID()
        controller.begin(id: id)
        controller.prepare(width: 900, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        let banner = try XCTUnwrap(harness.banners.first)
        XCTAssertEqual(banner.size.width, 600, "Wide iPad layouts must retain a bounded ad width")
        XCTAssertTrue(banner.view.isHidden)
        XCTAssertFalse(controller.isLoaded)
        controller.prepare(width: 900, root: harness.root)
        await settle()
        XCTAssertEqual(banner.loadCount, 1)

        banner.send(.loaded)
        banner.send(.impression)
        banner.send(.impression)
        banner.send(.revenue(Decimal(string: "0.014") ?? 0, "USD", 1))
        banner.send(.revenue(99, "USD", 1))
        XCTAssertFalse(banner.view.isHidden)
        XCTAssertTrue(controller.isLoaded)
        XCTAssertTrue(controller.hadImpression)
        XCTAssertEqual(harness.count(.adRequested), 1)
        XCTAssertEqual(harness.count(.adImpression), 1)
        XCTAssertEqual(harness.count(.adRevenue), 1)
        let revenue = try XCTUnwrap(harness.events.first { $0.event == .adRevenue })
        XCTAssertEqual(revenue.revenue, Decimal(string: "0.014"))
        XCTAssertEqual(revenue.currency, "USD")
        XCTAssertEqual(revenue.precision, 1)
        XCTAssertEqual(revenue.id, id)

        harness.advance(7)
        controller.finish(.completed)
        controller.resultsArrived()
        controller.resultsArrived()
        XCTAssertEqual(banner.disposeCount, 1)
        XCTAssertNil(controller.bannerView)
        XCTAssertFalse(controller.isLoaded)
        XCTAssertEqual(harness.count(.resultsArrived), 1)
        XCTAssertEqual(harness.events.first { $0.event == .completed }?.duration, 7)
        XCTAssertEqual(harness.events.first { $0.event == .resultsArrived }?.adVisible, true)
    }

    func testCancelledGraceCannotClearNewDiscoveryPreparation() async throws {
        let grace = ManualAdGrace()
        defer { grace.releaseAll() }
        let controller = harness.controller(wait: grace.wait)
        controller.begin(id: UUID())
        controller.prepare(width: 390, root: harness.root)
        try await eventually { grace.pendingCount == 1 }
        controller.finish(.cancelled)
        controller.begin(id: UUID())
        controller.prepare(width: 390, root: harness.root)
        try await eventually { grace.pendingCount == 2 }
        grace.releaseFirst()
        await settle()
        controller.prepare(width: 390, root: harness.root)
        await settle()
        XCTAssertEqual(grace.delays.count, 2, "Old cleanup must not erase the new pending request")
        grace.releaseAll()
        try await eventually { self.harness.banners.count == 1 }
        XCTAssertEqual(harness.count(.adRequested), 1)
        controller.finish(.completed)
    }

    func testRotationDuringGraceUsesLatestAvailableWidth() async throws {
        let grace = ManualAdGrace()
        defer { grace.releaseAll() }
        let controller = harness.controller(wait: grace.wait)
        controller.begin(id: UUID())
        controller.prepare(width: 700, root: harness.root)
        try await eventually { grace.pendingCount == 1 }
        controller.prepare(width: 350, root: harness.root)
        grace.releaseAll()
        try await eventually { self.harness.banners.count == 1 }
        XCTAssertEqual(harness.banners[0].size.width, 350)
        controller.prepare(width: 320, root: harness.root)
        XCTAssertNil(controller.bannerView, "A rotated banner cannot extend beyond its available space")
        XCTAssertEqual(harness.banners[0].disposeCount, 1)
        controller.finish(.completed)
    }

    func testAdFailureDisposesCreativeAndPersistsCooldown() async throws {
        let controller = harness.controller()
        controller.begin(id: UUID())
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        let banner = try XCTUnwrap(harness.banners.first)
        banner.send(.failed(3))
        banner.sendLate(.loaded)

        XCTAssertNil(controller.bannerView)
        XCTAssertFalse(controller.isLoaded)
        XCTAssertEqual(banner.disposeCount, 1)
        XCTAssertEqual(harness.events.first { $0.event == .adFailed }?.code, 3)
        XCTAssertEqual(harness.count(.completed), 0, "An ad failure cannot finish AI discovery")
        harness.advance(599)
        XCTAssertFalse(harness.frequency().canRequest)
        harness.advance(1)
        XCTAssertTrue(harness.frequency().canRequest)
        controller.finish(.completed)
        XCTAssertEqual(harness.count(.completed), 1)
    }

    func testCancelledDiscoveryIgnoresOldCallbacksDuringNewDiscovery() async throws {
        let controller = harness.controller()
        let firstID = UUID()
        controller.begin(id: firstID)
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        let oldBanner = harness.banners[0]
        controller.finish(.cancelled)
        harness.advance(120)
        let newID = UUID()
        controller.begin(id: newID)
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 2 }
        let newBanner = harness.banners[1]

        oldBanner.sendLate(.loaded)
        oldBanner.sendLate(.impression)
        oldBanner.sendLate(.failed(99))
        oldBanner.sendLate(.revenue(2, "USD", 1))
        XCTAssertFalse(controller.isLoaded)
        XCTAssertFalse(controller.hadImpression)
        XCTAssertTrue(controller.bannerView === newBanner.view)
        XCTAssertEqual(controller.discoveryID, newID)
        XCTAssertEqual(harness.count(.adFailed), 0)
        XCTAssertEqual(harness.count(.adImpression), 0)
        XCTAssertEqual(harness.count(.adRevenue), 0)
        newBanner.send(.loaded)
        XCTAssertTrue(controller.isLoaded)
        controller.finish(.completed)
    }

    func testBackgroundPermanentlySuppressesBannerForCurrentDiscovery() async throws {
        let controller = harness.controller()
        controller.begin(id: UUID())
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        let banner = harness.banners[0]
        banner.send(.loaded)
        controller.background()
        banner.sendLate(.loaded)
        harness.advance(120)
        controller.prepare(width: 390, root: harness.root)
        await settle()

        XCTAssertEqual(harness.banners.count, 1)
        XCTAssertEqual(harness.count(.backgrounded), 1)
        XCTAssertNil(controller.bannerView)
        XCTAssertNotNil(controller.discoveryID, "Backgrounding the ad must not cancel AI work")
        controller.finish(.completed)
    }

    func testEligibilityDenialAndRevocationPreventAdDelivery() async throws {
        var eligible = false
        let controller = harness.controller(eligible: { eligible })
        controller.begin(id: UUID())
        controller.prepare(width: 390, root: harness.root)
        await settle()
        XCTAssertTrue(harness.banners.isEmpty, "Consent/subscription eligibility must gate requests")

        eligible = true
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        eligible = false
        harness.banners[0].send(.loaded)
        XCTAssertNil(controller.bannerView)
        XCTAssertFalse(controller.isLoaded)
        XCTAssertEqual(harness.banners[0].disposeCount, 1)
        controller.finish(.completed)
    }

    func testVerifiedFreeWalletPermitsPassiveAdvertising() {
        for state: PurchaseState in [.idle, .purchased, .restored] {
            XCTAssertTrue(AdvertisingConfiguration.permitsLoadingAds(
                wallet: wallet(plan: "free"), hasPendingSync: false, purchaseState: state
            ))
        }
    }

    func testProRemainsAdFreeEvenWhenProSalesAreDisabled() {
        for salesEnabled in [false, true] {
            XCTAssertFalse(AdvertisingConfiguration.permitsLoadingAds(
                wallet: wallet(plan: "pro", salesEnabled: salesEnabled),
                hasPendingSync: false, purchaseState: .idle
            ))
        }
    }

    func testUnknownEntitlementFailsClosedForAdvertising() {
        XCTAssertFalse(AdvertisingConfiguration.permitsLoadingAds(
            wallet: nil, hasPendingSync: false, purchaseState: .idle
        ))
        XCTAssertFalse(AdvertisingConfiguration.permitsLoadingAds(
            wallet: wallet(plan: "unrecognized-plan"), hasPendingSync: false, purchaseState: .idle
        ))
    }

    func testPendingPurchasesSuppressAdvertisingUntilEntitlementsSettle() {
        for state: PurchaseState in [.purchasing, .pendingApproval] {
            XCTAssertFalse(AdvertisingConfiguration.permitsLoadingAds(
                wallet: wallet(plan: "free"), hasPendingSync: false, purchaseState: state
            ))
        }
        for state: PurchaseState in [.idle, .syncPending] {
            XCTAssertFalse(AdvertisingConfiguration.permitsLoadingAds(
                wallet: wallet(plan: "free"), hasPendingSync: true, purchaseState: state
            ))
        }
    }

    func testExplicitSuppressionAndNarrowLayoutNeverRequest() async {
        let controller = harness.controller()
        controller.begin(id: UUID(), allowAds: false)
        controller.prepare(width: 390, root: harness.root)
        await settle()
        XCTAssertTrue(harness.banners.isEmpty)
        controller.finish(.completed)
        controller.begin(id: UUID())
        controller.prepare(width: 319, root: harness.root)
        await settle()
        XCTAssertTrue(harness.banners.isEmpty)
        controller.finish(.completed)
    }

    func testFrequencyPersistsIntervalAndUTCDailyCapAcrossRelaunch() {
        let frequency = harness.frequency()
        XCTAssertTrue(frequency.canRequest)
        frequency.recordRequest()
        XCTAssertFalse(harness.frequency().canRequest)
        harness.advance(119)
        XCTAssertFalse(harness.frequency().canRequest)
        harness.advance(1)
        XCTAssertTrue(harness.frequency().canRequest)
        harness.frequency().recordRequest()
        harness.advance(120)
        harness.frequency().recordRequest()
        harness.advance(120)
        XCTAssertFalse(harness.frequency().canRequest, "Three attempts exhaust the daily cap")

        let nextUTCDay = (floor(harness.now.timeIntervalSince1970 / 86_400) + 1) * 86_400
        harness.now = Date(timeIntervalSince1970: nextUTCDay)
        XCTAssertTrue(harness.frequency().canRequest)
        harness.frequency().recordRequest()
        XCTAssertFalse(harness.frequency().canRequest)
    }

    func testDiscoveryErrorCooldownCannotShortenExistingAdFailureCooldown() {
        harness.frequency().suppressAfterError(adFailure: true)
        harness.advance(10)
        harness.frequency().suppressAfterError(adFailure: false)
        harness.advance(589)
        XCTAssertFalse(harness.frequency().canRequest)
        harness.advance(1)
        XCTAssertTrue(harness.frequency().canRequest)
        harness.frequency().suppressAfterError(adFailure: false)
        harness.advance(299)
        XCTAssertFalse(harness.frequency().canRequest)
        harness.advance(1)
        XCTAssertTrue(harness.frequency().canRequest)
    }

    func testPassiveAdNeverChangesFreeOrRewardedAllowance() async throws {
        let allowance = harness.allowance()
        allowance.grantReward(token: "server-verified-token")
        let controller = harness.controller()
        controller.begin(id: UUID())
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        harness.banners[0].send(.loaded)
        harness.banners[0].send(.impression)
        harness.banners[0].send(.revenue(1, "USD", 1))
        controller.finish(.completed)

        let restored = harness.allowance()
        XCTAssertEqual(restored.remainingFreeDiscoveries, 1)
        XCTAssertEqual(restored.rewardedAccessToken, "server-verified-token")
    }

    func testConcurrentSubmitsStartOneAIRequestAndOneDiscovery() async throws {
        let ai = ControlledRecommendations()
        let controller = harness.controller()
        let model = home(controller: controller, ai: ai)
        let first = Task { await model.submitSurvey() }
        defer { first.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        await model.submitSurvey()
        XCTAssertEqual(ai.calls.count, 1)
        XCTAssertEqual(harness.count(.started), 1)
        ai.finish(0, with: Self.success("First kitchen"))
        await first.value
        XCTAssertEqual(model.step, .reveal)
        XCTAssertEqual(model.recommendations.map(\.name), ["First kitchen"])
    }

    func testCancelledOldAIResponseCannotRevealOverNewSearch() async throws {
        let ai = ControlledRecommendations()
        let controller = harness.controller()
        let model = home(controller: controller, ai: ai)
        let oldTask = Task { await model.submitSurvey() }
        defer { oldTask.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        model.cancelDiscovery()
        let newTask = Task { await model.submitSurvey() }
        defer { newTask.cancel() }
        try await eventually { ai.calls.count == 2 }
        ai.finish(0, with: Self.success("Old kitchen"))
        await oldTask.value
        XCTAssertEqual(model.step, .loading)
        XCTAssertTrue(model.recommendations.isEmpty)
        XCTAssertEqual(harness.count(.completed), 0)
        ai.finish(1, with: Self.success("New kitchen"))
        await newTask.value
        XCTAssertEqual(model.recommendations.map(\.name), ["New kitchen"])
        XCTAssertEqual(harness.count(.cancelled), 1)
        XCTAssertEqual(harness.count(.completed), 1)
    }

    func testAIResultsArriveWhileAdRequestRemainsUnresolved() async throws {
        let ai = ControlledRecommendations()
        let controller = harness.controller()
        let model = home(controller: controller, ai: ai)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        let banner = harness.banners[0]
        XCTAssertFalse(controller.isLoaded)
        ai.finish(0, with: Self.success("Ready kitchen"))
        try await eventually { model.step == .reveal }
        await task.value

        XCTAssertEqual(model.recommendations.map(\.name), ["Ready kitchen"])
        XCTAssertEqual(banner.disposeCount, 1)
        banner.sendLate(.loaded)
        banner.sendLate(.impression)
        XCTAssertNil(controller.bannerView)
        XCTAssertEqual(harness.count(.adImpression), 0)
        XCTAssertEqual(harness.count(.completed), 1)
    }

    func testSlowAIContinuesAfterAdFailureAndCompletesIndependently() async throws {
        let ai = ControlledRecommendations()
        let controller = harness.controller()
        let model = home(controller: controller, ai: ai)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        controller.prepare(width: 390, root: harness.root)
        try await eventually { self.harness.banners.count == 1 }
        harness.banners[0].send(.failed(2))
        harness.advance(12)
        XCTAssertEqual(model.step, .loading)
        XCTAssertNil(model.lastSearchFailure)
        XCTAssertEqual(ai.calls.count, 1)
        XCTAssertEqual(harness.count(.completed), 0)
        ai.finish(0, with: Self.success("Slow kitchen"))
        await task.value
        XCTAssertEqual(model.step, .reveal)
        XCTAssertEqual(model.recommendations.map(\.name), ["Slow kitchen"])
        XCTAssertEqual(harness.events.first { $0.event == .completed }?.duration, 12)
        XCTAssertEqual(harness.count(.adFailed), 1)
    }

    func testFastAIDoesNotWaitForGraceAndConsumesOnlyItsFreeDiscovery() async throws {
        let grace = ManualAdGrace()
        defer { grace.releaseAll() }
        let ai = ControlledRecommendations()
        let controller = harness.controller(wait: grace.wait)
        let allowance = harness.allowance()
        allowance.grantReward(token: "still-unspent-reward")
        let model = home(controller: controller, ai: ai, allowance: allowance, commerce: false)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        controller.prepare(width: 390, root: harness.root)
        try await eventually { grace.pendingCount == 1 }
        ai.finish(0, with: Self.emptySuccess)
        try await eventually { model.step == .reveal }
        await task.value
        grace.releaseAll()
        await settle()
        XCTAssertTrue(harness.banners.isEmpty)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 0)
        XCTAssertEqual(allowance.rewardedAccessToken, "still-unspent-reward")
        XCTAssertNil(ai.calls[0].token)
    }

    func testRewardedDiscoverySuppressesPassiveAdAndConsumesVerifiedTokenOnce() async throws {
        let ai = ControlledRecommendations()
        let controller = harness.controller()
        let allowance = harness.allowance()
        allowance.recordDiscovery(usedRewardToken: nil)
        allowance.grantReward(token: "verified-single-use")
        let model = home(controller: controller, ai: ai, allowance: allowance, commerce: false)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        controller.prepare(width: 390, root: harness.root)
        await settle()
        XCTAssertTrue(harness.banners.isEmpty)
        XCTAssertEqual(ai.calls[0].token, "verified-single-use")
        ai.finish(0, with: Self.emptySuccess)
        await task.value
        XCTAssertFalse(allowance.hasRewardedDiscovery)
        XCTAssertFalse(allowance.canRunDiscovery)
        await model.submitSurvey()
        XCTAssertTrue(model.showingRewardGate)
        XCTAssertEqual(ai.calls.count, 1)
    }

    func testRejectedRewardReopensGateWithNoticeAndDropsToken() async throws {
        let ai = ControlledRecommendations()
        let allowance = harness.allowance()
        allowance.recordDiscovery(usedRewardToken: nil)
        allowance.grantReward(token: "unverified-reward")
        let model = home(controller: harness.controller(), ai: ai, allowance: allowance, commerce: false)
        model.rewardUnlocked()
        let task = Task { await model.rewardGateDismissed() }
        defer { task.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        XCTAssertEqual(ai.calls[0].token, "unverified-reward")
        ai.finish(0, with: VibeFetchOutcome(result: Self.emptySuccess.result, failure: .rewardRequired))
        await task.value
        XCTAssertTrue(model.showingRewardGate)
        XCTAssertNotNil(model.rewardGateNotice)
        XCTAssertFalse(allowance.hasRewardedDiscovery)
        XCTAssertNotEqual(model.step, .loading)

        // Closing the gate without earning a new reward must not start a search.
        await model.rewardGateDismissed()
        XCTAssertEqual(ai.calls.count, 1)
        model.rewardUnlocked()
        XCTAssertNil(model.rewardGateNotice)
    }

    func testFailedAIPreservesAllowanceAndSuppressesErrorRetries() async throws {
        let ai = ControlledRecommendations()
        let controller = harness.controller()
        let allowance = harness.allowance()
        let model = home(controller: controller, ai: ai, allowance: allowance, commerce: false)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); ai.finishAll() }
        try await eventually { ai.calls.count == 1 }
        ai.finish(0, with: VibeFetchOutcome(result: Self.emptySuccess.result, failure: .transportError))
        await task.value
        XCTAssertEqual(model.lastSearchFailure, .transportError)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
        XCTAssertEqual(harness.count(.failed), 1)
        XCTAssertFalse(harness.frequency().canRequest)
    }

    func testAutomaticTrendingDoesNotStartAIOrConsumeAllowance() async {
        let ai = ControlledRecommendations()
        let allowance = harness.allowance()
        let controller = harness.controller()
        let model = home(controller: controller, ai: ai, allowance: allowance, commerce: false)
        model.selection.location = "Los Angeles"
        await model.loadTrendingIfNeeded()
        await model.loadTrendingIfNeeded()
        XCTAssertTrue(ai.calls.isEmpty)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
        XCTAssertFalse(model.isLoadingTrending)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testEnrichmentTimeoutRevealsBeforeSlowProviderCompletes() async throws {
        let enrichment = ControlledEnrichment()
        let controller = harness.controller()
        let model = enrichingHome(controller: controller, enrichment: enrichment, timeout: 0)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); enrichment.finishAll() }
        try await eventually { enrichment.startedCount == 1 }
        try await eventually { model.step == .reveal && model.isEnriching }
        await task.value

        XCTAssertTrue(model.recommendations.isEmpty, "Unverified Phase-1 cards must stay hidden")
        XCTAssertEqual(enrichment.pendingCount, 1, "The readiness cap must return before Places finishes")
        XCTAssertTrue(enrichment.cancelled.isEmpty, "Only the intended fallback provider remains alive")
        XCTAssertEqual(harness.count(.completed), 1)
        enrichment.finish(0, with: Self.success("Verified kitchen").result.recommendations)
        try await eventually { model.recommendations.first?.name == "Verified kitchen" }
        XCTAssertFalse(model.isEnriching)
        XCTAssertEqual(harness.count(.completed), 1, "Late enrichment cannot complete the discovery twice")
    }

    func testNewDiscoveryCancelsFallbackAndRejectsItsLateEnrichment() async throws {
        let enrichment = ControlledEnrichment()
        let controller = harness.controller()
        let allowance = harness.allowance()
        let model = enrichingHome(controller: controller, enrichment: enrichment, allowance: allowance, timeout: 0)
        let first = Task { await model.submitSurvey() }
        defer { first.cancel(); enrichment.finishAll() }
        try await eventually { model.step == .reveal && model.isEnriching }
        await first.value

        allowance.grantReward(token: "verified-next-search")
        let second = Task { await model.submitSurvey() }
        defer { second.cancel() }
        try await eventually { enrichment.startedCount == 2 && model.step == .reveal && model.isEnriching }
        await second.value
        try await eventually { enrichment.cancelled.contains(0) }
        enrichment.finish(0, with: Self.success("Stale kitchen").result.recommendations)
        await settle()
        XCTAssertTrue(model.recommendations.isEmpty)
        XCTAssertTrue(model.isEnriching, "Old cleanup cannot clear the current discovery's loading state")
        enrichment.finish(1, with: Self.success("Current kitchen").result.recommendations)
        try await eventually { model.recommendations.first?.name == "Current kitchen" }
        XCTAssertFalse(model.isEnriching)
    }

    func testCancellationExitsReadinessRaceWithoutWaitingForProvider() async throws {
        let enrichment = ControlledEnrichment()
        let controller = harness.controller()
        let model = enrichingHome(controller: controller, enrichment: enrichment, timeout: 60)
        var submissionReturned = false
        let task = Task {
            await model.submitSurvey()
            submissionReturned = true
        }
        defer { task.cancel(); enrichment.finishAll() }
        try await eventually { enrichment.startedCount == 1 }
        model.cancelDiscovery()
        try await eventually { submissionReturned && enrichment.cancelled.contains(0) }
        XCTAssertEqual(enrichment.pendingCount, 1, "A provider ignoring cancellation must not trap the UI")
        XCTAssertEqual(model.step, .foodFeeling)
        XCTAssertFalse(model.isEnriching)
        enrichment.finish(0, with: Self.success("Cancelled kitchen").result.recommendations)
        await settle()
        XCTAssertTrue(model.recommendations.isEmpty)
        XCTAssertEqual(harness.count(.cancelled), 1)
        XCTAssertEqual(harness.count(.completed), 0)
    }

    func testFastEnrichmentWinsReadinessRaceWithoutWaitingForTimer() async throws {
        let enrichment = ControlledEnrichment()
        let controller = harness.controller()
        let model = enrichingHome(controller: controller, enrichment: enrichment, timeout: 60)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); enrichment.finishAll() }
        try await eventually { enrichment.startedCount == 1 }
        enrichment.finish(0, with: Self.success("Fast verified kitchen").result.recommendations)
        try await eventually { model.step == .reveal }
        await task.value
        XCTAssertEqual(model.recommendations.map(\.name), ["Fast verified kitchen"])
        XCTAssertFalse(model.isEnriching)
        XCTAssertEqual(harness.count(.completed), 1)
    }

    private func enrichingHome(controller: LoadingAdController, enrichment: ControlledEnrichment,
                               allowance: DiscoveryAllowance? = nil, timeout: TimeInterval) -> HomeViewModel {
        let model = HomeViewModel(loadingAds: controller, allowance: allowance ?? harness.allowance(),
            commerceEnabled: { false },
            fetchRecommendations: { _, _ in Self.success("Unverified candidate", isOpen: nil) },
            enrich: enrichment.run, readinessTimeout: timeout)
        model.reduceMotionPreference = true
        model.detectedLocation = "Los Angeles"
        return model
    }

    private func home(controller: LoadingAdController, ai: ControlledRecommendations,
                      allowance: DiscoveryAllowance? = nil, commerce: Bool = true) -> HomeViewModel {
        let model = HomeViewModel(loadingAds: controller, allowance: allowance ?? harness.allowance(),
            commerceEnabled: { commerce }, fetchRecommendations: ai.fetch,
            enrich: { recommendations, _, _ in recommendations })
        model.reduceMotionPreference = true
        model.detectedLocation = "Los Angeles"
        return model
    }

    private func wallet(plan: String, salesEnabled: Bool = false) -> PurchaseWallet {
        let accountID = UUID()
        return PurchaseWallet(accountId: accountID, requiresSignIn: false,
            appAccountToken: accountID, plan: plan, periodStart: harness.now,
            periodEnd: harness.now.addingTimeInterval(86_400),
            included: .init(explore: 1, tiktok: 1), purchased: .init(explore: 0, tiktok: 0),
            commerceEnabled: salesEnabled, proEnabled: salesEnabled)
    }

    private static var emptySuccess: VibeFetchOutcome {
        VibeFetchOutcome(result: VibeResult(recommendations: [], groundingPlaces: [], relaxed: false), failure: .noMatches)
    }

    private static func success(_ name: String, isOpen: Bool? = true) -> VibeFetchOutcome {
        let recommendation = Recommendation(name: name, dish: "Lunch", image: nil,
            explanation: "Test result", mapsUrl: "", latitude: nil, longitude: nil,
            rating: nil, reviewCount: nil, isOpen: isOpen, photos: nil, address: nil,
            phone: nil, website: nil, parking: nil, placeId: name, photoRefs: nil, reviews: nil)
        return VibeFetchOutcome(result: VibeResult(recommendations: [recommendation], groundingPlaces: [], relaxed: false), failure: nil)
    }

    private func settle() async {
        for _ in 0..<30 { await Task.yield() }
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected asynchronous state did not arrive", file: file, line: line)
        throw LoadingAdTestFailure.missingState
    }
}

private enum LoadingAdTestFailure: Error { case missingState }

@MainActor
private final class LoadingAdHarness {
    struct Event {
        let event: DiscoveryAnalytics.Event
        let id: UUID
        let duration: TimeInterval?
        let adVisible: Bool
        let code: Int?
        let revenue: Decimal?
        let currency: String?
        let precision: Int?
    }

    let suite = "LoadingAdTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let root = UIViewController()
    var now = Date(timeIntervalSince1970: 1_790_000_000)
    var banners: [FakeLoadingBanner] = []
    var events: [Event] = []

    init() throws { defaults = try XCTUnwrap(UserDefaults(suiteName: suite)) }
    func removeDefaults() { defaults.removePersistentDomain(forName: suite) }
    func advance(_ duration: TimeInterval) { now.addTimeInterval(duration) }
    func count(_ event: DiscoveryAnalytics.Event) -> Int { events.filter { $0.event == event }.count }
    func frequency() -> LoadingAdFrequencyStore { LoadingAdFrequencyStore(defaults: defaults, now: { self.now }) }
    func allowance() -> DiscoveryAllowance { DiscoveryAllowance(defaults: defaults, now: { self.now }) }

    func controller(eligible: @escaping () -> Bool = { true },
                    wait: @escaping (TimeInterval) async throws -> Void = { _ in }) -> LoadingAdController {
        LoadingAdController(frequency: frequency(), eligible: eligible,
            factory: { width, _ in
                let banner = FakeLoadingBanner(width: width)
                self.banners.append(banner)
                return banner
            }, record: { event, id, duration, visible, code, revenue, currency, precision in
                self.events.append(Event(event: event, id: id, duration: duration, adVisible: visible,
                    code: code, revenue: revenue, currency: currency, precision: precision))
            }, uptime: { self.now.timeIntervalSince1970 }, wait: wait, observeEnvironment: false)
    }
}

@MainActor
private final class FakeLoadingBanner: LoadingBannerAd {
    let view = UIView()
    let size: CGSize
    var onEvent: ((LoadingBannerEvent) -> Void)?
    private var capturedCallback: ((LoadingBannerEvent) -> Void)?
    private(set) var loadCount = 0
    private(set) var disposeCount = 0

    init(width: CGFloat) { size = CGSize(width: width, height: 60) }
    func load() { loadCount += 1; capturedCallback = onEvent }
    func dispose() { disposeCount += 1; onEvent = nil; view.isHidden = true }
    func send(_ event: LoadingBannerEvent) { onEvent?(event) }
    func sendLate(_ event: LoadingBannerEvent) { capturedCallback?(event) }
}

@MainActor
private final class ManualAdGrace {
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private(set) var delays: [TimeInterval] = []
    var pendingCount: Int { continuations.count }

    func wait(_ delay: TimeInterval) async throws {
        delays.append(delay)
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }

    func releaseFirst() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

@MainActor
private final class ControlledRecommendations {
    struct Call { let selection: VibeSelection; let token: String? }
    private(set) var calls: [Call] = []
    private var continuations: [Int: CheckedContinuation<VibeFetchOutcome, Never>] = [:]

    func fetch(_ selection: VibeSelection, _ token: String?) async -> VibeFetchOutcome {
        let index = calls.count
        calls.append(Call(selection: selection, token: token))
        return await withCheckedContinuation { continuations[index] = $0 }
    }

    func finish(_ index: Int, with outcome: VibeFetchOutcome) {
        continuations.removeValue(forKey: index)?.resume(returning: outcome)
    }

    func finishAll() {
        let outcome = VibeFetchOutcome(result: VibeResult(recommendations: [], groundingPlaces: [], relaxed: false), failure: .transportError)
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume(returning: outcome) }
    }
}

@MainActor
private final class ControlledEnrichment {
    private(set) var startedCount = 0
    private(set) var cancelled: Set<Int> = []
    private var continuations: [Int: CheckedContinuation<[Recommendation], Never>] = [:]
    var pendingCount: Int { continuations.count }

    func run(_ recommendations: [Recommendation], _ places: [GroundingPlace], _ location: String) async -> [Recommendation] {
        let index = startedCount
        startedCount += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuations[index] = $0 }
        } onCancel: {
            Task { @MainActor in self.cancelled.insert(index) }
        }
    }

    func finish(_ index: Int, with recommendations: [Recommendation]) {
        continuations.removeValue(forKey: index)?.resume(returning: recommendations)
    }

    func finishAll() {
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume(returning: []) }
    }
}
