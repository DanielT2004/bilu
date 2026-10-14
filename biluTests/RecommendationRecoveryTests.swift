import Foundation
import XCTest
@testable import bilu

/// Release gates: every recommendation failure shows distinct copy, keeps or
/// spends the allowance correctly, and recovers without leaving the spinner up.
@MainActor
final class RecommendationRecoveryTests: XCTestCase {
    private let suite = "RecommendationRecoveryTests.\(UUID().uuidString)"
    private var defaults: UserDefaults!
    private var allowance: DiscoveryAllowance!

    override func setUp() async throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        allowance = DiscoveryAllowance(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        allowance = nil
    }

    // MARK: - Copy

    func testEveryFailureHasDistinctCopy() {
        let failures: [SearchFailure] = [.noMatches, .rewardRequired, .purchaseRequired, .pendingDiscovery,
            .capacityUnavailable, .usageLimitExceeded, .timedOut, .offline, .sessionRejected, .transportError]
        let copies = failures.map(SearchRecoveryCopy.init(failure:))
        XCTAssertEqual(Set(copies.map(\.title)).count, failures.count, "Titles must be distinct")
        XCTAssertEqual(Set(copies.map(\.message)).count, failures.count, "Messages must be distinct")
        XCTAssertEqual(Set(copies.map(\.systemImage)).count, failures.count, "Icons must be distinct")
        for copy in copies { XCTAssertFalse(copy.actionTitle.isEmpty, "\(copy.title) needs a recovery action") }
    }

    // MARK: - HomeViewModel recovery, one per failure type

    func testNoMatchSpendsFreeDiscoveryAndAdjustVibeKeepsChoices() async {
        let ai = ScriptedRecommendations([.failure(.noMatches)])
        let model = home(ai)
        model.selection.foodFeelings = ["Pastry"]
        model.step = .location
        await model.submitSurvey()

        assertRecoveryCard(model, failure: .noMatches, title: "Nothing matched, yet", action: .adjustVibe)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 0, "A completed empty search was billed server-side")

