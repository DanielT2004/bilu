//
//  TikTokVideo.swift
//  bilu
//

import Foundation

struct TikTokAuthor: Codable {
    let name: String    // author.nickname
    let avatar: String  // author.avatar_thumb.url_list[0]
}

struct TikTokAnchor: Codable {
    let keyword: String
    let categoryName: String?
    let poiClassName: String?
    let lat: Double?
    let lng: Double?
}

struct TikTokDebugInfo: Codable {
    let anchors: [TikTokAnchor]
}

struct TikTokVideo: Codable, Identifiable {
    let videoId: String         // aweme_id
    let shareUrl: String        // constructed as https://www.tiktok.com/@user/video/<aweme_id>
    let videoUrl: String        // video.play_addr.url_list[0]
    let thumbnailUrl: String    // video.cover.url_list[0]
    let author: TikTokAuthor
    let desc: String            // desc
    let diggCount: Int          // statistics.digg_count
    let commentCount: Int       // statistics.comment_count
    let viewCount: Int          // statistics.play_count
    let transcriptUrl: String?  // video.cla_info.caption_infos[].url (prefer lang=eng)
    let debug: TikTokDebugInfo?

    var id: String { videoId }
}
