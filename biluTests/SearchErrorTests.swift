import XCTest
@testable import bilu

@MainActor
final class SearchErrorTests: XCTestCase {
    func testHTTPFailuresMapToActionableErrors() {
        XCTAssertEqual(TikTokServiceError.fromHTTPStatus(401), .unauthorized)
        XCTAssertEqual(TikTokServiceError.fromHTTPStatus(429, retryAfter: "42"), .rateLimited(retryAfterSeconds: 42))
        XCTAssertEqual(TikTokServiceError.fromHTTPStatus(503), .serverUnavailable)
        XCTAssertEqual(TikTokServiceError.fromHTTPStatus(418), .requestFailed)
    }

    func testNetworkFailuresMapToOfflineAndTimeout() {
        XCTAssertEqual(TikTokServiceError.from(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(TikTokServiceError.from(URLError(.timedOut)), .timedOut)
    }

    func testAuthenticationFailuresMapToActionableErrors() {
        XCTAssertEqual(TikTokServiceError.from(SupabaseAuthError.requestFailed(401)), .unauthorized)
        XCTAssertEqual(TikTokServiceError.from(SupabaseAuthError.requestFailed(503)), .serverUnavailable)
        XCTAssertEqual(TikTokServiceError.from(SupabaseAuthError.missingSession), .unauthorized)
    }

    func testSearchViewModelKeepsFailuresSeparateFromEmptyResults() async {
        let failing = SearchViewModel { _, _, _ in
            throw TikTokServiceError.serverUnavailable
        }
        failing.query = "ramen in Los Angeles"
        await failing.search()

        XCTAssertEqual(failing.searchError, .serverUnavailable)
        XCTAssertTrue(failing.videos.isEmpty)
        XCTAssertTrue(failing.hasSearched)

        let empty = SearchViewModel { _, _, _ in [] }
        empty.query = "ramen in Los Angeles"
        await empty.search()

        XCTAssertNil(empty.searchError)
        XCTAssertTrue(empty.videos.isEmpty)
        XCTAssertTrue(empty.hasSearched)
    }

    func testClearRemovesSearchError() async {
        let viewModel = SearchViewModel { _, _, _ in
            throw TikTokServiceError.offline
        }
        viewModel.query = "ramen in Los Angeles"
        await viewModel.search()

        viewModel.clear()

        XCTAssertNil(viewModel.searchError)
        XCTAssertFalse(viewModel.hasSearched)
    }

    func testChangingSortRequiresConfirmationBeforeRunningAnotherTikTokSearch() async {
        var calls: [(String, Int)] = []
        let video = TikTokVideo(
            videoId: "1",
            shareUrl: "https://www.tiktok.com/@bilu/video/1",
            videoUrl: "https://example.com/video.mp4",
            thumbnailUrl: "https://example.com/image.jpg",
            author: TikTokAuthor(name: "Bilu", avatar: ""),
            desc: "Ramen in Los Angeles",
            diggCount: 1,
            commentCount: 1,
            viewCount: 1,
            transcriptUrl: nil,
            debug: nil
        )
        let viewModel = SearchViewModel(
            usesWalletDiscovery: false,
            locationExtractor: { _, _ in
                LocationExtractionResult(locations: [], unresolvedVideoIds: [])
            },
            fetchVideos: { query, _, sort in
                calls.append((query, sort))
                return [video]
            }
        )
        viewModel.query = "ramen in Los Angeles"
        await viewModel.search()

        viewModel.setSort(.mostLiked)

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(viewModel.sort, .relevant)
        XCTAssertEqual(viewModel.pendingSort, .mostLiked)

        await viewModel.confirmSortChange()

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[1].1, SearchSort.mostLiked.rawValue)
        XCTAssertEqual(viewModel.sort, .mostLiked)
        XCTAssertNil(viewModel.pendingSort)
    }
}
