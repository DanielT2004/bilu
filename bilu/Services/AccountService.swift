import Foundation

nonisolated protocol AccountServicing: Sendable {
    func account() async throws -> BiluAccount
    func cachedAccount() async -> BiluAccount?
    func signIn(idToken: String, nonce: String, requireAccount: UUID?, linkGuest: Bool) async throws -> BiluAccount
    func signOut() async throws
    func deleteAccount(_ accountID: UUID, authorizationCode: String) async throws
}

nonisolated struct AccountService: AccountServicing {
    let auth: SupabaseAuthSession
    init(auth: SupabaseAuthSession = .shared) { self.auth = auth }
    func account() async throws -> BiluAccount { try await auth.account() }
    func cachedAccount() async -> BiluAccount? { await auth.cachedAccount() }
    func signIn(idToken: String, nonce: String, requireAccount: UUID?, linkGuest: Bool) async throws -> BiluAccount {
        try await auth.signInWithApple(idToken: idToken, nonce: nonce, requireAccount: requireAccount, linkGuest: linkGuest)
    }
    func signOut() async throws { try await auth.signOut() }

    func deleteAccount(_ accountID: UUID, authorizationCode: String) async throws {
        let token = try await auth.accessToken()
        guard let url = URL(string: "\(Config.apiBaseURL)/account-delete") else { throw SupabaseAuthError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: ["authorizationCode": authorizationCode])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw SupabaseAuthError.requestFailed(http.statusCode) }
        try await auth.clearDeletedAccount(accountID)
    }
}
