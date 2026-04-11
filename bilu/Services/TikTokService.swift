//
//  TikTokService.swift
//  bilu
//
//  Response structure (scraptik~tiktok-api):
//  Array of pages, each page has:
//    .search_item_list[] → .aweme_info → {
//        aweme_id, desc,
//        author: { nickname, avatar_thumb: { url_list } },
//        statistics: { digg_count, comment_count, play_count },
//        video: { play_addr: { url_list }, cover: { url_list } }
//    }
//

import Foundation

enum TikTokService {

    static func fetchVideos(query: String, maxResults: Int = 10) async -> [TikTokVideo] {
        let urlString = "https://api.apify.com/v2/acts/scraptik~tiktok-api/run-sync-get-dataset-items?token=\(Config.apifyApiKey)"
        guard let url = URL(string: urlString) else { return [] }

        let body: [String: Any] = [
            "searchPosts_count": maxResults,
            "searchPosts_keyword": query,
            "searchPosts_sortType": 0,
            "searchSounds_useFilters": false
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[TikTokService] HTTP \(code) for '\(query)': \(body.prefix(300))")
                #endif
                return []
            }

            let videos = parseVideos(from: data)
            #if DEBUG
            print("[TikTokService] Fetched \(videos.count) videos for '\(query)'")
            if let first = videos.first {
                print("[TikTokService] First video → id:\(first.videoId) digg:\(first.diggCount) comments:\(first.commentCount) desc:\"\(first.desc.prefix(60))\" thumb:\(first.thumbnailUrl.prefix(80))")
            }
            #endif
            return videos
        } catch {
            #if DEBUG
            print("[TikTokService] Error for '\(query)': \(error)")
            #endif
            return []
        }
    }

    // MARK: - Manual JSON parsing

    private static func parseVideos(from data: Data) -> [TikTokVideo] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        var results: [TikTokVideo] = []

        for page in root {
            guard let items = page["search_item_list"] as? [[String: Any]] else { continue }
            for item in items {
                guard let aweme = item["aweme_info"] as? [String: Any] else { continue }
                if let video = parseAweme(aweme) {
                    results.append(video)
                }
            }
        }

        return results
    }

    private static func parseAweme(_ aweme: [String: Any]) -> TikTokVideo? {
        // Required fields — skip video if any are missing
        guard
            let awemeId     = aweme["aweme_id"] as? String,
            let authorDict  = aweme["author"] as? [String: Any],
            let nickname    = authorDict["nickname"] as? String,
            let videoDict   = aweme["video"] as? [String: Any],
            let statsDict   = aweme["statistics"] as? [String: Any]
        else { return nil }

        // desc is the plain caption — sanitize: if it looks like a URL it's a bad parse
        let rawDesc = aweme["desc"] as? String ?? ""
        let desc = rawDesc.hasPrefix("http") ? "" : rawDesc

        // Avatar — first URL in avatar_thumb.url_list
        let avatarUrl: String
        if let thumbDict = authorDict["avatar_thumb"] as? [String: Any],
           let urlList = thumbDict["url_list"] as? [String],
           let first = urlList.first {
            avatarUrl = first
        } else {
            avatarUrl = ""
        }

        // Video play URL — play_addr.url_list[0]
        let videoUrl: String
        if let playAddr = videoDict["play_addr"] as? [String: Any],
           let urlList = playAddr["url_list"] as? [String],
           let first = urlList.first {
            videoUrl = first
        } else {
            return nil  // No playable URL → skip
        }

        // Thumbnail — use cover.url_list[0], fall back to dynamic_cover
        let thumbnailUrl: String
        if let coverDict = videoDict["cover"] as? [String: Any],
           let urlList = coverDict["url_list"] as? [String],
           let first = urlList.first {
            thumbnailUrl = first
        } else if let dynDict = videoDict["dynamic_cover"] as? [String: Any],
                  let urlList = dynDict["url_list"] as? [String],
                  let first = urlList.first {
            thumbnailUrl = first
        } else {
            thumbnailUrl = ""
        }

        // Stats — values can exceed Int32.max, use int64Value then clamp to Int
        let diggCount    = Int(clamping: (statsDict["digg_count"]    as? NSNumber)?.int64Value ?? 0)
        let commentCount = Int(clamping: (statsDict["comment_count"] as? NSNumber)?.int64Value ?? 0)
        let viewCount    = Int(clamping: (statsDict["play_count"]    as? NSNumber)?.int64Value ?? 0)

        // Share URL — construct canonical TikTok link
        let uniqueId = authorDict["unique_id"] as? String ?? ""
        let shareUrl = uniqueId.isEmpty
            ? "https://www.tiktok.com/video/\(awemeId)"
            : "https://www.tiktok.com/@\(uniqueId)/video/\(awemeId)"

        return TikTokVideo(
            videoId:      awemeId,
            shareUrl:     shareUrl,
            videoUrl:     videoUrl,
            thumbnailUrl: thumbnailUrl,
            author:       TikTokAuthor(name: nickname, avatar: avatarUrl),
            desc:         desc,
            diggCount:    diggCount,
            commentCount: commentCount,
            viewCount:    viewCount
        )
    }
}
