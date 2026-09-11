//
//  LocationService.swift
//  bilu
//

import CoreLocation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    /// Every in-flight `currentLocation()` caller waits here. A single CoreLocation
    /// request resolves all of them at once — callers no longer overwrite each
    /// other, which matters now that multiple views (e.g. a list of result cards)
    /// can call this concurrently.
    private var pendingContinuations: [CheckedContinuation<ResolvedLocation, Error>] = []

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Current iOS authorization status — lets callers decide whether to prompt without
    /// reaching into `CLLocationManager` themselves.
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// A resolved location: the raw coordinate plus human-readable labels.
    struct ResolvedLocation {
        let coordinate: CLLocationCoordinate2D
        let cityLabel: String          // locality, e.g. "Los Angeles"
        let neighborhoodLabel: String  // subLocality, falls back to locality
    }

    /// Resolves the user's current location to a coordinate and reverse-geocoded labels.
    /// Safe to call concurrently — every caller waiting when a result (or error) lands
    /// gets that same result.
    func currentLocation() async throws -> ResolvedLocation {
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuations.append(continuation)
            let status = manager.authorizationStatus
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else {
                resumeAll(.failure(LocationError.denied))
            }
        }
    }

    /// Returns a human-readable neighborhood/city string for the current location.
    func currentLocationString() async throws -> String {
        try await currentLocation().neighborhoodLabel
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else if status == .denied || status == .restricted {
                resumeAll(.failure(LocationError.denied))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        Task { @MainActor in
            await reverseGeocode(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            resumeAll(.failure(error))
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            let p = placemarks.first
            let city         = p?.locality ?? p?.administrativeArea ?? "your area"
            let neighborhood = p?.subLocality ?? p?.locality ?? p?.administrativeArea ?? "your area"
            resumeAll(.success(ResolvedLocation(
                coordinate: location.coordinate,
                cityLabel: city,
                neighborhoodLabel: neighborhood
            )))
        } catch {
            resumeAll(.failure(error))
        }
    }

    /// Drains every waiting continuation with the same result. Resuming happens
    /// exactly once per continuation regardless of how many CoreLocation callbacks
    /// fire afterward, since the list is emptied first.
    private func resumeAll(_ result: Result<ResolvedLocation, Error>) {
        let waiters = pendingContinuations
        pendingContinuations = []
        for continuation in waiters {
            continuation.resume(with: result)
        }
    }

    enum LocationError: Error {
        case denied
    }
}
