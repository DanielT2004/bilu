//
//  ImagePrefetcher.swift
//  bilu
//
//  Warms URLCache.shared so RecommendationCard's AsyncImage hits a hot cache
//  on first mount — letting the staged reveal animate over images that are
//  already decoded instead of empty placeholders.
//

import Foundation

enum ImagePrefetcher {
    /// Warms URLCache.shared for up to `limit` URLs.
    /// Returns when all complete OR `timeout` elapses — whichever first.
    /// Discards responses; only the cache mutation matters.
    static func warm(urls: [URL], limit: Int = 4, timeout: TimeInterval = 1.2) async {
        let targets = Array(urls.prefix(limit))
        guard !targets.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for url in targets {
                group.addTask {
                    _ = try? await URLSession.shared.data(from: url)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            // Cancel remaining work as soon as the first finisher returns —
            // either all fetches completed, or the timeout fired.
            await group.next()
            group.cancelAll()
        }
    }
}
