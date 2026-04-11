//
//  VideoPageView.swift
//  bilu
//
//  Single page in the feed. Owns its VideoPageModel — completely independent
//  from every other page.
//

import SwiftUI
import AVFoundation

struct VideoPageView: View {
    @ObservedObject var feedViewModel: VideoFeedViewModel
    @ObservedObject var pageModel: VideoPageModel
    let index: Int

    private var isActive: Bool { feedViewModel.currentIndex == index }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // This page's dedicated AVPlayer layer
            VideoLayerView(player: pageModel.player)
                .ignoresSafeArea()

            // Tap anywhere to pause/resume (active page only)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isActive else { return }
                    pageModel.togglePlayPause()
                }

            // HUD — only on active page
            if isActive {
                VStack {
                    Spacer()

                    // Pause icon
                    if !pageModel.isPlaying {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }

                    Spacer()

                    // Metadata overlay — taps pass through to pause handler
                    videoMetadataHUD
                        .allowsHitTesting(false)

                    // Counter pill
                    Text("\(index + 1) / \(feedViewModel.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(.bottom, 8)

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.3))
                            Rectangle()
                                .fill(.white)
                                .frame(width: geo.size.width * CGFloat(pageModel.progress))
                                .animation(.linear(duration: 0.05), value: pageModel.progress)
                        }
                    }
                    .frame(height: 3)
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    // MARK: - Metadata HUD

    private var videoMetadataHUD: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Author
            HStack(spacing: 8) {
                AsyncImage(url: URL(string: pageModel.video.author.avatar)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill).clipShape(Circle())
                    } else {
                        Circle().fill(.white.opacity(0.3))
                    }
                }
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5))

                Text("@\(pageModel.video.author.name)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Description
            Text(pageModel.video.desc)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Stats
            HStack(spacing: 10) {
                hudStatPill(icon: "heart.fill", count: pageModel.video.diggCount)
                hudStatPill(icon: "bubble.left.fill", count: pageModel.video.commentCount)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hudStatPill(icon: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11))
            Text(formatCount(count)).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
