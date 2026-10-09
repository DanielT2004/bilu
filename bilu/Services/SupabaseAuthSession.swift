import Foundation
import Security

enum SupabaseAuthError: Error {
    case invalidResponse
    case requestFailed(Int)
    case missingSession
    case keychain(OSStatus)
}

/// Maintains one anonymous Supabase user per app installation. The public anon
/// key may create the session, but only the short-lived user JWT authorizes paid
/// Edge Functions. Refresh tokens remain in the device Keychain.
actor SupabaseAuthSession {
    static let shared = SupabaseAuthSession()

    private struct StoredSession: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date

        var canBeUsed: Bool { expiresAt.timeIntervalSinceNow > 60 }
    }

    private struct SessionResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private var session: StoredSession?

    private init() {
        if let data = try? SessionKeychain.load() {
            session = try? JSONDecoder().decode(StoredSession.self, from: data)
        }
    }

    func accessToken() async throws -> String {
        if let session, session.canBeUsed {
            return session.accessToken
        }

        if let refreshToken = session?.refreshToken,
           let refreshed = try? await requestSession(
               path: "/auth/v1/token?grant_type=refresh_token",
               body: ["refresh_token": refreshToken]
           ) {
            return try persist(refreshed).accessToken
        }

        let created = try await requestSession(path: "/auth/v1/signup", body: [:])
        return try persist(created).accessToken
    }

    private func requestSession(path: String, body: [String: String]) async throws -> SessionResponse {
        guard let url = URL(string: "\(Config.supabaseURL)\(path)") else {
            throw SupabaseAuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        // Authentication is part of the visible search journey on first launch.
        // Fail promptly instead of adding another long wait before the paid call.
        request.timeoutInterval = 8
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw SupabaseAuthError.requestFailed(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(SessionResponse.self, from: data),
              !decoded.accessToken.isEmpty,
              !decoded.refreshToken.isEmpty else {
            throw SupabaseAuthError.missingSession
        }
        return decoded
    }

    private func persist(_ response: SessionResponse) throws -> StoredSession {
        let stored = StoredSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn)
        )
        let data = try JSONEncoder().encode(stored)
        try SessionKeychain.save(data)
        session = stored
        return stored
    }
}

enum AuthenticatedAPIRequest {
    static func post(path: String, timeout: TimeInterval) async throws -> URLRequest {
        let token = try await SupabaseAuthSession.shared.accessToken()
        guard let url = URL(string: "\(Config.apiBaseURL)/\(path)") else {
            throw SupabaseAuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        return request
    }
}

private enum SessionKeychain {
    nonisolated private static let service = "com.simonsoloman.bilu.supabase-session"
    nonisolated private static let account = "anonymous-user"

    nonisolated static func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SupabaseAuthError.keychain(status) }
        return result as? Data
    }

    nonisolated static func save(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SupabaseAuthError.keychain(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw SupabaseAuthError.keychain(addStatus) }
    }
}
