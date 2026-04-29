//
//  LocationVideosSheet.swift
//  bilu
//

import SwiftUI

private let C = AppTheme.self

struct LocationVideosSheet: View {
    let location: SearchLocation
    let videos: [TikTokVideo]
    var onSelectVideo: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            grabHandle
            header
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                        videoCard(video: video)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                onSelectVideo(index)
                            }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(C.surface)
        .presentationDetents([.fraction(0.5), .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
    }

    // MARK: - Subviews

    private var grabHandle: some View {
        Capsule()
            .fill(C.muted.opacity(0.35))
            .frame(width: 38, height: 4)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if location.isTopRanked {
                ZStack {
                    Circle()
                        .fill(C.sage)
                        .frame(width: 36, height: 36)
                    Text("\(location.rank + 1)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(C.sageLt)
                        .frame(width: 36, height: 36)
                    Image(systemName: "mappin")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(C.sage)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(location.placeName)
                    .font(.custom("Georgia", size: 20))
                    .foregroundColor(C.onSurface)
                    .lineLimit(2)
                if !location.address.isEmpty {
                    Text(location.address)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(C.muted)
                        .lineLimit(2)
                }
                Text("\(videos.count) TikTok\(videos.count == 1 ? "" : "s") · \(formatViews(location.totalViews)) views")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(C.subtle)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }

    private func videoCard(video: TikTokVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    Rectangle()
                        .fill(C.sageLt)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(C.sage)
                                .font(.system(size: 20))
                        )
                @unknown default:
                    Rectangle().fill(C.sageLt)
                }
            }
            .frame(width: 150, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 3) {
                    Image(systemName: "play.fill").font(.system(size: 8))
                    Text(formatViews(video.viewCount))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45))
                .clipShape(Capsule())
                .padding(8)
            }

            Text("@\(video.author.name)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(C.muted)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
        }
    }

    private func formatViews(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return "\(n / 1_000_000)M"
        case 1_000...:     return "\(n / 1_000)k"
        default:           return "\(n)"
        }
    }
}
