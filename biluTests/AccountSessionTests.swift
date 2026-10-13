import Foundation
import XCTest
@testable import bilu

final class AccountSessionTests: XCTestCase {
    private let guestID = "11111111-1111-4111-8111-111111111111"
    private let existingID = "22222222-2222-4222-8222-222222222222"

    func testConcurrentAccessUsesOneRefreshAndPreservesIdentity() async throws {
        let storage = try storedSession(anonymous: false, expired: true)
        let server = AuthHTTPFixture(responses: [(200, response(id: guestID, anonymous: false))])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<12 { group.addTask { try await auth.accessToken() } }
            var tokens: [String] = []
            for try await token in group { tokens.append(token) }
            return tokens
        }
        XCTAssertEqual(Set(tokens), ["new-access"])
        let requests = await server.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.query, "grant_type=refresh_token")
        let account = await auth.cachedAccount()
        XCTAssertEqual(account?.id.uuidString.lowercased(), guestID)
    }

    func testFailedRefreshNeverCreatesAnotherGuestOrErasesSession() async throws {
        let storage = try storedSession(anonymous: false, expired: true)
        let original = try storage.load()
        let server = AuthHTTPFixture(responses: [(503, Data("{}".utf8))])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        do { _ = try await auth.accessToken(); XCTFail("Expected refresh failure") } catch {}
        XCTAssertEqual(try storage.load(), original)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(requests.contains { $0.url?.path.hasSuffix("signup") == true })
    }

    func testInaccessibleKeychainDoesNotCreateGuest() async throws {
        let storage = MemoryAuthStorage(data: nil)
        storage.loadError = SupabaseAuthError.keychain(-25308)
        let server = AuthHTTPFixture(responses: [])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        do { _ = try await auth.accessToken(); XCTFail("Expected Keychain failure") } catch {}
        let requests = await server.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testGuestUpgradeLinksItsExistingUUID() async throws {
        let storage = try storedSession(anonymous: true)
        let server = AuthHTTPFixture(responses: [(200, response(id: guestID, anonymous: false))])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        let account = try await auth.signInWithApple(idToken: "apple-test-token", nonce: "test-nonce")
        XCTAssertEqual(account.id.uuidString.lowercased(), guestID)
        XCTAssertFalse(account.isAnonymous)
        let first = await server.firstRequest()
        let request = try XCTUnwrap(first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["link_identity"] as? Bool, true)
        XCTAssertEqual(body["nonce"] as? String, "test-nonce")
    }

    func testExistingAppleIdentityRecoversItsOriginalAccount() async throws {
        let storage = try storedSession(anonymous: true)
        let server = AuthHTTPFixture(responses: [
            (422, Data("{\"code\":\"identity_already_exists\"}".utf8)),
            (200, response(id: existingID, anonymous: false)),
        ])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        let account = try await auth.signInWithApple(idToken: "apple-test-token", nonce: "test-nonce")
        XCTAssertEqual(account.id.uuidString.lowercased(), existingID)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests.last?.value(forHTTPHeaderField: "Authorization"))
    }

    func testLinkConfigurationFailureDoesNotSilentlySwitchAccount() async throws {
        let storage = try storedSession(anonymous: true)
        let original = try storage.load()
        let server = AuthHTTPFixture(responses: [(400, Data("{\"code\":\"manual_linking_disabled\"}".utf8))])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        do { _ = try await auth.signInWithApple(idToken: "token", nonce: "nonce"); XCTFail("Expected rejection") } catch {}
        XCTAssertEqual(try storage.load(), original)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testDeletionReauthenticationCannotSwitchToDifferentAccount() async throws {
        let storage = try storedSession(anonymous: false)
        let original = try storage.load()
        let server = AuthHTTPFixture(responses: [(200, response(id: existingID, anonymous: false))])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        do {
            _ = try await auth.signInWithApple(idToken: "token", nonce: "nonce", requireAccount: UUID(uuidString: guestID))
            XCTFail("Expected account mismatch")
        } catch SupabaseAuthError.accountMismatch {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(try storage.load(), original)
    }

    func testExplicitExistingAccountRecoveryBypassesExpiredGuestRefresh() async throws {
        let storage = try storedSession(anonymous: true, expired: true)
        let server = AuthHTTPFixture(responses: [(200, response(id: existingID, anonymous: false))])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        let account = try await auth.signInWithApple(idToken: "token", nonce: "nonce", linkGuest: false)
        XCTAssertEqual(account.id.uuidString.lowercased(), existingID)
        let requests = await server.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.query, "grant_type=id_token")
        XCTAssertNil(requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testOriginalGuestKeychainSchemaStillRefreshes() async throws {
        let storage = MemoryAuthStorage(data: try JSONSerialization.data(withJSONObject: [
            "accessToken": "old", "refreshToken": "refresh", "expiresAt": Date.distantPast.timeIntervalSinceReferenceDate,
        ]))
        let server = AuthHTTPFixture(responses: [(200, response(id: guestID, anonymous: true))])
        let auth = SupabaseAuthSession(storage: storage, transport: { try await server.send($0) })
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "new-access")
        let account = await auth.cachedAccount()
        XCTAssertEqual(account?.isAnonymous, true)
    }

    private func storedSession(anonymous: Bool, expired: Bool = false) throws -> MemoryAuthStorage {
        MemoryAuthStorage(data: try JSONSerialization.data(withJSONObject: [
            "accessToken": "old-access", "refreshToken": "old-refresh",
            "expiresAt": Date().addingTimeInterval(expired ? -100 : 3600).timeIntervalSinceReferenceDate,
            "user": ["id": guestID, "is_anonymous": anonymous],
        ]))
    }

    private func response(id: String, anonymous: Bool) -> Data {
        Data("{\"access_token\":\"new-access\",\"refresh_token\":\"new-refresh\",\"expires_in\":3600,\"user\":{\"id\":\"\(id)\",\"is_anonymous\":\(anonymous)}}".utf8)
    }
}

nonisolated private final class MemoryAuthStorage: AuthSessionStorage, @unchecked Sendable {
    private var data: Data?
    var loadError: Error?
    private let lock = NSLock()
    init(data: Data?) { self.data = data }
    func load() throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        if let loadError { throw loadError }
        return data
    }
    func save(_ data: Data) throws { lock.lock(); defer { lock.unlock() }; self.data = data }
    func remove() throws { lock.lock(); defer { lock.unlock() }; data = nil }
}

private actor AuthHTTPFixture {
    var responses: [(Int, Data)]
    var requests: [URLRequest] = []
    init(responses: [(Int, Data)]) { self.responses = responses }
    func firstRequest() -> URLRequest? { requests.first }
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !responses.isEmpty, let url = request.url else { throw URLError(.badServerResponse) }
        let (status, data) = responses.removeFirst()
        try await Task.sleep(nanoseconds: 10_000_000)
        return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
