//
//  MapsLauncher.swift
//  bilu
//

import SwiftUI
import UIKit

enum MapsLauncher {
    static func appleMapsURL(for rec: Recommendation) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")!
        var items: [URLQueryItem] = []
        if let lat = rec.latitude, let lng = rec.longitude {
            items.append(URLQueryItem(name: "ll", value: "\(lat),\(lng)"))
            items.append(URLQueryItem(name: "q", value: rec.name))
        } else {
            items.append(URLQueryItem(name: "q", value: queryString(for: rec)))
        }
        components.queryItems = items
        return components.url
    }

    static func googleMapsURL(for rec: Recommendation) -> URL? {
        if googleMapsAppInstalled() {
            var components = URLComponents(string: "comgooglemaps://")!
            var items: [URLQueryItem] = []
            items.append(URLQueryItem(name: "q", value: rec.name))
            if let lat = rec.latitude, let lng = rec.longitude {
                items.append(URLQueryItem(name: "center", value: "\(lat),\(lng)"))
            }
            components.queryItems = items
            if let url = components.url { return url }
        }
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        var items: [URLQueryItem] = [URLQueryItem(name: "api", value: "1")]
        if let lat = rec.latitude, let lng = rec.longitude {
            items.append(URLQueryItem(name: "query", value: "\(lat),\(lng)"))
        } else {
            items.append(URLQueryItem(name: "query", value: queryString(for: rec)))
        }
        components.queryItems = items
        return components.url
    }

    static func googleMapsAppInstalled() -> Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    private static func queryString(for rec: Recommendation) -> String {
        if let address = rec.address, !address.isEmpty {
            return "\(rec.name), \(address)"
        }
        return rec.name
    }
}

private struct MapsChoiceDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let recommendation: Recommendation
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.confirmationDialog(
            recommendation.name,
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Apple Maps") {
                Haptics.medium()
                if let url = MapsLauncher.appleMapsURL(for: recommendation) {
                    openURL(url)
                }
            }
            Button("Google Maps") {
                Haptics.medium()
                if let url = MapsLauncher.googleMapsURL(for: recommendation) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Open directions in")
        }
    }
}

private struct MapsChoiceDialogItemModifier: ViewModifier {
    @Binding var item: Recommendation?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.confirmationDialog(
            item?.name ?? "",
            isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            ),
            titleVisibility: .visible,
            presenting: item
        ) { rec in
            Button("Apple Maps") {
                Haptics.medium()
                if let url = MapsLauncher.appleMapsURL(for: rec) {
                    openURL(url)
                }
            }
            Button("Google Maps") {
                Haptics.medium()
                if let url = MapsLauncher.googleMapsURL(for: rec) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Open directions in")
        }
    }
}

extension View {
    func mapsChoiceDialog(isPresented: Binding<Bool>, recommendation: Recommendation) -> some View {
        modifier(MapsChoiceDialogModifier(isPresented: isPresented, recommendation: recommendation))
    }

    func mapsChoiceDialog(item: Binding<Recommendation?>) -> some View {
        modifier(MapsChoiceDialogItemModifier(item: item))
    }
}
