//
//  PendingShareStore.swift
//  biluShare
//
//  Writes shared TikTok links into the App Group container so the main app
//  can pick them up on next launch. The extension has no network/UI budget
//  to resolve the link itself, so it only queues it.
//

import Foundation

enum PendingShareStore {
    private static let suiteName = "group.com.bilu.shared"
    private static let key = "pendingTikTokShares"

    static func append(urlString: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        var items = (defaults.array(forKey: key) as? [[String: Any]]) ?? []
        items.append([
            "id": UUID().uuidString,
            "urlString": urlString,
            "dateAdded": Date().timeIntervalSince1970
        ])
        defaults.set(items, forKey: key)
    }
}
