import Foundation
import XCTest
@testable import bilu

@MainActor
final class PendingSharesModelTests: XCTestCase {

    private let video = ResolvedShareVideo(
        videoId: "1", caption: "best birria", canonicalUrl: "https://www.tiktok.com/@a/video/1",
        authorName: "Food Scout", thumbnailUrl: nil
    )
    private let place = ResolvedSharePlace(
        placeId: "ChIJteddys", name: "Teddy's Red Tacos", address: "Venice, CA",
        latitude: 33.99, longitude: -118.47, rating: 4.6, neighborhood: "Venice", tags: ["Mexican"]
    )

    private func share(_ id: String) -> PendingTikTokShare {
        PendingTikTokShare(id: id, urlString: "https://www.tiktok.com/t/\(id)", dateAdded: Date())
    }

    /// Records every resolve call and answers with a fixed outcome.
    private final class ResolverSpy {
        var outcome: TikTokResolveOutcome
        var calls: [(url: String, city: String?, lat: Double?, lng: Double?)] = []
        init(_ outcome: TikTokResolveOutcome) { self.outcome = outcome }
    }

    private func makeModel(
        storage: InMemoryPendingShareStorage,
        spy: ResolverSpy,
        location: ShareResolveLocation = ShareResolveLocation(city: "Los Angeles, CA", latitude: 34.05, longitude: -118.24),
        rememberedCity: ((String) -> Void)? = nil
    ) -> PendingSharesModel {
        PendingSharesModel(
            storage: storage,
            resolver: { url, city, lat, lng in
                spy.calls.append((url, city, lat, lng))
                return spy.outcome
            },
            location: { location },
            rememberCity: rememberedCity ?? { _ in }
        )
    }

    func testResolvedShareIsStoredWithTagsAndNotResolvedAgain() async {
        let storage = InMemoryPendingShareStorage(queued: [share("a")])
        let spy = ResolverSpy(.resolved(video: video, places: [place]))
        let model = makeModel(storage: storage, spy: spy)

        await model.refreshAndResolve()

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.url, "https://www.tiktok.com/t/a")
        XCTAssertEqual(spy.calls.first?.city, "Los Angeles, CA")
        XCTAssertEqual(spy.calls.first?.lat, 34.05)
        XCTAssertEqual(model.shares.first?.resolution, .resolved(video: video, places: [place]))
        XCTAssertEqual(storage.resolutions["a"], .resolved(video: video, places: [place]))
        guard case let .resolved(_, places)? = storage.resolutions["a"] else { return XCTFail() }
        XCTAssertEqual(places.first?.tags, ["Mexican"])
        XCTAssertTrue(model.resolving.isEmpty)

