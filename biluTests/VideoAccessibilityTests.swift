import XCTest
@testable import bilu

final class VideoAccessibilityTests: XCTestCase {
    func testClipLabelNamesAuthorAndSpokenViews() {
        XCTAssertEqual(
            VideoAccessibility.clipLabel(authorName: "tacoqueen", viewCount: 12_000),
            "Video by @tacoqueen, 12 thousand views"
        )
        XCTAssertEqual(
            VideoAccessibility.clipLabel(authorName: "  ", viewCount: 1),
            "Video, 1 view"
        )
    }

    func testSpokenCountSpellsOutMagnitudes() {
        XCTAssertEqual(VideoAccessibility.spokenCount(0, unit: "view"), "0 views")
        XCTAssertEqual(VideoAccessibility.spokenCount(950, unit: "view"), "950 views")
        XCTAssertEqual(VideoAccessibility.spokenCount(1_250, unit: "like"), "1.2 thousand likes")
        XCTAssertEqual(VideoAccessibility.spokenCount(1_000_000, unit: "view"), "1 million views")
        XCTAssertEqual(VideoAccessibility.spokenCount(3_480_000, unit: "view"), "3.4 million views")
        XCTAssertEqual(VideoAccessibility.spokenCount(1, unit: "TikTok"), "1 TikTok")
        XCTAssertEqual(VideoAccessibility.spokenCount(-5, unit: "view"), "0 views")
    }

    func testPlaybackValueReportsStateAndSpeed() {
        XCTAssertEqual(VideoAccessibility.playbackValue(isPlaying: true, rate: 1.0), "Playing")
        XCTAssertEqual(VideoAccessibility.playbackValue(isPlaying: false, rate: 1.0), "Paused")
        XCTAssertEqual(VideoAccessibility.playbackValue(isPlaying: true, rate: 2.0), "Playing, 2x speed")
    }
}
