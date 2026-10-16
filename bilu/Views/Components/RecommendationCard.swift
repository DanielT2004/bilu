//
//  RecommendationCard.swift
//  bilu
//

import SwiftUI
import CoreLocation

// MARK: - Recommendation card

struct RecommendationCard: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let rec: Recommendation
    var onSelect: (() -> Void)? = nil
    @State private var imageError = false
    @State private var imageDidAppear = false
    @State private var showMapsChoice = false
    @State private var distanceText: String? = nil

    private let fallbackImage = "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo and details are one control so VoiceOver reads the place as
            // a single "opens details" button; "Take Me There" stays separate.
            Button { onSelect?() } label: {
                VStack(alignment: .leading, spacing: 0) {
                    photo
                    details
                        .padding(.horizontal, 18)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.accessibilitySummary(
                name: rec.name, rating: rec.rating, distance: distanceText,
                area: rec.address.map(shortAddress), cuisine: cuisineTag,
                price: priceTag, parking: rec.parkingDisplayText))
            .accessibilityHint("Opens details")
            .accessibilityIdentifier("recommendation-card")

            // Take Me There button
            Button(action: openMaps) {
                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text("Take Me There")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppTheme.onPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .background(AppTheme.sage)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens directions in Maps")
            .padding(.top, 14)
            .padding(.bottom, 18)
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
        .mapsChoiceDialog(isPresented: $showMapsChoice, recommendation: rec)
        .task {
            guard distanceText == nil,
                  let lat = rec.latitude, let lng = rec.longitude,
                  let resolved = try? await LocationService.shared.currentLocation() else { return }
            let userLoc = CLLocation(latitude: resolved.coordinate.latitude, longitude: resolved.coordinate.longitude)
            let placeLoc = CLLocation(latitude: lat, longitude: lng)
            let miles = userLoc.distance(from: placeLoc) / 1609.34
            distanceText = miles < 0.1 ? "<0.1 mi" : String(format: "%.1f mi", miles)
        }
    }

    /// One VoiceOver sentence for the card, e.g.
    /// "Luigi's, rating 4.5, 0.4 mi, Mission, Italian, moderate price, Parking: Street".
    static func accessibilitySummary(name: String, rating: Double?, distance: String?, area: String?,
                                     cuisine: String?, price: String?, parking: String?) -> String {
        var parts = [name]
        if let rating { parts.append("rating " + String(format: "%.1f", rating)) }
        if let distance { parts.append(distance) }
        if let area, !area.isEmpty { parts.append(area) }
        if let cuisine { parts.append(cuisine) }
        if let price, let spoken = spokenPrice(price) { parts.append(spoken) }
        if let parking, !parking.isEmpty {
            parts.append(parking.lowercased().hasPrefix("parking") ? parking : "Parking: \(parking)")
        }
        return parts.joined(separator: ", ")
    }

    /// "$$" reads as "dollar dollar"; say what it means instead.
    static func spokenPrice(_ tier: String) -> String? {
        switch tier {
        case "$":    return "inexpensive"
        case "$$":   return "moderate price"
        case "$$$":  return "expensive"
        case "$$$$": return "very expensive"
        default:     return nil
        }
    }

    // MARK: - Photo

    private var photo: some View {
        ZStack(alignment: .bottom) {
            // Base color so ZStack always has defined size
            AppTheme.surface

            AsyncImage(url: URL(string: imageError ? fallbackImage : (rec.image ?? ""))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .clipped()
                        .opacity(imageDidAppear ? 1 : 0)
                        .onAppear {
                            if reduceMotion { imageDidAppear = true; return }
                            withAnimation(.easeOut(duration: 0.25)) { imageDidAppear = true }
                        }
                case .failure:
                    AppTheme.surface
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(AppTheme.subtle)
                        )
                        .task {
                            if !imageError { Haptics.error() }
                            imageError = true
                        }
                case .empty:
                    AppTheme.surface
                @unknown default:
                    AppTheme.surface
                }
            }
            .onChange(of: rec.image) {
                imageError = false
                imageDidAppear = false
            }

            // Bottom gradient scrim
            LinearGradient(
                colors: [.clear, AppTheme.photoScrim.opacity(0.22)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Name + rating
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(rec.name)
                    .font(AppTheme.title)
                    .foregroundStyle(AppTheme.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                if let rating = rec.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.terracotta)
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.onSurface)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.surface)
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 14)

            // Tags row
            tagsRow
                .padding(.top, 6)

            HStack(spacing: 6) {
                Image(systemName: "parkingsign.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.primaryInk)
                Text(rec.parkingDisplayText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }
            .padding(.top, 9)
        }
    }

    // MARK: - Tags row

    private var tagsRow: some View {
        HStack(spacing: 0) {
            if let distance = distanceText {
                tagText(distance)
                if rec.address != nil { dot() }
            }
            if let address = rec.address {
                tagText(shortAddress(address))
            }

            if let cuisine = cuisineTag {
                dot()
                tagText(cuisine)
            }

            if let price = priceTag {
                dot()
                tagText(price)
            }

            Spacer(minLength: 0)
        }
    }

    private func tagText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.muted)
            .lineLimit(1)
    }

    private func dot() -> some View {
        Circle()
            .fill(AppTheme.subtle)
            .frame(width: 3, height: 3)
            .padding(.horizontal, 6)
    }

    // MARK: - Helpers

    private func openMaps() {
        Haptics.light()
        showMapsChoice = true
    }


    private func shortAddress(_ address: String) -> String {
        // Take just the neighborhood/city portion if long
        let parts = address.components(separatedBy: ",")
        if parts.count >= 2 {
            return parts[parts.count - 2].trimmingCharacters(in: .whitespaces)
        }
        return address
    }

    private var cuisineTag: String? {
        CuisineLabel.infer(name: rec.name, dish: rec.dish, explanation: rec.explanation)
    }

    private var priceTag: String? {
        // Use explanation text to infer price if not directly available
        let text = rec.explanation.lowercased()
        if text.contains("$$$$") || text.contains("upscale") || text.contains("fine dining") { return "$$$$" }
        if text.contains("$$$") || text.contains("mid-range") || text.contains("sit-down") { return "$$$" }
        if text.contains("$$") || text.contains("casual") { return "$$" }
        if text.contains("$") || text.contains("budget") || text.contains("cheap") { return "$" }
        return nil
    }
}
