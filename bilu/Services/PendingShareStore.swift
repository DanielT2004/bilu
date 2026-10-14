//
//  PendingShareStore.swift
//  bilu
//
//  Reads/clears the TikTok links queued by the Share Extension into the
//  App Group container (mirrors biluShare's writer — same suite, same key),
//  remembers how each one resolved, and drives resolution on launch.
//

import Foundation
import CoreLocation
import Combine

// MARK: - Storage

/// Persistence for shared TikToks, injectable for tests.
protocol PendingShareStorage {
    /// The extension's queue, newest first, without resolutions.
    func fetchQueued() -> [PendingTikTokShare]
    func remove(id: String)
    func loadResolutions() -> [String: PendingShareResolution]
    func saveResolutions(_ resolutions: [String: PendingShareResolution])
}

enum PendingShareStore {
    private static let suiteName = "group.com.bilu.shared"
    private static let key = "pendingTikTokShares"
    /// Written only by the app, so the extension's writer stays unchanged.
    private static let resolutionsKey = "pendingTikTokShareResolutions"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func fetchAll() -> [PendingTikTokShare] {
        guard let raw = defaults?.array(forKey: key) as? [[String: Any]] else { return [] }
        return raw.compactMap { dict in
            guard let id = dict["id"] as? String,
                  let urlString = dict["urlString"] as? String,
                  let timestamp = dict["dateAdded"] as? Double else { return nil }
            return PendingTikTokShare(id: id, urlString: urlString, dateAdded: Date(timeIntervalSince1970: timestamp))
        }
        .sorted { $0.dateAdded > $1.dateAdded }
    }

    static func remove(id: String) {
        guard let defaults, var raw = defaults.array(forKey: key) as? [[String: Any]] else { return }
        raw.removeAll { ($0["id"] as? String) == id }
        defaults.set(raw, forKey: key)
    }

    static func loadResolutions() -> [String: PendingShareResolution] {
        guard let data = defaults?.data(forKey: resolutionsKey),
              let decoded = try? JSONDecoder().decode([String: PendingShareResolution].self, from: data)
        else { return [:] }
        return decoded
    }

    static func saveResolutions(_ resolutions: [String: PendingShareResolution]) {
        guard let data = try? JSONEncoder().encode(resolutions) else { return }
        defaults?.set(data, forKey: resolutionsKey)
    }
}

struct AppGroupPendingShareStorage: PendingShareStorage {
    func fetchQueued() -> [PendingTikTokShare] { PendingShareStore.fetchAll() }
    func remove(id: String) { PendingShareStore.remove(id: id) }
    func loadResolutions() -> [String: PendingShareResolution] { PendingShareStore.loadResolutions() }
    func saveResolutions(_ resolutions: [String: PendingShareResolution]) {
        PendingShareStore.saveResolutions(resolutions)
    }
}

/// In-memory storage for tests and the DEBUG screenshot fixture.
final class InMemoryPendingShareStorage: PendingShareStorage {
    var queued: [PendingTikTokShare]
    var resolutions: [String: PendingShareResolution]

    init(queued: [PendingTikTokShare] = [], resolutions: [String: PendingShareResolution] = [:]) {
        self.queued = queued
        self.resolutions = resolutions
    }

    func fetchQueued() -> [PendingTikTokShare] { queued.sorted { $0.dateAdded > $1.dateAdded } }
    func remove(id: String) { queued.removeAll { $0.id == id } }
    func loadResolutions() -> [String: PendingShareResolution] { resolutions }
    func saveResolutions(_ resolutions: [String: PendingShareResolution]) { self.resolutions = resolutions }
}

// MARK: - Location

/// The city (and coordinates, when known) sent with a resolve request.
struct ShareResolveLocation: Equatable {
    var city: String?
    var latitude: Double?
    var longitude: Double?
}

enum ShareLocationProvider {
    /// The city the user typed when a share needed one; reused for later shares.
    static let manualCityKey = "tiktokShareCity"

