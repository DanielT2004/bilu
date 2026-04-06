//
//  RecommendationCard.swift
//  bilu
//RecommendationCard

import SwiftUI

struct RecommendationCard: View {
    @Environment(\.openURL) private var openURL
    let rec: Recommendation
    @State private var imageError = false

    private let fallbackImage = "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80"

    var body: some View {
        let _ = {
            #if DEBUG
            print("[RecommendationCard] LOADING IMAGE | name=\(rec.name) | url=\(rec.image)")
            #endif
        }()
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: imageError ? fallbackImage : rec.image)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure(let error):
                        Color.gray.opacity(0.2)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.gray)
                            )
                            .task {
                                imageError = true
                                #if DEBUG
                                print(
                                    "[RecommendationCard] IMAGE_LOAD_FAILED → using stock fallback | name=\(rec.name) | error=\(error.localizedDescription) | url=\(String(rec.image.prefix(120)))…"
                                )
                                #endif
                            }
                    case .empty:
                        Color.gray.opacity(0.2)
                    @unknown default:
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(height: 180)
                .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Text(rec.dish)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(rec.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))

                Text(rec.explanation)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "64748B"))
                    .lineLimit(3)

                Button(action: openMaps) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                        Text("Take Me There")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(hex: "8B5CF6"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .background(Color.white.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
    }

    private func openMaps() {
        guard let url = URL(string: rec.mapsUrl) else { return }
        openURL(url)
    }
}
