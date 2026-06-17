//
//  LocationService.swift
//  bilu
//

import CoreLocation

@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<ResolvedLocation, Error>?

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
    func currentLocation() async throws -> ResolvedLocation {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let status = manager.authorizationStatus
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            } else {
                continuation.resume(throwing: LocationError.denied)
                self.continuation = nil
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
                continuation?.resume(throwing: LocationError.denied)
                continuation = nil
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
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func reverseGeocode(_ location: CLLocation) async {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            let p = placemarks.first
            let city         = p?.locality ?? p?.administrativeArea ?? "your area"
            let neighborhood = p?.subLocality ?? p?.locality ?? p?.administrativeArea ?? "your area"
            continuation?.resume(returning: ResolvedLocation(
                coordinate: location.coordinate,
                cityLabel: city,
                neighborhoodLabel: neighborhood
            ))
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    enum LocationError: Error {
        case denied
    }
}