        await model.performRecoveryAction()
        XCTAssertEqual(model.step, .location, "Adjusting returns to the step that submitted the search")
        XCTAssertEqual(model.selection.foodFeelings, ["Pastry"])
        XCTAssertNil(model.lastSearchFailure)
        XCTAssertEqual(ai.calls.count, 1, "Adjusting never starts a new paid search")
    }

    func testTimeoutKeepsFreeDiscoveryAndRetryReveals() async {
        await assertRetryRecovers(.timedOut, title: "Search took too long")
    }

    func testCapacityKeepsFreeDiscoveryAndRetryReveals() async {
        await assertRetryRecovers(.capacityUnavailable, title: "Search is at capacity")
    }

    func testOfflineKeepsFreeDiscoveryAndRetryReveals() async {
        await assertRetryRecovers(.offline, title: "You're offline")
    }

    func testRejectedSessionKeepsFreeDiscoveryAndRetryReveals() async {
        await assertRetryRecovers(.sessionRejected, title: "Couldn't verify this device")
    }

    func testTransportErrorKeepsFreeDiscoveryAndRetryReveals() async {
        await assertRetryRecovers(.transportError, title: "Couldn't reach us")
    }

    func testUsageLimitOffersStartOverAndResetsWithoutRetrying() async {
        let ai = ScriptedRecommendations([.failure(.usageLimitExceeded)])
        let model = home(ai)
        model.selection.occasion = "Brunch"
        await model.submitSurvey()

        assertRecoveryCard(model, failure: .usageLimitExceeded, title: "Search limit reached", action: .startOver)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1, "The server refunds access when its quota rejects")

        await model.performRecoveryAction()
        XCTAssertEqual(model.step, .feed)
        XCTAssertEqual(model.selection.occasion, "")
        XCTAssertNil(model.lastSearchFailure)
        XCTAssertEqual(ai.calls.count, 1)
    }

    func testRejectedRewardReopensGateWithNoticeAndNeverSticksOnLoading() async {
        allowance.recordDiscovery(usedRewardToken: nil)
        allowance.grantReward(token: "unverified-reward")
        let ai = ScriptedRecommendations([.failure(.rewardRequired)])
        let model = home(ai)
        model.step = .foodFeeling
        model.rewardUnlocked()
        await model.rewardGateDismissed()

        XCTAssertEqual(ai.calls.map(\.token), ["unverified-reward"])
        XCTAssertTrue(model.showingRewardGate)
        XCTAssertEqual(model.rewardGateNotice, "We couldn't verify your ad reward. Watch another ad to try again.")
        XCTAssertEqual(model.step, .foodFeeling, "The gate reopens over the survey, not a stale results card")
        XCTAssertFalse(allowance.hasRewardedDiscovery, "The rejected token is dropped")

        model.showingRewardGate = false
        await model.rewardGateDismissed()
        XCTAssertEqual(ai.calls.count, 1, "Closing the gate without a new reward must not search")
    }

    func testRetryThatHitsRewardGateReturnsToSurveyStep() async {
        let ai = ScriptedRecommendations([.failure(.timedOut), .failure(.rewardRequired)])
        let model = home(ai)
        model.step = .location
        await model.submitSurvey()
        XCTAssertEqual(model.step, .reveal)
        await model.performRecoveryAction()
        XCTAssertTrue(model.showingRewardGate)
        XCTAssertEqual(model.step, .location)
    }

    // MARK: - Forced 401

    func testForced401RefreshesTheSessionOnceAndRetriesTheSameRequest() async {
        let session = FakeSession()
        let server = FakeRecommendationsServer([(401, #"{"code":"INVALID_SESSION"}"#), (200, Self.oneResultJSON)])
        let outcome = await GeminiService.fetchRecommendations(body: Data("{}".utf8), rewardedAccessToken: "reward",
            makeRequest: session.request, invalidateToken: session.invalidate, transport: server.send)

        XCTAssertNil(outcome.failure)
        XCTAssertEqual(outcome.result.recommendations.map(\.name), ["Tartine"])
        XCTAssertEqual(session.invalidated, ["token-1"], "Only the rejected token is dropped, once")
        XCTAssertEqual(server.requests.map { $0.value(forHTTPHeaderField: "Authorization") },
                       ["Bearer token-1", "Bearer token-2"])
        XCTAssertEqual(server.requests.map { $0.value(forHTTPHeaderField: "X-Rewarded-Access-Token") },
                       ["reward", "reward"])
    }

    func testSecond401StopsAfterOneRefreshWithDistinctFailure() async {
        let session = FakeSession()
        let server = FakeRecommendationsServer([(401, "{}"), (401, "{}"), (200, Self.oneResultJSON)])
        let outcome = await GeminiService.fetchRecommendations(body: Data("{}".utf8), rewardedAccessToken: nil,
            makeRequest: session.request, invalidateToken: session.invalidate, transport: server.send)
        XCTAssertEqual(outcome.failure, .sessionRejected)
        XCTAssertEqual(server.requests.count, 2, "No retry loop")
        XCTAssertEqual(session.invalidated, ["token-1"])
    }

    func testInvalidatedTokenRefreshesOnceAndKeepsTheGuestIdentity() async throws {
        let guestID = "11111111-1111-4111-8111-111111111111"
        let storage = RecoveryAuthStorage(data: try JSONSerialization.data(withJSONObject: [
            "accessToken": "stale-access", "refreshToken": "old-refresh",
            "expiresAt": Date().addingTimeInterval(3600).timeIntervalSinceReferenceDate,
            "user": ["id": guestID, "is_anonymous": true],
        ]))
        let refreshed = Data(#"{"access_token":"fresh-access","refresh_token":"new-refresh","expires_in":3600,"user":{"id":"\#(guestID)","is_anonymous":true}}"#.utf8)
        let auth = RecoveryAuthServer(response: refreshed)
        let session = SupabaseAuthSession(storage: storage, transport: { try await auth.send($0) })

        let before = try await session.accessToken()
        XCTAssertEqual(before, "stale-access")
        await session.invalidate(accessToken: "stale-access")
        await session.invalidate(accessToken: "stale-access")
        let after = try await session.accessToken()
        let again = try await session.accessToken()

        XCTAssertEqual(after, "fresh-access")
        XCTAssertEqual(again, "fresh-access")
        let requests = await auth.requests
        XCTAssertEqual(requests.map { $0.url?.query }, ["grant_type=refresh_token"], "Exactly one refresh, no new guest")
        let account = await session.cachedAccount()
        XCTAssertEqual(account?.id.uuidString.lowercased(), guestID)

        // A late invalidate for the replaced token must not discard the fresh one.
        await session.invalidate(accessToken: "stale-access")
        let afterLate = try await session.accessToken()
        XCTAssertEqual(afterLate, "fresh-access")
        let finalRequests = await auth.requests
        XCTAssertEqual(finalRequests.count, 1)
    }

    // MARK: - Error mapping

    func testServerCodesAndNetworkErrorsMapToDistinctFailures() {
        XCTAssertEqual(GeminiService.failure(status: 503, code: "UPSTREAM_CAPACITY"), .capacityUnavailable)
        XCTAssertEqual(GeminiService.failure(status: 429, code: "GLOBAL_BUDGET_EXCEEDED"), .capacityUnavailable)
        XCTAssertEqual(GeminiService.failure(status: 429, code: "USAGE_LIMIT_EXCEEDED"), .usageLimitExceeded)
        XCTAssertEqual(GeminiService.failure(status: 402, code: "REWARDED_AD_REQUIRED"), .rewardRequired)
        XCTAssertEqual(GeminiService.failure(status: 504, code: "UPSTREAM_TIMEOUT"), .timedOut)
        XCTAssertEqual(GeminiService.failure(status: 500, code: nil), .transportError)
        XCTAssertEqual(GeminiService.failure(for: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(GeminiService.failure(for: URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(GeminiService.failure(for: URLError(.timedOut)), .timedOut)
        XCTAssertEqual(GeminiService.failure(for: URLError(.badServerResponse)), .transportError)
        XCTAssertEqual(GeminiService.failure(for: SupabaseAuthError.rejected(400, "refresh_token_not_found")), .sessionRejected)
        XCTAssertEqual(GeminiService.failure(for: SupabaseAuthError.requestFailed(503)), .transportError)
    }

    func testServerTimeoutResponseIsReportedAsTimeout() async {
        let session = FakeSession()
        let server = FakeRecommendationsServer([(504, #"{"code":"UPSTREAM_TIMEOUT"}"#)])
        let outcome = await GeminiService.fetchRecommendations(body: Data("{}".utf8), rewardedAccessToken: nil,
            makeRequest: session.request, invalidateToken: session.invalidate, transport: server.send)
        XCTAssertEqual(outcome.failure, .timedOut)
    }

    // MARK: - Slow responses keep the free discovery

    func testClientWaitsLongerThanTheServerDeadline() async {
        XCTAssertGreaterThanOrEqual(GeminiService.recommendationTimeout,
            GeminiService.serverRecommendationsDeadline + GeminiService.serverPreflightBudget)

        // The fake transport behaves like URLSession: it times out only when the
        // simulated latency exceeds the request's own timeout. A response that
        // lands just after the server's 19 s deadline (plus auth/access checks)
        // must still be accepted rather than dropped while the server bills it.
        let session = FakeSession()
        let server = FakeRecommendationsServer([(200, Self.oneResultJSON)], simulatedLatency: 24)
        let outcome = await GeminiService.fetchRecommendations(body: Data("{}".utf8), rewardedAccessToken: nil,
            makeRequest: session.request, invalidateToken: session.invalidate, transport: server.send)
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(server.requests.first?.timeoutInterval, 30)
    }

    func testSlowSuccessRevealsAndSpendsExactlyOneFreeDiscovery() async throws {
        let ai = ControlledFetch()
        let model = home(fetch: ai.fetch)
        let task = Task { await model.submitSurvey() }
        defer { task.cancel(); ai.finish(with: .failure(.transportError)) }
        try await eventually { ai.isPending }
        // HomeViewModel has no deadline of its own; it waits for the service's
        // 30 s request timeout, which outlasts the server's refunding deadline.
        for _ in 0..<200 { await Task.yield() }
        XCTAssertEqual(model.step, .loading)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)

        ai.finish(with: .success("Slow Bakery"))
        await task.value
        XCTAssertEqual(model.step, .reveal)
        XCTAssertEqual(model.recommendations.map(\.name), ["Slow Bakery"])
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 0)
        XCTAssertNil(model.lastSearchFailure)
    }

    func testServerTimeoutRefundLeavesFreeDiscoveryForTheRetry() async {
        let ai = ScriptedRecommendations([.failure(.timedOut), .success("Second try")])
        let model = home(ai)
        await model.submitSurvey()
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1)
        await model.performRecoveryAction()
        XCTAssertEqual(ai.calls.map(\.token), [nil, nil], "The retry uses the refunded free discovery, not a reward")
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 0)
    }

    // MARK: - Helpers

    private func assertRetryRecovers(_ failure: SearchFailure, title: String,
                                     file: StaticString = #filePath, line: UInt = #line) async {
        let ai = ScriptedRecommendations([.failure(failure), .success("Recovered kitchen")])
        let model = home(ai)
        model.step = .location
        await model.submitSurvey()

        assertRecoveryCard(model, failure: failure, title: title, action: .retry, file: file, line: line)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 1, "Failed searches keep the free discovery", file: file, line: line)

        await model.performRecoveryAction()
        XCTAssertEqual(ai.calls.count, 2, file: file, line: line)
        XCTAssertEqual(model.step, .reveal, file: file, line: line)
        XCTAssertNil(model.lastSearchFailure, "Retry clears the previous failure", file: file, line: line)
        XCTAssertEqual(model.recommendations.map(\.name), ["Recovered kitchen"], file: file, line: line)
        XCTAssertEqual(allowance.remainingFreeDiscoveries, 0, file: file, line: line)
    }

    private func assertRecoveryCard(_ model: HomeViewModel, failure: SearchFailure, title: String,
                                    action: SearchRecoveryAction,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.step, .reveal, "Never left on the loading screen", file: file, line: line)
        XCTAssertFalse(model.isEnriching, file: file, line: line)
        XCTAssertTrue(model.recommendations.isEmpty, file: file, line: line)
        XCTAssertEqual(model.lastSearchFailure, failure, file: file, line: line)
        XCTAssertEqual(model.searchRecovery.title, title, file: file, line: line)
        XCTAssertEqual(model.searchRecovery.action, action, file: file, line: line)
    }

    private func home(_ ai: ScriptedRecommendations) -> HomeViewModel { home(fetch: ai.fetch) }

    private func home(fetch: @escaping (VibeSelection, String?) async -> VibeFetchOutcome) -> HomeViewModel {
        let ads = LoadingAdController(frequency: LoadingAdFrequencyStore(defaults: defaults), eligible: { false },
            record: { _, _, _, _, _, _, _, _ in }, observeEnvironment: false)
        let model = HomeViewModel(loadingAds: ads, allowance: allowance, commerceEnabled: { false },
            fetchRecommendations: fetch, enrich: { recommendations, _, _ in recommendations }, readinessTimeout: 60)
        model.reduceMotionPreference = true
        return model
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Expected asynchronous state did not arrive", file: file, line: line)
        throw URLError(.timedOut)
    }

    fileprivate static let oneResultJSON = #"{"recommendations":[{"name":"Tartine","dish":"Croissant","explanation":"Flaky","mapsUrl":""}],"groundingPlaces":[],"relaxed":false}"#
}

extension VibeFetchOutcome {
    fileprivate static func failure(_ failure: SearchFailure) -> VibeFetchOutcome {
        VibeFetchOutcome(result: VibeResult(recommendations: [], groundingPlaces: [], relaxed: false), failure: failure)
    }

    fileprivate static func success(_ name: String) -> VibeFetchOutcome {
        let recommendation = Recommendation(name: name, dish: "Lunch", image: nil, explanation: "Test result",
            mapsUrl: "", latitude: nil, longitude: nil, rating: nil, reviewCount: nil, isOpen: true, photos: nil,
            address: nil, phone: nil, website: nil, parking: nil, placeId: name, photoRefs: nil, reviews: nil)
        return VibeFetchOutcome(result: VibeResult(recommendations: [recommendation], groundingPlaces: [], relaxed: false),
                                failure: nil)
    }
}

@MainActor
private final class ScriptedRecommendations {
    struct Call { let token: String? }
    private var outcomes: [VibeFetchOutcome]
    private(set) var calls: [Call] = []

    init(_ outcomes: [VibeFetchOutcome]) { self.outcomes = outcomes }

    func fetch(_ selection: VibeSelection, _ token: String?) async -> VibeFetchOutcome {
        calls.append(Call(token: token))
        return outcomes.isEmpty ? .failure(.transportError) : outcomes.removeFirst()
    }
}

@MainActor
private final class ControlledFetch {
    private var continuation: CheckedContinuation<VibeFetchOutcome, Never>?
    var isPending: Bool { continuation != nil }

    func fetch(_ selection: VibeSelection, _ token: String?) async -> VibeFetchOutcome {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(with outcome: VibeFetchOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}

/// Mimics SupabaseAuthSession: hands out the current token and rotates it
/// only after that exact token has been invalidated.
@MainActor
private final class FakeSession {
    private var generation = 1
    private(set) var invalidated: [String] = []

    func request(_ path: String, _ timeout: TimeInterval) async throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://fixture.invalid/\(path)")!)
        request.timeoutInterval = timeout
        request.setValue("Bearer token-\(generation)", forHTTPHeaderField: "Authorization")
        return request
    }

    func invalidate(_ token: String) async {
        invalidated.append(token)
        if token == "token-\(generation)" { generation += 1 }
    }
}

@MainActor
private final class FakeRecommendationsServer {
    private var responses: [(Int, String)]
    private let simulatedLatency: TimeInterval
    private(set) var requests: [URLRequest] = []

    init(_ responses: [(Int, String)], simulatedLatency: TimeInterval = 0) {
        self.responses = responses
        self.simulatedLatency = simulatedLatency
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if simulatedLatency > request.timeoutInterval { throw URLError(.timedOut) }
        guard !responses.isEmpty, let url = request.url else { throw URLError(.badServerResponse) }
        let (status, body) = responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

nonisolated private final class RecoveryAuthStorage: AuthSessionStorage, @unchecked Sendable {
    private var data: Data?
    private let lock = NSLock()
    init(data: Data?) { self.data = data }
    func load() throws -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    func save(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
    func remove() throws { lock.lock(); defer { lock.unlock() }; data = nil }
}

private actor RecoveryAuthServer {
    let response: Data
    var requests: [URLRequest] = []
    init(response: Data) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else { throw URLError(.badURL) }
        return (response, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
