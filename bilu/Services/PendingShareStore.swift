//
//  PendingShareStore.swift
//  bilu
//
//  Reads/clears the TikTok links queued by the Share Extension into the
//  App Group container. Mirrors biluShare's writer — same suite, same key.
//

import Foundation

enum PendingShareStore {
    private static let suiteName = "group.com.bilu.shared"
    private static let key = "pendingTikTokShares"

    static func fetchAll() -> [PendingTikTokShare] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let raw = defaults.array(forKey: key) as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let urlString = dict["urlString"] as? String,
                  let timestamp = dict["dateAdded"] as? Double else { return nil }
            return PendingTikTokShare(id: id, urlString: urlString, dateAdded: Date(timeIntervalSince1970: timestamp))
        }
        .sorted { $0.dateAdded > $1.dateAdded }
    }

    static func remove(id: String) {
        guard let defaults = UserDefaults(suiteName: suiteName),
              var raw = defaults.array(forKey: key) as? [[String: Any]] else { return }
        raw.removeAll { ($0["id"] as? String) == id }
        defaults.set(raw, forKey: key)
    }
}
