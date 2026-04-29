//
//  RecommendationCard.swift
//  bilu
//

import SwiftUI

// MARK: - Mock match scores (deterministic per name)

private func mockMatchScore(for name: String) -> Int {
    let seeds: [Int] = [98, 95, 92, 89, 94, 91, 97, 88, 93, 96]
    let idx = abs(name.hashValue) % seeds.count
    return seeds[idx]
}

// MARK: - Recommendation card

struct RecommendationCard: View {
    @Environment(\.openURL) private var openURL
    let rec: Recommendation
    @State private var imageError = false

    private let fallbackImage = "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Photo + overlays ──────────────────────────────────────────
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
                    case .failure:
                        AppTheme.surface
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(AppTheme.subtle)
                            )
                            .task { imageError = true }
                    case .empty:
                        AppTheme.surface
                    @unknown default:
                        AppTheme.surface
                    }
                }
                .onChange(of: rec.image) { _ in imageError = false }

                // Bottom gradient scrim
                LinearGradient(
                    colors: [.clear, .black.opacity(0.22)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .frame(maxWidth: .infinity, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topTrailing) {
                matchBadge
                    .padding(.top, 12)
                    .padding(.trailing, 12)
            }

            // ── Metadata ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                // Name + rating
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(rec.name)
                        .font(.custom("Georgia", size: 22))
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

                // Take Me There button
                Button(action: openMaps) {
                    HStack(spacing: 7) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 13))
                        Text("Take Me There")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(AppTheme.terracotta)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
    }

    // MARK: - Match badge

    private var matchBadge: some View {
        let score = mockMatchScore(for: rec.name)
        return Text("\(score)% Match")
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppTheme.sage)
            .clipShape(Capsule())
    }

    // MARK: - Tags row

    private var tagsRow: some View {
        HStack(spacing: 0) {
            if let address = rec.address {
                let distanceMock = mockDistance(for: rec.name)
                tagText(distanceMock)
                dot()
                tagText(shortAddress(address))
            } else {
                tagText(mockDistance(for: rec.name))
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
        guard let url = URL(string: rec.mapsUrl) else { return }
        openURL(url)
    }

    private func mockDistance(for name: String) -> String {
        let vals = ["0.3 mi", "0.8 mi", "1.2 mi", "0.5 mi", "1.7 mi", "2.1 mi"]
        return vals[abs(name.hashValue) % vals.count]
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
        // Derive a cuisine label from the dish or explanation
        let text = (rec.dish + " " + rec.explanation).lowercased()
        if text.contains("italian") || text.contains("pasta") || text.contains("pizza") { return "Italian" }
        if text.contains("mexican") || text.contains("taco") || text.contains("burrito") { return "Mexican" }
        if text.contains("japanese") || text.contains("sushi") || text.contains("ramen") { return "Japanese" }
        if text.contains("thai") { return "Thai" }
        if text.contains("indian") { return "Indian" }
        if text.contains("chinese") { return "Chinese" }
        if text.contains("american") || text.contains("burger") || text.contains("bbq") { return "American" }
        if text.contains("french") || text.contains("bistro") || text.contains("brasserie") { return "French" }
        if text.contains("mediterranean") || text.contains("greek") { return "Mediterranean" }
        if text.contains("farm") || text.contains("organic") { return "Farm-to-Table" }
        if text.contains("bakery") || text.contains("pastry") || text.contains("coffee") { return "Café & Bakery" }
        return nil
    }

    private var priceTag: String? {
        // Use explanation text to infer price if not directly available
        let text = rec.explanation.lowercased()
        if text.contains("$$$$") || text.contains("upscale") || text.contains("fine dining") { return "$$$$" }
        if text.contains("$$$") || text.contains("mid-range") || text.contains("sit-down") { return "$$$" }
        if text.contains("$$") || text.contains("casual") { return "$$" }
        if text.contains("$") || text.contains("budget") || text.contains("cheap") { return "$" }
        // Mock fallback based on name hash
        let tiers = ["$$", "$$$", "$$", "$$$", "$$$$"]
        return tiers[abs(rec.name.hashValue) % tiers.count]
    }
}
