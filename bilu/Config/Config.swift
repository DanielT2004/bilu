//
//  Config.swift
//  bilu
//

import Foundation

enum Config {
    nonisolated static let supabase: SupabaseClientConfiguration = {
        #if DEBUG && BILU_PAYMENT_SANDBOX
        return (try? SupabaseClientConfiguration.resolve(
            info: Bundle.main.infoDictionary ?? [:], allowsPaymentSandbox: true
        )) ?? .unconfiguredSandbox
        #else
        return .production
        #endif
    }()

    nonisolated static let supabaseURL = supabase.url

    /// Base URL for Edge Functions only (no trailing slash).
    /// Dashboard → Project Settings → API → Project URL, then append `/functions/v1`
    nonisolated static let apiBaseURL = "\(supabaseURL)/functions/v1"

    /// Public policy URL used by the in-app Privacy settings row and App Store
    /// Connect's Privacy Policy URL field.
    nonisolated static let privacyPolicyURL = URL(
        string: "\(apiBaseURL)/privacy-policy"
    )!

    nonisolated static let supportURL = URL(string: "\(apiBaseURL)/support")

    /// Google-provided IDs are used only in Debug. Release builds stay
    /// disabled until the real AdMob values are supplied in Info.plist.
    nonisolated static var rewardedAdUnitID: String? {
        #if DEBUG
        return "ca-app-pub-3940256099942544/1712485313"
        #else
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "BILURewardedAdUnitIdentifier"
        ) as? String,
              value.hasPrefix("ca-app-pub-"),
              value != "ca-app-pub-3940256099942544/1712485313" else {
            return nil
        }
        return value
        #endif
    }

    nonisolated static var rewardedAdsAreConfigured: Bool {
        rewardedAdUnitID != nil
    }

    /// Public project identifier used to create a user session. This is not an
    /// authorization credential; paid functions require a user's access token.
    nonisolated static let supabaseAnonKey = supabase.anonKey
}

nonisolated struct SupabaseClientConfiguration: Equatable, Sendable {
    enum ConfigurationError: Error { case invalidSandbox }

    static let productionReference = "yysxjtexwlnvoptxcxlp"
    static let production = SupabaseClientConfiguration(
        url: "https://yysxjtexwlnvoptxcxlp.supabase.co",
        anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl5c3hqdGV4d2xudm9wdHhjeGxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2Njc0ODgsImV4cCI6MjEwMzI0MzQ4OH0.5q1ayzeDHm7oLZOE_sMpPdjHXfgyNWbixaPGvU3T36A",
        projectReference: productionReference, isPaymentSandbox: false, isConfigured: true
    )
    /// Invalid sandbox manifests must never fall back to the production project.
    static let unconfiguredSandbox = SupabaseClientConfiguration(
        url: "https://payment-sandbox-unconfigured.invalid", anonKey: "",
        projectReference: "unconfigured-payment-sandbox", isPaymentSandbox: true, isConfigured: false
    )

    let url: String
    let anonKey: String
    let projectReference: String
    let isPaymentSandbox: Bool
    let isConfigured: Bool

    var sessionKeychainService: String {
        let original = "com.simonsoloman.bilu.supabase-session"
        return projectReference == Self.productionReference ? original : "\(original).\(projectReference)"
    }

    static func resolve(info: [String: Any], allowsPaymentSandbox: Bool) throws -> Self {
        // The normal app, including every Release build, ignores override keys.
        guard allowsPaymentSandbox else { return .production }
        guard info["BILUPaymentSandbox"] as? Bool == true,
              let rawURL = info["BILUSupabaseURL"] as? String,
              let components = URLComponents(string: rawURL),
              components.scheme == "https", components.user == nil, components.password == nil,
              components.port == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let host = components.host,
              host.range(of: "^[a-z0-9]{20}\\.supabase\\.co$", options: .regularExpression) != nil,
              let project = host.split(separator: ".").first.map(String.init),
              project != productionReference,
              let key = info["BILUSupabaseAnonKey"] as? String,
              isPublicKey(key, for: project) else { throw ConfigurationError.invalidSandbox }
        return Self(url: "https://\(host)", anonKey: key, projectReference: project,
                    isPaymentSandbox: true, isConfigured: true)
    }

    private static func isPublicKey(_ key: String, for project: String) -> Bool {
        if key.range(of: "^sb_publishable_[A-Za-z0-9_-]{16,}$", options: .regularExpression) != nil { return true }
        let segments = key.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return false }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        // This is configuration validation, not JWT authentication. Supabase
        // verifies the key; the client merely refuses server-only credentials.
        return claims["role"] as? String == "anon" && claims["ref"] as? String == project
    }
}
