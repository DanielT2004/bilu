import XCTest
@testable import bilu

@MainActor
final class DiscoveryJobServiceTests: XCTestCase {
    private let accountA = "11111111-1111-4111-8111-111111111111"
    private let accountB = "22222222-2222-4222-8222-222222222222"
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var session: URLSession!
    private var token = "account-a-token"
    private var refreshCount = 0
    private var requestFactoryCount = 0

    override func setUp() async throws {
        suiteName = "DiscoveryJobServiceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryJobURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        DiscoveryJobURLProtocol.handler = nil
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLostResponseSurvivesRelaunchAndRecoversWithoutStartingAnotherJob() async throws {
        var requests: [[String: Any]] = []
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" { return self.wallet() }
            let body = try Self.body(request)
            requests.append(body)
            if requests.count == 1 { throw URLError(.networkConnectionLost) }
            return Self.completed()
        }
        await expectFailure(makeService(), matching: nil)
        let stored = pendingIDs()
        XCTAssertEqual(stored.count, 1)

        let recovered = try await makeService().explore(input: ["prompt": "Dinner in LA"])

        XCTAssertTrue(recovered.recommendations.isEmpty)
        XCTAssertEqual(requests.map { $0["action"] as? String }, ["start", "status"])
        XCTAssertEqual(requests[0]["discoveryId"] as? String, requests[1]["discoveryId"] as? String)
        XCTAssertNil(requests[1]["input"], "Recovery must not resubmit paid provider input")
        XCTAssertTrue(pendingIDs().isEmpty)
        XCTAssertEqual(refreshCount, 1)
    }

    func testMissingReservationRetriesTheSameIdentifierAfterStatusLookup() async throws {
        var requests: [[String: Any]] = []
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" { return self.wallet() }
            let body = try Self.body(request)
            requests.append(body)
            switch requests.count {
            case 1: throw URLError(.timedOut)
            case 2: return (404, ["code": "DISCOVERY_NOT_FOUND"])
            default: return Self.completed()
            }
        }
        await expectFailure(makeService(), matching: nil)
        _ = try await makeService().explore(input: ["prompt": "Dinner in LA"])

