import Foundation
import Security

nonisolated struct BiluAccount: Codable, Equatable, Sendable {
    let id: UUID
    let isAnonymous: Bool
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id, email
        case isAnonymous = "is_anonymous"
    }
}

nonisolated enum SupabaseAuthError: Error {
    case invalidResponse
    case requestFailed(Int)
    case rejected(Int, String?)
    case missingSession
    case accountMismatch
    case keychain(OSStatus)
}

nonisolated protocol AuthSessionStorage: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func remove() throws
}

/// Auth mutations and refresh are serialized, including across actor suspension.
/// A failed refresh never replaces an existing identity with a new guest.
actor SupabaseAuthSession {
    static let shared = SupabaseAuthSession()
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private struct StoredSession: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        var user: BiluAccount?
        var canBeUsed: Bool { expiresAt.timeIntervalSinceNow > 60 }
    }

    private struct SessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval
        let user: BiluAccount

        enum CodingKeys: String, CodingKey {
            case user
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private let storage: any AuthSessionStorage
    private let transport: Transport
    private let configuration: SupabaseClientConfiguration
    private var session: StoredSession?
    private var storageError: Error?
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(storage: (any AuthSessionStorage)? = nil, transport: @escaping Transport = {
        try await URLSession.shared.data(for: $0)
    }, configuration: SupabaseClientConfiguration = Config.supabase) {
        self.storage = storage ?? SessionKeychain(configuration: configuration)
        self.transport = transport
        self.configuration = configuration
        do {
            if let data = try self.storage.load() {
                session = try JSONDecoder().decode(StoredSession.self, from: data)
            }
        } catch {
            // A temporarily inaccessible or damaged Keychain item must not be
            // silently overwritten with an unrelated anonymous account.
            storageError = error
        }
    }

    func accessToken() async throws -> String {
        await acquire()
        defer { release() }
        return try await tokenWhileLocked()
    }

    func account() async throws -> BiluAccount {
        await acquire()
        defer { release() }
        let token = try await tokenWhileLocked()
        let data = try await request(path: "/auth/v1/user", method: "GET", token: token)
        let user = try JSONDecoder().decode(BiluAccount.self, from: data)
        if var stored = session {
            stored.user = user
            try save(stored)
        }
        return user
    }

    func cachedAccount() -> BiluAccount? { session?.user }

    /// Guest linking preserves its UUID. An Apple identity that already belongs
    /// to a Bilu account signs into that account; device-local saves are untouched.
    func signInWithApple(idToken: String, nonce: String, requireAccount: UUID? = nil, linkGuest: Bool = true) async throws -> BiluAccount {
        await acquire()
        defer { release() }
        // A durable account can recover through Apple even if its refresh token
        // has expired. A guest must have a live session to link its identity.
        var body: [String: Any] = ["provider": "apple", "id_token": idToken, "nonce": nonce]
        var token: String?
        let isGuest = session?.user?.isAnonymous ?? (session != nil)
        if isGuest && requireAccount == nil && linkGuest {
            token = try await tokenWhileLocked()
            body["link_identity"] = true
        }
        let response: SessionResponse
        do {
            response = try await requestSession(body: body, token: token)
        } catch SupabaseAuthError.rejected(_, let code) where isGuest && linkGuest && code == "identity_already_exists" {
            body.removeValue(forKey: "link_identity")
            response = try await requestSession(body: body)
        }
        guard !response.user.isAnonymous,
              requireAccount == nil || response.user.id == requireAccount else {
            throw SupabaseAuthError.accountMismatch
        }
        try persist(response)
        storageError = nil
        return response.user
    }

    func signOut() async throws {
        await acquire()
        defer { release() }
        if let token = session?.accessToken {
            do {
                _ = try await request(path: "/auth/v1/logout?scope=local", method: "POST", token: token)
            } catch SupabaseAuthError.rejected(let status, _) where status == 401 || status == 403 {
                // Explicit sign-out may remove an already invalid session.
            }
        }
        try storage.remove()
        session = nil
        storageError = nil
    }

    func clearDeletedAccount(_ accountID: UUID) async throws {
        await acquire()
        defer { release() }
        guard session?.user?.id == accountID else { throw SupabaseAuthError.accountMismatch }
        try storage.remove()
        session = nil
        storageError = nil
    }

    private func tokenWhileLocked() async throws -> String {
        guard configuration.isConfigured else { throw SupabaseClientConfiguration.ConfigurationError.invalidSandbox }
        if let storageError { throw storageError }
        if let session, session.canBeUsed { return session.accessToken }
        let response: SessionResponse
        if let session {
            response = try await requestSession(
                path: "/auth/v1/token?grant_type=refresh_token",
                body: ["refresh_token": session.refreshToken]
            )
        } else {
            response = try await requestSession(path: "/auth/v1/signup", body: [:])
        }
        try persist(response)
        return response.accessToken
    }

    private func requestSession(path: String = "/auth/v1/token?grant_type=id_token", body: [String: Any], token: String? = nil) async throws -> SessionResponse {
        let data = try await request(path: path, method: "POST", body: body, token: token)
        let response = try JSONDecoder().decode(SessionResponse.self, from: data)
        guard !response.accessToken.isEmpty, !response.refreshToken.isEmpty,
              response.expiresIn > 0 else { throw SupabaseAuthError.missingSession }
        return response
    }

    private func request(path: String, method: String, body: [String: Any]? = nil, token: String? = nil) async throws -> Data {
        guard configuration.isConfigured else { throw SupabaseClientConfiguration.ConfigurationError.invalidSandbox }
        guard let url = URL(string: "\(configuration.url)\(path)") else { throw SupabaseAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.anonKey, forHTTPHeaderField: "apikey")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 12
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw SupabaseAuthError.rejected(http.statusCode, payload?["code"] as? String ?? payload?["error_code"] as? String)
        }
        return data
    }

    private func persist(_ response: SessionResponse) throws {
        try save(StoredSession(accessToken: response.accessToken, refreshToken: response.refreshToken,
                               expiresAt: Date().addingTimeInterval(response.expiresIn), user: response.user))
    }

    private func save(_ stored: StoredSession) throws {
        try storage.save(JSONEncoder().encode(stored))
        session = stored
    }

    private func acquire() async {
        if locked { await withCheckedContinuation { waiters.append($0) } }
        else { locked = true }
    }

    private func release() {
        if waiters.isEmpty { locked = false }
        else { waiters.removeFirst().resume() }
    }
}

enum AuthenticatedAPIRequest {
    static func post(path: String, timeout: TimeInterval) async throws -> URLRequest {
        let token = try await SupabaseAuthSession.shared.accessToken()
        guard let url = URL(string: "\(Config.apiBaseURL)/\(path)") else { throw SupabaseAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        return request
    }
}

nonisolated struct SessionKeychain: AuthSessionStorage {
    let service: String
    let account = "anonymous-user"

    init(configuration: SupabaseClientConfiguration = Config.supabase) {
        service = configuration.sessionKeychainService
    }

    // Production retains the exact original pair. Sandbox projects use separate
    // services so switching builds never reads, replaces, or deletes that user.
    private var query: [String: Any] { [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ] }

    func load() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SupabaseAuthError.keychain(status) }
        return result as? Data
    }

    func save(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SupabaseAuthError.keychain(status) }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw SupabaseAuthError.keychain(added) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SupabaseAuthError.keychain(status) }
    }
}
