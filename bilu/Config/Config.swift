//
//  Config.swift
//  bilu
//

import Foundation

enum Config {
    /// Base URL for Edge Functions only (no trailing slash).
    /// Dashboard → Project Settings → API → Project URL, then append `/functions/v1`
    static let apiBaseURL = "https://yysxjtexwlnvoptxcxlp.supabase.co/functions/v1"

    /// Project anon (public) key — Dashboard → Project Settings → API → `anon` `public`.
    /// Required for default Edge Functions (JWT verification). Safe to embed in the app.
    /// If you deployed with `--no-verify-jwt`, you can leave this empty.
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl5c3hqdGV4d2xudm9wdHhjeGxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc2Njc0ODgsImV4cCI6MjEwMzI0MzQ4OH0.5q1ayzeDHm7oLZOE_sMpPdjHXfgyNWbixaPGvU3T36A"
}