    /// Same sources as `HomeViewModel.cityForTikTok()`: the device location as
    /// "City, ST" when location access is already granted (never prompts),
    /// otherwise the city the user typed for an earlier share.
    @MainActor
    static func current() async -> ShareResolveLocation {
        let manual = UserDefaults.standard.string(forKey: manualCityKey)
        let status = LocationService.shared.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let resolved = try? await LocationService.shared.currentLocation() else {
            return ShareResolveLocation(city: manual)
        }
        let coordinate = resolved.coordinate
        var city = manual
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
           let locality = placemark.locality, !locality.isEmpty {
            let state = placemark.administrativeArea ?? ""
            city = state.isEmpty ? locality : "\(locality), \(state)"
        }
        return ShareResolveLocation(city: city, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

// MARK: - Model

/// Drives the "Shared from TikTok" row: loads the queue, resolves each share
/// once, and records the outcome so it survives relaunches.
@MainActor
final class PendingSharesModel: ObservableObject {
    @Published private(set) var shares: [PendingTikTokShare] = []
    /// Shares with a resolve call in flight. Guards against duplicate calls when
    /// launch and "became active" overlap.
    @Published private(set) var resolving: Set<String> = []

    private let storage: PendingShareStorage
    private let resolver: TikTokShareResolver
    private let location: () async -> ShareResolveLocation
    private let rememberCity: (String) -> Void

    init(
        storage: PendingShareStorage = AppGroupPendingShareStorage(),
        resolver: @escaping TikTokShareResolver = { url, city, lat, lng in
            await TikTokResolveService.resolve(shareURL: url, city: city, latitude: lat, longitude: lng)
        },
        location: @escaping () async -> ShareResolveLocation = { await ShareLocationProvider.current() },
        rememberCity: @escaping (String) -> Void = {
            UserDefaults.standard.set($0, forKey: ShareLocationProvider.manualCityKey)
        }
    ) {
        self.storage = storage
        self.resolver = resolver
        self.location = location
        self.rememberCity = rememberCity
        refresh()
    }

    /// Re-reads the queue and drops stored results for shares that are gone.
    func refresh() {
        let resolutions = storage.loadResolutions()
        var loaded = storage.fetchQueued()
        for index in loaded.indices {
            loaded[index].resolution = resolutions[loaded[index].id] ?? .pending
        }
        shares = loaded
        let liveIds = Set(loaded.map(\.id))
        let pruned = resolutions.filter { liveIds.contains($0.key) }
        if pruned.count != resolutions.count { storage.saveResolutions(pruned) }
    }

    /// Refreshes, then resolves every share still `.pending` and not in flight.
    /// Call on launch and whenever the app becomes active.
    func refreshAndResolve() async {
        refresh()
        let targets = shares.filter { $0.resolution == .pending && !resolving.contains($0.id) }
        guard !targets.isEmpty else { return }
        // Claim before the first await so an overlapping call skips these.
        resolving.formUnion(targets.map(\.id))
        let context = await location()
        for share in targets {
            await resolve(share, at: context)
        }
    }

    /// Retries a `.needsCity` share with the city the user typed, and remembers
    /// it for later shares.
    func retry(_ share: PendingTikTokShare, city: String) async {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !resolving.contains(share.id) else { return }
        rememberCity(trimmed)
        resolving.insert(share.id)
        await resolve(share, at: ShareResolveLocation(city: trimmed))
    }

    func dismiss(_ share: PendingTikTokShare) {
        storage.remove(id: share.id)
        var resolutions = storage.loadResolutions()
        resolutions[share.id] = nil
        storage.saveResolutions(resolutions)
        shares.removeAll { $0.id == share.id }
        Haptics.soft()
    }

    private func resolve(_ share: PendingTikTokShare, at location: ShareResolveLocation) async {
        let outcome = await resolver(share.urlString, location.city, location.latitude, location.longitude)
        resolving.remove(share.id)

        let resolution: PendingShareResolution
        switch outcome {
        case let .resolved(video, places): resolution = .resolved(video: video, places: places)
        case .needsCity: resolution = .needsCity
        case .unavailable: resolution = .unavailable
        case .retryLater: resolution = .pending
        }

        // The user may have dismissed it while the call was in flight.
        guard let index = shares.firstIndex(where: { $0.id == share.id }) else { return }
        shares[index].resolution = resolution
        var resolutions = storage.loadResolutions()
        resolutions[share.id] = resolution == .pending ? nil : resolution
        storage.saveResolutions(resolutions)
    }
}

#if DEBUG
// MARK: - Screenshot fixture

extension PendingSharesModel {
    /// Launch with `-PendingShareFixture YES` to show one share in every state
    /// without the network or the App Group queue.
    static var fixtureRequested: Bool {
        UserDefaults.standard.bool(forKey: "PendingShareFixture")
    }

    static func fixture() -> PendingSharesModel {
        let now = Date()
        func share(_ id: String, _ minutesAgo: Double) -> PendingTikTokShare {
            PendingTikTokShare(
                id: id,
                urlString: "https://www.tiktok.com/t/\(id)",
                dateAdded: now.addingTimeInterval(-minutesAgo * 60)
            )
        }
        let video = ResolvedShareVideo(
            videoId: "7312345678901234567",
            caption: "The birria tacos everyone is lining up for 🌮",
            canonicalUrl: "https://www.tiktok.com/@foodscout/video/7312345678901234567",
            authorName: "Food Scout",
            thumbnailUrl: nil
        )
        let places = [
            ResolvedSharePlace(placeId: "fixture-teddys", name: "Teddy's Red Tacos", address: "46 Windward Ave, Venice, CA",
                               latitude: 33.99, longitude: -118.47, rating: 4.6, neighborhood: "Venice", tags: ["Mexican"]),
            ResolvedSharePlace(placeId: "fixture-sonoratown", name: "Sonoratown", address: "208 E 8th St, Los Angeles, CA",
                               latitude: 34.04, longitude: -118.25, rating: 4.7, neighborhood: "Downtown", tags: [])
        ]
        let storage = InMemoryPendingShareStorage(
            queued: [share("resolved", 1), share("needscity", 2), share("unavailable", 3),
                     share("nomatch", 4), share("waiting", 5)],
            resolutions: [
                "resolved": .resolved(video: video, places: places),
                "needscity": .needsCity,
                "unavailable": .unavailable,
                "nomatch": .resolved(video: video, places: [])
            ]
        )
        // "waiting" stays pending: the fixture resolver never answers, so the
        // row shows its in-progress state.
        return PendingSharesModel(
            storage: storage,
            resolver: { _, _, _, _ in
                try? await Task.sleep(nanoseconds: .max / 2)
                return .retryLater
            },
            location: { ShareResolveLocation(city: "Los Angeles, CA") },
            rememberCity: { _ in }
        )
    }
}
#endif
