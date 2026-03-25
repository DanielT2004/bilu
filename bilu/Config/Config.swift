//
//  Config.swift
//  bilu
//

import Foundation

enum Config {
    /// Base URL for Edge Functions only (no trailing slash).
    /// Dashboard → Project Settings → API → Project URL, then append `/functions/v1`
    static let apiBaseURL = "https://cnbhsaayknmtiwdamonb.supabase.co/functions/v1"

    /// Project anon (public) key — Dashboard → Project Settings → API → `anon` `public`.
    /// Required for default Edge Functions (JWT verification). Safe to embed in the app.
    /// If you deployed with `--no-verify-jwt`, you can leave this empty.
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNuYmhzYWF5a25tdGl3ZGFtb25iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwODY1NzUsImV4cCI6MjA4OTY2MjU3NX0.QvrYIk7yk-odESjL1H93oyjVv_XYZhgvTQA1jnmzGP0"
}
