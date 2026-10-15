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
    let videos: [TikTokVideo]
    var onSelect: (SearchLocation) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mapPosition: MapCameraPosition = .region(SearchResultsMapView.wideUSARegion)

    private static let wideUSARegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.0),
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
    )

    private var cityRegion: MKCoordinateRegion? {
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
        ZStack(alignment: .top) {
            Map(position: $mapPosition) {
                ForEach(Array(locations.enumerated()), id: \.element.id) { index, loc in
                    Annotation(loc.placeName, coordinate: CLLocationCoordinate2D(latitude: loc.lat, longitude: loc.lng)) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelect(loc)
                        } label: {
                            MapPinView(location: loc, index: index)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(loc.isTopRanked ? "Number \(loc.rank + 1), \(loc.placeName)" : loc.placeName)
                        .accessibilityHint("Shows videos for this place")
                    }
                }
            }
            .onAppear {
                // If locations are already loaded when the map first becomes visible
                // (e.g. user finished loading on Videos tab and then tapped Map),
                // snap to the city instantly. The animated fly-over only fires via
                // onChange below, when locations arrive while the map is on-screen.
                if !locations.isEmpty, let target = cityRegion {
                    mapPosition = .region(target)
                }
            }
            .onChange(of: locations) { _, newLocations in
                guard !newLocations.isEmpty, let target = cityRegion else { return }
                // Reduce Motion: jump straight to the city instead of a 1.4 s fly-over.
                let flyDuration = reduceMotion ? 0 : 1.4
                if reduceMotion {
                    mapPosition = .region(target)
                } else {
                    withAnimation(.easeInOut(duration: flyDuration)) {
                        mapPosition = .region(target)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + flyDuration) {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                }
            }

            if isLoading {
                LoadingStatusTicker(videos: videos)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            } else if locations.isEmpty {
                emptyOverlay
            }
        }
    }

    // MARK: - Empty state overlay

    private var emptyOverlay: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(C.primaryInk)
                .frame(width: 52, height: 52)
                .background(Circle().fill(C.sageLt))
            Text("no spots yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(C.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: C.shadowColor, radius: 10, y: 3)
        .padding(.top, 80)
    }
}

// MARK: - Pin view (per-pin stagger animation)

private struct MapPinView: View {
    let location: SearchLocation
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0

    var body: some View {
        Group {
            if location.isTopRanked {
                ZStack {
                    Circle()
                        .fill(C.sage)
                        .frame(width: 38, height: 38)
                        .shadow(color: C.sage.opacity(0.4), radius: 6, y: 3)
                    Text("\(location.rank + 1)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(C.onPrimary)
                }
            } else {
                Circle()
                    .fill(C.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(C.sage, lineWidth: 2))
                    .shadow(color: C.shadowColor, radius: 3, y: 1)
            }
        }
        .scaleEffect(scale)
        // Small dots keep their look but get a 44 pt hit area.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .onAppear {
            // Reduce Motion: pins appear at once, no staggered pop-in.
            if reduceMotion {
                scale = 1
                return
            }
            let delay = Double(index) * 0.12
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(delay)) {
                scale = 1
            }
            if index < 6 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
        }
    }
}
