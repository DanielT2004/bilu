//
//  PendingTikTokShare.swift
//  bilu
//

import Foundation

/// A TikTok link the user shared into bilu via the Share Extension, not yet
/// acted on. Queued in the App Group container until the user opens or
/// dismisses it — automatic resolution to a restaurant isn't built yet.
struct PendingTikTokShare: Identifiable, Equatable {
    let id: String
    let urlString: String
    let dateAdded: Date
}
