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

enum TikTokServiceError: Error, Equatable {
    case offline
    case timedOut
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case serverUnavailable
    case invalidResponse
    case requestFailed
    case pendingDiscovery

    var title: String {
        switch self {
        case .offline: return "You're offline"
        case .timedOut: return "Search took too long"
        case .pendingDiscovery: return "Your search is still finishing"
        case .unauthorized: return "Couldn't start search"
        case .rateLimited: return "Too many searches"
        case .serverUnavailable: return "Search is unavailable"
        case .invalidResponse, .requestFailed: return "Couldn't load results"
        }
    }

    var message: String {
        switch self {
        case .pendingDiscovery:
            return "Try this search again to recover its result without using another search."
        case .offline:
            return "Check your internet connection and try again."
        case .timedOut:
            return "The search service didn't respond in time. Please try again."
        case .unauthorized:
            return "We couldn't verify this search. Please try again."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds, retryAfterSeconds > 0 {
                return "Please wait about \(retryAfterSeconds) seconds, then try again."
            }
            return "Please wait a moment, then try again."
        case .serverUnavailable:
            return "Our search service is having trouble. Please try again shortly."
        case .invalidResponse:
            return "The search service returned an unexpected response. Please try again."
        case .requestFailed:
            return "Something interrupted the search. Please try again."
        }
    }

    static func fromHTTPStatus(_ statusCode: Int, retryAfter: String? = nil) -> TikTokServiceError {
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 408:
            return .timedOut
        case 429:
            return .rateLimited(retryAfterSeconds: retryAfter.flatMap(Int.init))
        case 500...599:
            return .serverUnavailable
        default:
            return .requestFailed
        }
    }

    static func from(_ error: Error) -> TikTokServiceError {
        if let serviceError = error as? TikTokServiceError { return serviceError }

        if let authError = error as? SupabaseAuthError {
            switch authError {
            case .requestFailed(let statusCode), .rejected(let statusCode, _):
                return fromHTTPStatus(statusCode)
            case .invalidResponse, .missingSession, .accountMismatch, .keychain:
                return .unauthorized
            }
        }

        guard let urlError = error as? URLError else { return .requestFailed }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .requestFailed
        }
    }
}

enum TikTokService {

    /// ScrapTik sortType values:
    /// 0 = relevance, 1 = most liked, 2 = most recent
    static func fetchVideos(query: String, maxResults: Int = 10, sortType: Int = 0) async throws -> [TikTokVideo] {
        // Commerce searches use DiscoveryJobService to include extraction and
        // settle one complete result. Detail screens must not start an unmetered scrape.
        guard !PurchaseConfiguration.current.commerceEnabled else {
            throw TikTokServiceError.serverUnavailable
        }
        let body: [String: Any] = [
            "query": query,
            "maxResults": maxResults,
            "sortType": sortType
        ]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            throw TikTokServiceError.requestFailed
        }

        do {
            var request = try await AuthenticatedAPIRequest.post(path: "tiktok-search", timeout: 60)
            request.httpBody = httpBody
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw TikTokServiceError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                #if DEBUG
                let body = String(data: data, encoding: .utf8) ?? ""
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[TikTokService] HTTP \(code) for '\(query)': \(body.prefix(300))")
                #endif
                throw TikTokServiceError.fromHTTPStatus(
                    http.statusCode,
                    retryAfter: http.value(forHTTPHeaderField: "Retry-After")
                )
            }

            let videos = try parseVideos(from: data)
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
            throw TikTokServiceError.from(error)
        }
    }

    // MARK: - Manual JSON parsing

    private static func parseVideos(from data: Data) throws -> [TikTokVideo] {
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let root = json as? [[String: Any]] else {
            throw TikTokServiceError.invalidResponse
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

        // Prefer lowest-bitrate stream for fast playback start.
        // Fall back to top-level play_addr if bit_rate is missing.
        let videoUrl: String = {
            if let bitRates = videoDict["bit_rate"] as? [[String: Any]],
               let lowest = bitRates.last,
               let playAddr = lowest["play_addr"] as? [String: Any],
               let urlList = playAddr["url_list"] as? [String],
               let first = urlList.first {
                return first
            }
            if let playAddr = videoDict["play_addr"] as? [String: Any],
               let urlList = playAddr["url_list"] as? [String],
               let first = urlList.first {
                return first
            }
            return ""
        }()
        guard !videoUrl.isEmpty else { return nil }

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

        let anchors = parseAnchors(aweme: aweme)
        let transcriptUrl = parseTranscriptUrl(video: videoDict)

        return TikTokVideo(
            videoId:      awemeId,
            shareUrl:     shareUrl,
            videoUrl:     videoUrl,
            thumbnailUrl: thumbnailUrl,
            author:       TikTokAuthor(name: nickname, avatar: avatarUrl),
            desc:         desc,
            diggCount:    diggCount,
            commentCount: commentCount,
            viewCount:    viewCount,
            transcriptUrl: transcriptUrl,
            debug:        TikTokDebugInfo(anchors: anchors)
        )
    }

    private static func parseAnchors(aweme: [String: Any]) -> [TikTokAnchor] {
        guard let anchorList = aweme["anchors"] as? [[String: Any]] else { return [] }
        var out: [TikTokAnchor] = []
        for a in anchorList {
            let keyword = a["keyword"] as? String ?? ""
            var categoryName: String? = nil
            var poiClassName: String? = nil
            var lat: Double? = nil
            var lng: Double? = nil
            // `extra` is a JSON-encoded string, not an object — parse it
            if let extraStr = a["extra"] as? String,
               let extraData = extraStr.data(using: .utf8),
               let extra = (try? JSONSerialization.jsonObject(with: extraData)) as? [String: Any] {
                categoryName = extra["category_name"] as? String
                poiClassName = extra["poi_class_name"] as? String
                if let loc = extra["location"] as? [String: Any] {
                    if let latStr = loc["lat"] as? String { lat = Double(latStr) }
                    if let lngStr = loc["lng"] as? String { lng = Double(lngStr) }
                }
            }
            out.append(TikTokAnchor(keyword: keyword, categoryName: categoryName, poiClassName: poiClassName, lat: lat, lng: lng))
        }
        return out
    }

    private static func parseTranscriptUrl(video: [String: Any]) -> String? {
        guard let claInfo = video["cla_info"] as? [String: Any],
              let captionInfos = claInfo["caption_infos"] as? [[String: Any]],
              !captionInfos.isEmpty else { return nil }

        // Prefer English
        let english = captionInfos.first { c in
            if let code = c["language_code"] as? String, code.hasPrefix("en") { return true }
            if let lang = c["lang"] as? String, lang.hasPrefix("en") { return true }
            return false
        }
        let chosen = english ?? captionInfos.first

        if let url = chosen?["url"] as? String, !url.isEmpty { return url }
        if let urlList = chosen?["url_list"] as? [String], let first = urlList.first { return first }
        return nil
    }
}