        XCTAssertEqual(requests.map { $0["action"] as? String }, ["start", "status", "start"])
        XCTAssertEqual(Set(requests.compactMap { $0["discoveryId"] as? String }).count, 1)
        XCTAssertTrue(pendingIDs().isEmpty)
    }

    func testAccountSwitchDuringWalletReadKeepsOriginalBearerForSpending() async throws {
        var discoveryBearer: String?
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-a-token")
                self.token = "account-b-token"
                return self.wallet()
            }
            discoveryBearer = request.value(forHTTPHeaderField: "Authorization")
            return Self.completed()
        }

        _ = try await makeService().explore(input: ["prompt": "Dinner in LA"])

        XCTAssertEqual(discoveryBearer, "Bearer account-a-token")
        XCTAssertEqual(requestFactoryCount, 1, "Fetching a second bearer could charge the newly signed-in account")
    }

    func testPendingIdentifiersAreScopedToAuthoritativeAccount() async throws {
        var activeAccount = accountA
        var requests: [[String: Any]] = []
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" { return self.wallet(account: activeAccount) }
            requests.append(try Self.body(request))
            if activeAccount == self.accountA && requests.count == 1 { throw URLError(.timedOut) }
            return Self.completed()
        }
        let service = makeService()
        await expectFailure(service, matching: nil)
        activeAccount = accountB
        _ = try await service.explore(input: ["prompt": "Dinner in LA"])
        XCTAssertEqual(pendingIDs().count, 1, "Account B must not discard account A's recovery identifier")
        activeAccount = accountA
        _ = try await service.explore(input: ["prompt": "Dinner in LA"])

        XCTAssertEqual(requests.map { $0["action"] as? String }, ["start", "start", "status"])
        XCTAssertNotEqual(requests[0]["discoveryId"] as? String, requests[1]["discoveryId"] as? String)
        XCTAssertEqual(requests[0]["discoveryId"] as? String, requests[2]["discoveryId"] as? String)
        XCTAssertTrue(pendingIDs().isEmpty)
    }

    func testDisabledCommerceAllowsExistingResultRecoveryButNoNewReservation() async throws {
        var enabled = true
        var requestCount = 0
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" { return self.wallet(enabled: enabled) }
            requestCount += 1
            if requestCount == 1 { throw URLError(.timedOut) }
            XCTAssertEqual(try Self.body(request)["action"] as? String, "status")
            return Self.completed()
        }
        await expectFailure(makeService(), matching: nil)
        enabled = false
        _ = try await makeService().explore(input: ["prompt": "Dinner in LA"])
        await expectFailure(makeService(), matching: .unavailable)

        XCTAssertEqual(requestCount, 2)
        XCTAssertTrue(pendingIDs().isEmpty)
    }

    func testTerminalReleasedJobClearsIdentifierBeforeAnExplicitNewSearch() async throws {
        var requests: [[String: Any]] = []
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" { return self.wallet() }
            requests.append(try Self.body(request))
            if requests.count == 1 { return (200, ["status": "released"]) }
            return Self.completed()
        }
        let service = makeService()
        await expectFailure(service, matching: .failed)
        XCTAssertTrue(pendingIDs().isEmpty)
        _ = try await service.explore(input: ["prompt": "Dinner in LA"])

        XCTAssertNotEqual(requests[0]["discoveryId"] as? String, requests[1]["discoveryId"] as? String)
        XCTAssertEqual(refreshCount, 2)
    }

    func testPendingServerJobIsPolledWithoutResubmittingInput() async throws {
        var requests: [[String: Any]] = []
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" { return self.wallet() }
            requests.append(try Self.body(request))
            if requests.count == 1 { return (202, ["status": "reserved"]) }
            return Self.completed()
        }
        _ = try await makeService().explore(input: ["prompt": "Dinner in LA"])

        XCTAssertEqual(requests.map { $0["action"] as? String }, ["start", "status"])
        XCTAssertEqual(requests[0]["discoveryId"] as? String, requests[1]["discoveryId"] as? String)
        XCTAssertNil(requests[1]["input"])
    }

    func testExhaustionReturnsPurchaseRequirementAndRefreshesWallet() async {
        DiscoveryJobURLProtocol.handler = { request in
            if request.url?.lastPathComponent == "purchase-wallet" { return self.wallet() }
            return (402, ["code": "DISCOVERY_CREDITS_REQUIRED"])
        }

        await expectFailure(makeService(), matching: .allowanceRequired)

        XCTAssertTrue(pendingIDs().isEmpty)
        XCTAssertEqual(refreshCount, 1)
    }

    private func makeService() -> DiscoveryJobService {
        DiscoveryJobService(defaults: defaults, session: session, requestFactory: { path, timeout in
            self.requestFactoryCount += 1
            var request = URLRequest(url: URL(string: "https://discovery-test.invalid/\(path)")!)
            request.httpMethod = "POST"
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
            return request
        }, walletDidChange: { self.refreshCount += 1 })
    }

    private func expectFailure(_ service: DiscoveryJobService, matching expected: DiscoveryJobError?) async {
        do {
            _ = try await service.explore(input: ["prompt": "Dinner in LA"])
            XCTFail("Expected failure")
        } catch {
            if let expected { XCTAssertEqual(error as? DiscoveryJobError, expected) }
        }
    }

    private func pendingIDs() -> [String] {
        defaults.dictionaryRepresentation().compactMap { key, value in
            key.hasPrefix("purchases.discovery.") ? value as? String : nil
        }
    }

    private func wallet(account: String? = nil, enabled: Bool = true) -> (Int, [String: Any]) {
        let id = account ?? accountA
        return (200, [
            "accountId": id, "appAccountToken": id, "requiresSignIn": false,
            "plan": "free", "periodStart": "2026-10-01T00:00:00Z", "periodEnd": "2026-11-01T00:00:00Z",
            "included": ["explore": 2, "tiktok": 1], "purchased": ["explore": 4, "tiktok": 1],
            "commerceEnabled": enabled, "proEnabled": false
        ])
    }

    private static func completed() -> (Int, [String: Any]) {
        (200, ["status": "committed", "result": ["recommendations": [], "groundingPlaces": [], "relaxed": false]])
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(buffer, count: count)
            }
            data = bytes
        } else { throw URLError(.badServerResponse) }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private final class DiscoveryJobURLProtocol: URLProtocol {
    @MainActor static var handler: ((URLRequest) throws -> (Int, [String: Any]))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Task { @MainActor in
            do {
                let handler = try XCTUnwrap(Self.handler)
                let (status, payload) = try handler(request)
                let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: payload))
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }
}
