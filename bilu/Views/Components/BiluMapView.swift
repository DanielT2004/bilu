//
//  BiluMapView.swift
//  bilu
//

import SwiftUI
import MapKit

struct BiluMapView: View {
    let recommendations: [Recommendation]
    var isLoading: Bool = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var revealedPinCount: Int = 0
    @State private var pendingMapsRec: Recommendation?

    private var annotated: [(index: Int, rec: Recommendation, coord: CLLocationCoordinate2D)] {
        recommendations.enumerated().compactMap { i, rec in
            guard let lat = rec.latitude, let lng = rec.longitude else { return nil }
            return (i + 1, rec, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
    }

    private var region: MKCoordinateRegion? {
        guard !annotated.isEmpty else { return nil }
        let lats = annotated.map(\.coord.latitude)
        let lngs = annotated.map(\.coord.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.02),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.5, 0.02)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        if isLoading {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surface)
                .frame(height: 220)
                .overlay(
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(AppTheme.muted)
                        Text("Loading map...")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.muted)
                    }
                )
                .shadow(color: AppTheme.shadowColor, radius: 8, y: 3)
        } else if let region, !annotated.isEmpty {
            Map(position: $mapPosition) {
                ForEach(annotated, id: \.index) { item in
                    Annotation(item.rec.name, coordinate: item.coord) {
                        Button {
                            Haptics.light()
                            pendingMapsRec = item.rec
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(AppTheme.terracotta)
                                    .frame(width: 34, height: 34)
                                    .shadow(color: AppTheme.terracotta.opacity(0.4), radius: 4, y: 2)
                                Text("\(item.index)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .scaleEffect(item.index <= revealedPinCount ? 1 : 0.001)
                            .opacity(item.index <= revealedPinCount ? 1 : 0)
                            .animation(AnimationProfile.listReveal.animation(reduceMotion: reduceMotion),
                                       value: revealedPinCount)
                        }
                    }
                }
            }
            .onAppear { mapPosition = .region(region) }
            .onChange(of: annotated.count) { _ in mapPosition = .region(region) }
            .task(id: annotated.count) { await runPinStagger() }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 10, y: 4)
            .onTapGesture { }
            .mapsChoiceDialog(item: $pendingMapsRec)
        }
    }

    private func runPinStagger() async {
        let total = annotated.count
        guard total > 0 else { return }
        if reduceMotion {
            revealedPinCount = total
            return
        }
        revealedPinCount = 0
        for i in 1...total {
            try? await Task.sleep(nanoseconds: 80_000_000)
            if Task.isCancelled { return }
            revealedPinCount = i
        }
    }
}
