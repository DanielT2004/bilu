//
//  VideoAccessibility.swift
//  bilu
//
//  VoiceOver strings for TikTok clips, shared by the Search tiles, the venue
//  sheet and the full-screen player so they all read the same way.
//

import Foundation

enum VideoAccessibility {
    static let playHint = "Plays video"

    /// "Video by @author, 12 thousand views". Drops the author when it's empty.
    static func clipLabel(authorName: String, viewCount: Int) -> String {
        let author = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let views = spokenCount(viewCount, unit: "view")
        return author.isEmpty ? "Video, \(views)" : "Video by @\(author), \(views)"
    }

    /// Spoken count such as "1 view", "950 views", "12 thousand views", "1.2 million views".
    /// Abbreviations like "12K" are read letter by letter, so spell the magnitude out.
    static func spokenCount(_ count: Int, unit: String) -> String {
        let n = max(0, count)
        let number: String
        if n >= 1_000_000 {
            number = "\(trimmed(Double(n) / 1_000_000)) million"
        } else if n >= 1_000 {
            number = "\(trimmed(Double(n) / 1_000)) thousand"
        } else {
            number = "\(n)"
        }
        return "\(number) \(n == 1 ? unit : unit + "s")"
    }

    /// Accessibility value for a player page: "Playing", "Paused", "Playing, 2x speed".
    static func playbackValue(isPlaying: Bool, rate: Float) -> String {
        let state = isPlaying ? "Playing" : "Paused"
        return rate > 1.0 ? "\(state), \(trimmed(Double(rate)))x speed" : state
    }

    /// One decimal at most, no trailing ".0": 12.0 → "12", 1.25 → "1.2".
    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded(.down) / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
