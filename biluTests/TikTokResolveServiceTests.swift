import Foundation
import XCTest
@testable import bilu

@MainActor
final class TikTokResolveServiceTests: XCTestCase {

    private let video = """
    {"videoId":"7312345678901234567","caption":"best birria","canonicalUrl":"https://www.tiktok.com/@a/video/7312345678901234567","authorName":"Food Scout","thumbnailUrl":null}
    """

    private let place = """
    {"placeId":"ChIJteddys","placeName":"Teddy's Red Tacos","address":"Venice, CA","lat":33.99,"lng":-118.47,"rank":0,"totalViews":0,"videoIds":["7312345678901234567"],"videoCount":1,"rating":4.6,"isOpen":true,"neighborhood":"Venice","score":1.2}
    """

    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testResolvedShareDecodesVideoAndPlaces() {
        let outcome = TikTokResolveService.decode(
            statusCode: 200,
            data: data(#"{"video":\#(video),"places":[\#(place)],"queryCity":"Los Angeles"}"#)
        )
        guard case let .resolved(decodedVideo, places) = outcome else {
            return XCTFail("expected .resolved, got \(outcome)")
        }
        XCTAssertEqual(decodedVideo.videoId, "7312345678901234567")
        XCTAssertEqual(places.map(\.placeName), ["Teddy's Red Tacos"])
    }

    func testMissingCityKeepsTheVideo() {
        let outcome = TikTokResolveService.decode(
            statusCode: 400,
            data: data(#"{"error":"missing_city","video":\#(video)}"#)
        )
        guard case let .needsCity(decodedVideo) = outcome else {
            return XCTFail("expected .needsCity, got \(outcome)")
        }
        XCTAssertEqual(decodedVideo?.videoId, "7312345678901234567")
    }

    func testBadLinksAndDeadVideosAreUnavailable() {
        XCTAssertEqual(
            TikTokResolveService.decode(statusCode: 400, data: data(#"{"error":"invalid_share_url"}"#)),
            .unavailable
        )
        XCTAssertEqual(
            TikTokResolveService.decode(statusCode: 422, data: data(#"{"error":"video_unavailable"}"#)),
            .unavailable
        )
    }

    func testQuotaAuthAndServerErrorsAreRetriedLater() {
        for code in [401, 426, 429, 500, 503] {
            XCTAssertEqual(
                TikTokResolveService.decode(statusCode: code, data: data(#"{"error":"x"}"#)),
                .retryLater,
                "status \(code)"
            )
        }
        XCTAssertEqual(TikTokResolveService.decode(statusCode: 200, data: data("{}")), .retryLater)
    }
}
