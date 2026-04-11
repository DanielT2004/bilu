//
//  RecommendationCard.swift
//  bilu
//

import SwiftUI

struct RecommendationCard: View {
    let rec: Recommendation
    let onTap: () -> Void
    @State private var currentPhoto = 0
    @State private var imageErrors: Set<Int> = []

    private let fallbackImage = "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80"

    private var photos: [String] {
        if let p = rec.photos, !p.isEmpty { return p }
        if let img = rec.image { return [img] }
        return [fallbackImage]
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // ── Swipeable photo gallery ──────────────────────
                ZStack(alignment: .bottom) {
                    TabView(selection: $currentPhoto) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                            AsyncImage(url: URL(string: imageErrors.contains(i) ? fallbackImage : url)) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().aspectRatio(contentMode: .fill)
                                case .failure:
                                    Color.gray.opacity(0.2)
                                        .overlay(Image(systemName: "photo").font(.largeTitle).foregroundStyle(.gray))
                                        .task {
                                            imageErrors.insert(i)
                                            #if DEBUG
                                            print("[RecommendationCard] photo \(i) failed | name=\(rec.name) | url=\(url.prefix(80))")
                                            #endif
                                        }
                                case .empty:
                                    Color.gray.opacity(0.15)
                                @unknown default:
                                    Color.gray.opacity(0.15)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                    .onChange(of: rec.photos) { _ in imageErrors = [] }

                    // Gradient + bottom row overlay
                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

                    HStack(alignment: .bottom) {
                        Text(rec.dish)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.leading, 14)
                            .padding(.bottom, 12)

                        Spacer()

                        // Photo counter pill — always shown so user knows to swipe
                        HStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 10))
                            Text("\(currentPhoto + 1)/\(photos.count)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())
                        .padding(.trailing, 10)
                        .padding(.bottom, 10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                // ── Info section ─────────────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(rec.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: "0F172A"))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if let rating = rec.rating {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: "3d5a2e"))
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color(hex: "3d5a2e"))
                            }
                        }
                    }

                    Text(rec.explanation)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "64748B"))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Text("View details")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: "3d5a2e"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "3d5a2e"))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .onAppear {
            #if DEBUG
            print("[RecommendationCard] APPEAR \"\(rec.name)\": photos=\(photos.count) rating=\(rec.rating.map(String.init) ?? "nil") reviews=\(rec.reviews?.count ?? 0) tips=\(rec.tips?.count ?? 0)")
            #endif
        }
    }
}