        // Next launch: a fresh model reads the stored result and makes no call.
        let relaunched = makeModel(storage: storage, spy: spy)
        await relaunched.refreshAndResolve()
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(relaunched.shares.first?.resolution, .resolved(video: video, places: [place]))
    }

    func testResolvedPlaceSavesUnderItsPlacesId() {
        let rec = place.recommendation(caption: "best birria")
        XCTAssertEqual(rec.identityKey, "ChIJteddys")
        XCTAssertEqual(rec.explanation, "best birria")
        XCTAssertEqual(place.recommendation(caption: nil).explanation, "From a TikTok you shared.")
    }

    func testNeedsCityIsStoredAndRetryUsesTheTypedCity() async {
        let storage = InMemoryPendingShareStorage(queued: [share("a")])
        let spy = ResolverSpy(.needsCity(video: video))
        var remembered: [String] = []
        let model = makeModel(
            storage: storage, spy: spy,
            location: ShareResolveLocation(city: nil),
            rememberedCity: { remembered.append($0) }
        )

        await model.refreshAndResolve()
        XCTAssertEqual(model.shares.first?.resolution, .needsCity)
        XCTAssertEqual(storage.resolutions["a"], .needsCity)

        // Launching again doesn't re-ask the server; it waits for the user.
        await model.refreshAndResolve()
        XCTAssertEqual(spy.calls.count, 1)

        spy.outcome = .resolved(video: video, places: [place])
        await model.retry(model.shares[0], city: "  Austin, TX ")
        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertEqual(spy.calls.last?.city, "Austin, TX")
        XCTAssertEqual(remembered, ["Austin, TX"])
        XCTAssertEqual(model.shares.first?.resolution, .resolved(video: video, places: [place]))

        await model.retry(model.shares[0], city: "   ")
        XCTAssertEqual(spy.calls.count, 2, "a blank city is ignored")
    }

    func testUnavailableShareCanBeDismissed() async {
        let storage = InMemoryPendingShareStorage(queued: [share("a"), share("b")])
        let spy = ResolverSpy(.unavailable)
        let model = makeModel(storage: storage, spy: spy)

        await model.refreshAndResolve()
        XCTAssertEqual(model.shares.map(\.resolution), [.unavailable, .unavailable])

        model.dismiss(model.shares.first { $0.id == "a" }!)
        XCTAssertEqual(model.shares.map(\.id), ["b"])
        XCTAssertEqual(storage.queued.map(\.id), ["b"])
        XCTAssertNil(storage.resolutions["a"])
        XCTAssertEqual(storage.resolutions["b"], .unavailable)
    }

    func testRetryLaterKeepsTheShareAndRetriesNextLaunch() async {
        let storage = InMemoryPendingShareStorage(queued: [share("a")])
        let spy = ResolverSpy(.retryLater)
        let model = makeModel(storage: storage, spy: spy)

        await model.refreshAndResolve()
        XCTAssertEqual(model.shares.map(\.id), ["a"])
        XCTAssertEqual(model.shares.first?.resolution, .pending)
        XCTAssertNil(storage.resolutions["a"])
        XCTAssertEqual(storage.queued.count, 1)

        spy.outcome = .resolved(video: video, places: [place])
        await makeModel(storage: storage, spy: spy).refreshAndResolve()
        XCTAssertEqual(spy.calls.count, 2)
        XCTAssertEqual(storage.resolutions["a"], .resolved(video: video, places: [place]))
    }

    func testOverlappingLaunchAndActiveDoNotResolveTwice() async {
        let storage = InMemoryPendingShareStorage(queued: [share("a"), share("b")])
        var calls: [String] = []
        var gate: CheckedContinuation<Void, Never>?
        let model = PendingSharesModel(
            storage: storage,
            resolver: { url, _, _, _ in
                calls.append(url)
                if gate == nil { await withCheckedContinuation { gate = $0 } }
                return .unavailable
            },
            location: { ShareResolveLocation(city: "Los Angeles, CA") },
            rememberCity: { _ in }
        )

        let first = Task { await model.refreshAndResolve() }
        // Let the first pass claim both shares and block inside the resolver.
        while gate == nil { await Task.yield() }
        XCTAssertEqual(model.resolving, ["a", "b"])

        await model.refreshAndResolve()   // "became active" while the first runs
        await model.retry(model.shares[0], city: "Austin") // also skipped: in flight
        gate?.resume()
        await first.value

        XCTAssertEqual(calls.sorted(), ["https://www.tiktok.com/t/a", "https://www.tiktok.com/t/b"])
        XCTAssertTrue(model.resolving.isEmpty)
    }

    func testDismissWhileResolvingDropsTheLateResult() async {
        let storage = InMemoryPendingShareStorage(queued: [share("a")])
        var gate: CheckedContinuation<Void, Never>?
        let model = PendingSharesModel(
            storage: storage,
            resolver: { _, _, _, _ in
                await withCheckedContinuation { gate = $0 }
                return .resolved(video: self.video, places: [self.place])
            },
            location: { ShareResolveLocation(city: "Los Angeles, CA") },
            rememberCity: { _ in }
        )

        let task = Task { await model.refreshAndResolve() }
        while gate == nil { await Task.yield() }
        model.dismiss(model.shares[0])
        gate?.resume()
        await task.value

        XCTAssertTrue(model.shares.isEmpty)
        XCTAssertTrue(storage.resolutions.isEmpty)
    }

    func testRefreshPrunesResultsForSharesThatAreGone() {
        let storage = InMemoryPendingShareStorage(
            queued: [share("a")],
            resolutions: ["a": .unavailable, "gone": .needsCity]
        )
        let model = makeModel(storage: storage, spy: ResolverSpy(.retryLater))
        XCTAssertEqual(model.shares.first?.resolution, .unavailable)
        XCTAssertEqual(storage.resolutions, ["a": .unavailable])
    }

    func testResolutionsRoundTripThroughJSON() throws {
        let all: [String: PendingShareResolution] = [
            "a": .resolved(video: video, places: [place]),
            "b": .needsCity,
            "c": .unavailable
        ]
        let data = try JSONEncoder().encode(all)
        XCTAssertEqual(try JSONDecoder().decode([String: PendingShareResolution].self, from: data), all)
    }
}
