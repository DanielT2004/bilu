//
//  SearchResultsMapView.swift
//  bilu
//

import SwiftUI
import MapKit

private let C = AppTheme.self

struct SearchResultsMapView: View {
    let locations: [SearchLocation]
    let isLoading: Bool
    var onSelect: (SearchLocation) -> Void

    @State private var mapPosition: MapCameraPosition = .automatic

    private var region: MKCoordinateRegion? {
        guard !locations.isEmpty else { return nil }
        let lats = locations.map(\.lat)
        let lngs = locations.map(\.lng)
        let center = CLLocationCoordinate2D(
            latitude:  (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max((lats.max()! - lats.min()!) * 1.5, 0.02),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.5, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        ZStack {
            if let region, !locations.isEmpty {
                Map(position: $mapPosition) {
                    ForEach(locations) { loc in
                        Annotation(loc.placeName, coordinate: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lng)) {
                            pin(for: loc)
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onSelect(loc)
                                }
                        }
                    }
                }
                .onAppear { mapPosition = .region(region) }
                .onChange(of: locations) { _ in
                    if let newRegion = self.region {
                        mapPosition = .region(newRegion)
                    }
                }
            } else {
                placeholder
            }
        }
    }

    // MARK: - Pin

    @ViewBuilder
    private func pin(for loc: SearchLocation) -> some View {
        if loc.isTopRanked {
            ZStack {
                Circle()
                    .fill(C.sage)
                    .frame(width: 38, height: 38)
                    .shadow(color: C.sage.opacity(0.4), radius: 6, y: 3)
                Text("\(loc.rank + 1)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .transition(.scale.combined(with: .opacity))
        } else {
            Circle()
                .fill(C.white)
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(C.sage, lineWidth: 2))
                .shadow(color: C.shadowColor, radius: 3, y: 1)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(C.sageLt)
                    .frame(width: 64, height: 64)
                if isLoading {
                    ProgressView()
                        .tint(C.sage)
                } else {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(C.sage)
                }
            }
            Text(isLoading ? "Finding locations…" : "No locations yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(C.muted)
            if !isLoading {
                Text("Locations appear as TikToks are analyzed")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(C.subtle)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
