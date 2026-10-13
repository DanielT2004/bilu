import Foundation
import XCTest
@testable import bilu

@MainActor
final class SandboxConfigurationTests: XCTestCase {
    private let sandboxReference = "abcdefghijklmnopqrst"

    func testNormalBuildIgnoresSandboxOverridesAndPreservesProductionNamespace() throws {
        let resolved = try SupabaseClientConfiguration.resolve(info: sandboxInfo(), allowsPaymentSandbox: false)
        XCTAssertEqual(resolved, .production)
        XCTAssertEqual(SessionKeychain(configuration: resolved).service, "com.simonsoloman.bilu.supabase-session")
        XCTAssertEqual(SessionKeychain(configuration: resolved).account, "anonymous-user")
    }

    func testExplicitSandboxUsesItsOwnProjectAndKeychainNamespace() throws {
        let resolved = try sandboxConfiguration()
        XCTAssertEqual(resolved.url, "https://\(sandboxReference).supabase.co")
        XCTAssertEqual(resolved.projectReference, sandboxReference)
        XCTAssertTrue(resolved.isPaymentSandbox)
        XCTAssertTrue(resolved.isConfigured)
        XCTAssertEqual(SessionKeychain(configuration: resolved).service,
                       "com.simonsoloman.bilu.supabase-session.\(sandboxReference)")
        XCTAssertNotEqual(resolved.sessionKeychainService, SupabaseClientConfiguration.production.sessionKeychainService)
    }

    func testSandboxRejectsProductionPrivateKeysAndMismatchedJWTProject() throws {
        var productionInfo = sandboxInfo()
        productionInfo["BILUSupabaseURL"] = SupabaseClientConfiguration.production.url
        XCTAssertThrowsError(try SupabaseClientConfiguration.resolve(info: productionInfo, allowsPaymentSandbox: true))
        for key in ["sb_secret_private-do-not-embed", try jwt(role: "service_role", reference: sandboxReference),
                    try jwt(role: "anon", reference: "other-project"), "not-a-public-key"] {
            var info = sandboxInfo()
            info["BILUSupabaseAnonKey"] = key
            XCTAssertThrowsError(try SupabaseClientConfiguration.resolve(info: info, allowsPaymentSandbox: true))
        }
    }

    func testSandboxAcceptsMatchingPublicAnonJWT() throws {
        var info = sandboxInfo()
        let key = try jwt(role: "anon", reference: sandboxReference)
        info["BILUSupabaseAnonKey"] = key
        let resolved = try SupabaseClientConfiguration.resolve(info: info, allowsPaymentSandbox: true)
        XCTAssertEqual(resolved.anonKey, key)
    }

    func testMissingOrUntrustedSandboxEndpointFailsClosed() {
        XCTAssertThrowsError(try SupabaseClientConfiguration.resolve(info: [:], allowsPaymentSandbox: true))
        for endpoint in ["http://\(sandboxReference).supabase.co", "https://example.com",
                         "https://\(sandboxReference).supabase.co.evil.example",
                         "https://user:pass@\(sandboxReference).supabase.co",
                         "https://\(sandboxReference).supabase.co/auth/v1",
                         "https://\(sandboxReference).supabase.co?project=production"] {
            var info = sandboxInfo()
            info["BILUSupabaseURL"] = endpoint
            XCTAssertThrowsError(try SupabaseClientConfiguration.resolve(info: info, allowsPaymentSandbox: true))
        }
        XCTAssertFalse(SupabaseClientConfiguration.unconfiguredSandbox.isConfigured)
        XCTAssertNotEqual(SupabaseClientConfiguration.unconfiguredSandbox.sessionKeychainService,
                          SupabaseClientConfiguration.production.sessionKeychainService)
    }

    func testKeychainWriteAndRemovalCannotCrossProjectNamespaces() throws {
        let first = SessionKeychain(configuration: try sandboxConfiguration(reference: randomReference()))
        let second = SessionKeychain(configuration: try sandboxConfiguration(reference: randomReference()))
        defer { try? first.remove(); try? second.remove() }
        // Only unique test sandbox namespaces are touched; never production.
        try first.save(Data("first-sandbox-session".utf8))
        XCTAssertNil(try second.load())
        try second.save(Data("second-sandbox-session".utf8))
        try first.remove()
        XCTAssertNil(try first.load())
        XCTAssertEqual(try second.load(), Data("second-sandbox-session".utf8))
    }

    func testPurchaseJournalsUseProjectDirectoriesAndKeepOriginalProductionPath() throws {
        let original = FilePurchaseJournal(configuration: .production).url
        XCTAssertEqual(original, URL.applicationSupportDirectory.appending(path: "Commerce/PendingPurchases.json"))
        let sandbox = FilePurchaseJournal(configuration: try sandboxConfiguration()).url
        XCTAssertEqual(sandbox, URL.applicationSupportDirectory
            .appending(path: "Commerce/Sandbox/\(sandboxReference)/PendingPurchases.json"))
        XCTAssertNotEqual(original, sandbox)
        XCTAssertNotEqual(sandbox, FilePurchaseJournal(configuration: try sandboxConfiguration(reference: randomReference())).url)
    }

    func testSandboxAuthRequestsUseOnlySandboxURLAndPublicKey() async throws {
        let configuration = try sandboxConfiguration(reference: randomReference())
        let storage = SessionKeychain(configuration: configuration)
        defer { try? storage.remove() }
        let server = SandboxAuthHTTPFixture()
        let auth = SupabaseAuthSession(transport: { try await server.send($0) }, configuration: configuration)
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "sandbox-user-token")
        let request = await server.lastRequest
        XCTAssertEqual(request?.url?.absoluteString, "\(configuration.url)/auth/v1/signup")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "apikey"), configuration.anonKey)
        XCTAssertNil(request?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNotNil(try storage.load())
    }

    func testInvalidSandboxConfigurationMakesNoAuthenticationRequest() async {
        let server = SandboxAuthHTTPFixture()
        let auth = SupabaseAuthSession(transport: { try await server.send($0) }, configuration: .unconfiguredSandbox)
        do {
            _ = try await auth.accessToken()
            XCTFail("Missing sandbox config must not create a production guest")
        } catch SupabaseClientConfiguration.ConfigurationError.invalidSandbox {} catch { XCTFail("Unexpected error: \(error)") }
        let request = await server.lastRequest
        XCTAssertNil(request)
    }

    private func sandboxInfo(reference: String? = nil) -> [String: Any] {
        ["BILUPaymentSandbox": true,
         "BILUSupabaseURL": "https://\(reference ?? sandboxReference).supabase.co/",
         "BILUSupabaseAnonKey": "sb_publishable_test_public_key_0123456789"]
    }

    private func sandboxConfiguration(reference: String? = nil) throws -> SupabaseClientConfiguration {
        try SupabaseClientConfiguration.resolve(info: sandboxInfo(reference: reference), allowsPaymentSandbox: true)
    }

    private func randomReference() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(20))
    }

    private func jwt(role: String, reference: String) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["role": role, "ref": reference])
            .base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "test-header.\(payload).test-signature"
    }
}

private actor SandboxAuthHTTPFixture {
    var lastRequest: URLRequest?
    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        lastRequest = request
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        let data = Data("""
        {"access_token":"sandbox-user-token","refresh_token":"sandbox-refresh-token","expires_in":3600,
         "user":{"id":"11111111-1111-4111-8111-111111111111","is_anonymous":true}}
        """.utf8)
        return (data, response)
    }
}
