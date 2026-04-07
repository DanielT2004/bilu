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
    @State private var mapPosition: MapCameraPosition = .automatic

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
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: "F1F5F9"))
                .frame(height: 220)
                .overlay(
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color(hex: "8B5CF6"))
                        Text("Loading map...")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "94A3B8"))
                    }
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        } else if let region, !annotated.isEmpty {
            Map(position: $mapPosition) {
                ForEach(annotated, id: \.index) { item in
                    Annotation(item.rec.name, coordinate: item.coord) {
                        Button {
                            if let url = URL(string: item.rec.mapsUrl) {
                                openURL(url)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: "8B5CF6"))
                                    .frame(width: 34, height: 34)
                                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                                Text("\(item.index)")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                }
            }
            .onAppear { mapPosition = .region(region) }
            .onChange(of: annotated.count) { _ in mapPosition = .region(region) }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.07), radius: 10, y: 4)
        }
    }
}
