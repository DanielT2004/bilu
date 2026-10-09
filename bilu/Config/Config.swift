//
//  Config.swift
//  bilu
//

import Foundation

enum Config {
    nonisolated static let supabaseURL = "https://yysxjtexwlnvoptxcxlp.supabase.co"

    /// Base URL for Edge Functions only (no trailing slash).
    /// Dashboard → Project Settings → API → Project URL, then append `/functions/v1`
    nonisolated static let apiBaseURL = "\(supabaseURL)/functions/v1"

    /// Public policy URL used by the in-app Privacy settings row and App Store
    /// Connect's Privacy Policy URL field.
    nonisolated static let privacyPolicyURL = URL(
        string: "\(apiBaseURL)/privacy-policy"
    )!

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
    nonisolated static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl5c3hqdGV4d2xudm9wdHhjeGxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2Njc0ODgsImV4cCI6MjEwMzI0MzQ4OH0.5q1ayzeDHm7oLZOE_sMpPdjHXfgyNWbixaPGvU3T36A"
}
