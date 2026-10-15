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
        XCTAssertEqual(places.map(\.name), ["Teddy's Red Tacos"])
        XCTAssertEqual(places.first?.tags, [])
    }

    func testPlaceTagsAndCuisineAreKeptWhenSent() {
        let tagged = place.replacingOccurrences(of: #""score":1.2}"#, with: #""score":1.2,"tags":["tacos"],"cuisine":"Mexican"}"#)
        let outcome = TikTokResolveService.decode(
            statusCode: 200,
            data: data(#"{"video":\#(video),"places":[\#(tagged)]}"#)
        )
        guard case let .resolved(_, places) = outcome else {
            return XCTFail("expected .resolved, got \(outcome)")
        }
        XCTAssertEqual(places.first?.tags, ["Mexican", "tacos"])
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

    func testOnlyUnchargedFailuresAreRetriedAutomatically() {
        // Auth and rate-limit refusals happen before the server spends quota.
        for code in [401, 429] {
            XCTAssertEqual(
                TikTokResolveService.decode(statusCode: code, data: data(#"{"error":"x","code":"y"}"#)),
                .retryLater,
                "status \(code)"
            )
        }
        // The function says whether its own failure ran the paid step.
        XCTAssertEqual(
            TikTokResolveService.decode(statusCode: 500, data: data(#"{"error":"resolve_failed","charged":false}"#)),
            .retryLater
        )
        XCTAssertEqual(
            TikTokResolveService.decode(statusCode: 502, data: data(#"{"error":"place_lookup_failed","charged":true}"#)),
            .failed
        )
        // Anything unmarked (gateway timeout, 503, worker killed) may have charged.
        for code in [426, 500, 503, 504, 546] {
            XCTAssertEqual(
                TikTokResolveService.decode(statusCode: code, data: data(#"{"error":"x"}"#)),
                .failed,
                "status \(code)"
            )
        }
        // A 200 means the paid step ran; a garbled one isn't retried silently.
        XCTAssertEqual(TikTokResolveService.decode(statusCode: 200, data: data("{}")), .failed)
    }

    func testOnlyErrorsBeforeTheRequestLeftAreRetriedAutomatically() {
        for code in [URLError.Code.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed] {
            XCTAssertEqual(TikTokResolveService.outcome(forTransportError: URLError(code)), .retryLater, "\(code)")
        }
        for code in [URLError.Code.timedOut, .networkConnectionLost, .cancelled, .badServerResponse] {
            XCTAssertEqual(TikTokResolveService.outcome(forTransportError: URLError(code)), .failed, "\(code)")
        }
        XCTAssertEqual(TikTokResolveService.outcome(forTransportError: CocoaError(.fileNoSuchFile)), .failed)
    }
}
