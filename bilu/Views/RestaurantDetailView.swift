//
//  RestaurantDetailView.swift
//  bilu
//

import SwiftUI
import MapKit

// MARK: - Tab enum

private enum DetailTab: Int, CaseIterable {
    case overview, insights, media, reviews
    var label: String {
        ["Overview", "Insights", "Media", "Reviews"][rawValue]
    }
}

// MARK: - View

struct RestaurantDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let rec: Recommendation
    var tikTokVideos: [TikTokVideo] = []

    @State private var currentPhoto = 0
    @State private var selectedTab: DetailTab = .overview
    @State private var ivenBeenHere = false
    @State private var swipeForward = true
    @State private var playerStartIndex: Int = 0
    @State private var showingVideoPlayer = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    photoGallery
                    contentSheet
                }
            }
            .ignoresSafeArea(edges: .top)
            topBar
        }
        .background(AppTheme.surface.ignoresSafeArea())
        .fullScreenCover(isPresented: $showingVideoPlayer) {
            VideoFeedView(videos: tikTokVideos, startIndex: playerStartIndex)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.sage)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("bilu")
                .font(.custom("Georgia", size: 20))
                .italic()
                .foregroundStyle(AppTheme.sage)
            Spacer()
            HStack(spacing: 6) {
                topBarIcon("magnifyingglass")
                topBarIcon("bookmark")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func topBarIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(AppTheme.sage)
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }

    // MARK: - Photo data

    private var allPhotos: [String] {
        if let photos = rec.photos, !photos.isEmpty { return photos }
        if let img = rec.image { return [img] }
        return []
    }

    private var communityPhotos: [String] {
        guard let photos = rec.photos, photos.count > 1 else { return [] }
        return Array(photos.dropFirst())
    }

    // MARK: - Photo gallery (hero) — clean bottom, no fade

    private var photoGallery: some View {
        ZStack(alignment: .bottomTrailing) {
            galleryImages
            galleryCounter
        }
        .clipped()
    }

    private var galleryImages: some View {
        Group {
            if allPhotos.isEmpty {
                AppTheme.sageLt
            } else {
                TabView(selection: $currentPhoto) {
                    ForEach(Array(allPhotos.enumerated()), id: \.offset) { idx, url in
                        AsyncImage(url: URL(string: url)) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                AppTheme.sageLt
                            }
                        }
                        .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360, maxHeight: 360)
    }

    private var galleryCounter: some View {
        Group {
            if allPhotos.count > 1 {
                Text("\(currentPhoto + 1)/\(allPhotos.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0, opacity: 0.45))
                    .clipShape(Capsule())
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Content sheet

    private var contentSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Name + address ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                // Dish tag
                Text(rec.dish)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.sage)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.sageLt)
                    .clipShape(Capsule())

                Text(rec.name)
                    .font(.custom("Georgia", size: 30))
                    .fontWeight(.bold)
                    .italic()
                    .foregroundStyle(AppTheme.sage)
                    .fixedSize(horizontal: false, vertical: true)

                if let address = rec.address {
                    Text(address)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)

            // ── Status / Rating / Distance row ────────────────────────
            statsHeaderRow
                .padding(.horizontal, 24)
                .padding(.top, 20)

            // ── I've been here + bookmark ─────────────────────────────
            ctaRow
                .padding(.horizontal, 24)
                .padding(.top, 20)

            // ── Tab bar ───────────────────────────────────────────────
            tabBar
                .padding(.top, 24)
                .zIndex(1)

            // ── Swipeable tab content ─────────────────────────────────
            tabContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.white)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
        )
        .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: -6)
        .padding(.top, -28)
    }

    // MARK: - Stats header row (Status / Rating / Distance)

    private var statsHeaderRow: some View {
        HStack(spacing: 0) {
            // Status
            VStack(alignment: .leading, spacing: 4) {
                Text("Status")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.muted)
                if let open = rec.isOpen {
                    HStack(spacing: 4) {
                        Text(open ? "Open now" : "Closed")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(open ? AppTheme.sage : AppTheme.destructive)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Rating
            VStack(alignment: .center, spacing: 4) {
                Text("Rating")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.muted)
                if let r = rec.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.terracotta)
                        Text(String(format: "%.1f", r))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.onSurface)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Distance (mocked)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Distance")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.muted)
                Text(mockDistance)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.onSurface)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var mockDistance: String {
        let vals = ["0.3 mi", "0.8 mi", "1.2 mi", "0.5 mi", "1.7 mi", "2.1 mi", "4.2 mi"]
        return vals[abs(rec.name.hashValue) % vals.count]
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: 12) {
            // "I've been here" pill button
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    ivenBeenHere.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: ivenBeenHere ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 16))
                    Text("I've been here")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(ivenBeenHere ? AppTheme.terracotta : AppTheme.sage)
                .clipShape(Capsule())
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: ivenBeenHere)
            }
            .buttonStyle(.plain)

            // Bookmark circle
            Button(action: {}) {
                Image(systemName: "bookmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)
                    .frame(width: 52, height: 52)
                    .background(Color(hex: "eae8e3"))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.rawValue) { tab in
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 8) {
                            Text(tab.label)
                                .font(.system(size: 11, weight: .medium))
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(selectedTab == tab ? AppTheme.sage : AppTheme.subtle)
                                .animation(.easeInOut(duration: 0.2), value: selectedTab)

                            // Active underline
                            Rectangle()
                                .fill(selectedTab == tab ? AppTheme.sage : Color.clear)
                                .frame(height: 2)
                                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selectedTab)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            // Full-width hairline — only visible on inactive areas via contrast
            Rectangle()
                .fill(AppTheme.sageLt)
                .frame(height: 1)
        }
    }

    // MARK: - Tab content (swipeable)

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .overview:  overviewTab
            case .insights:  insightsTab
            case .media:     mediaTab
            case .reviews:   reviewsTab
            }
        }
        .id(selectedTab)
        .transition(.asymmetric(
            insertion: .move(edge: swipeForward ? .trailing : .leading).combined(with: .opacity),
            removal:   .move(edge: swipeForward ? .leading  : .trailing).combined(with: .opacity)
        ))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let tabs = DetailTab.allCases
                    guard let idx = tabs.firstIndex(of: selectedTab) else { return }
                    if value.translation.width < -40, idx < tabs.count - 1 {
                        swipeForward = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedTab = tabs[idx + 1]
                        }
                    } else if value.translation.width > 40, idx > 0 {
                        swipeForward = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedTab = tabs[idx - 1]
                        }
                    }
                }
        )
    }

    // MARK: - ══ OVERVIEW TAB ══

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 28) {
            actionButtonsRow
            vibeCheckCard
            if !communityPhotos.isEmpty {
                communityMomentsSection
            }
            proTipsSection
            visitSection
            if rec.latitude != nil && rec.longitude != nil {
                miniMapSection
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action buttons

    private var actionButtonsRow: some View {
        HStack(spacing: 12) {
            primaryActionButton
            if let phone = rec.phone {
                Button(action: { dialPhone(phone) }) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.onSurface)
                        .frame(width: 52, height: 52)
                        .background(Color(hex: "eae8e3"))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Button(action: openMaps) {
                Image(systemName: "map")
                    .font(.system(size: 18))
                    .foregroundStyle(AppTheme.onSurface)
                    .frame(width: 52, height: 52)
                    .background(Color(hex: "eae8e3"))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var primaryActionButton: some View {
        Group {
            if let website = rec.website, let url = URL(string: website) {
                Button(action: { openURL(url) }) { websiteLabel }
                    .buttonStyle(.plain)
            } else {
                Button(action: openMaps) { directionsLabel }
                    .buttonStyle(.plain)
            }
        }
    }

    private var websiteLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe").font(.system(size: 15))
            Text("Website").font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.sage)
        .clipShape(Capsule())
    }

    private var directionsLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill").font(.system(size: 15))
            Text("Get Directions").font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.sage)
        .clipShape(Capsule())
    }

    // MARK: - AI Vibe check

    private var vibeCheckCard: some View {
        VStack(spacing: 10) {
            Text("\"" + rec.explanation + "\"")
                .font(.custom("Georgia", size: 16))
                .italic()
                .foregroundStyle(Color(hex: "434a2b"))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Circle().fill(AppTheme.sage).frame(width: 7, height: 7)
                Text("AI VIBE CHECK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.sageLt.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Community Moments

    private var communityMomentsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("More Photos")
                    .font(.custom("Georgia", size: 18))
                    .foregroundStyle(AppTheme.onSurface)
                Spacer()
                Text("View All")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.sage)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(communityPhotos.enumerated()), id: \.offset) { _, url in
                        communityThumb(url: url)
                    }
                }
            }
        }
    }

    private func communityThumb(url: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: url)) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    AppTheme.sageLt
                }
            }
            .frame(width: 130, height: 200)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Image(systemName: "play.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .padding(6)
                .background(Color(white: 0, opacity: 0.4))
                .clipShape(Circle())
                .padding(10)
        }
    }

    // MARK: - Pro Tips

    private var proTipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(AppTheme.terracotta)
                Text("Pro Tips")
                    .font(.custom("Georgia", size: 18))
                    .foregroundStyle(AppTheme.onSurface)
            }
            proTipRow("01", "Arrive early or book ahead — popular spots fill up fast on weekends.")
            proTipRow("02", "Ask your server about the chef's daily special — it's usually the best thing on the menu.")
            proTipRow("03", "Check Google Maps for the latest hours before heading out.")
        }
        .padding(20)
        .background(Color(hex: "f5f3ee"))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func proTipRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(num)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.terracotta)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "45483e"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Visit section

    private var visitSection: some View {
        Group {
            if rec.address != nil || rec.isOpen != nil || rec.phone != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Visit")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.sage)
                    if let address = rec.address {
                        Button(action: openMaps) {
                            Text(address)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: "45483e"))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    if let open = rec.isOpen {
                        Text(open ? "Open now" : "Currently closed")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(open ? AppTheme.sage : AppTheme.destructive)
                    }
                    if let phone = rec.phone {
                        Button(action: { dialPhone(phone) }) {
                            HStack(spacing: 6) {
                                Image(systemName: "phone.fill").font(.system(size: 13))
                                Text(phone).font(.system(size: 14))
                            }
                            .foregroundStyle(AppTheme.sage)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Mini map

    private var miniMapSection: some View {
        Group {
            if let lat = rec.latitude, let lng = rec.longitude {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                let region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                )
                Map(position: .constant(.region(region))) {
                    Annotation(rec.name, coordinate: coord) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.terracotta)
                                .frame(width: 30, height: 30)
                                .shadow(color: AppTheme.terracotta.opacity(0.4), radius: 4, y: 2)
                            Image(systemName: "fork.knife")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(true)
                .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: AppTheme.shadowColor, radius: 10, y: 4)
            }
        }
    }

    // MARK: - ══ INSIGHTS TAB ══

    private var insightsTab: some View {
        VStack(spacing: 0) {
            stubCard(icon: "sparkles", message: "AI-powered insights\ncoming soon")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - ══ MEDIA TAB ══

    private var mediaTab: some View {
        VStack(alignment: .leading, spacing: 28) {
            if tikTokVideos.isEmpty {
                stubCard(icon: "video.slash", message: "Loading TikTok clips…")
            } else {
                // Featured hero video
                featuredVideoCard(tikTokVideos[0], index: 0)

                // Other Posts list
                if tikTokVideos.count > 1 {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Other Posts")
                            .font(.custom("Georgia", size: 22))
                            .foregroundStyle(AppTheme.onSurface)

                        let others = Array(tikTokVideos.dropFirst().enumerated())
                        ForEach(others, id: \.offset) { idx, video in
                            otherPostRow(video, playerIndex: idx + 1)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .animation(
                                    .spring(response: 0.4, dampingFraction: 0.8).delay(Double(idx) * 0.07),
                                    value: tikTokVideos.count
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Featured 9:16 hero card
    private func featuredVideoCard(_ video: TikTokVideo, index: Int) -> some View {
        Button {
            playerStartIndex = index
            showingVideoPlayer = true
        } label: {
            ZStack(alignment: .bottom) {
                // Thumbnail — fixed frame, fills and clips to card bounds
                AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AppTheme.sageLt
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Gradient overlay — bottom heavy
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .bottom,
                    endPoint: .center
                )

                // Top vignette
                VStack {
                    LinearGradient(
                        colors: [.black.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.35)
                    )
                    .frame(height: 80)
                    Spacer()
                }

                // Centered play button
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())

                // Bottom metadata
                VStack(alignment: .leading, spacing: 10) {
                    // Author row
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: video.author.avatar)) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                                    .clipShape(Circle())
                            } else {
                                Circle().fill(AppTheme.sageLt)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 1.5))

                        Text("@\(video.author.name)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    // Description
                    Text(video.desc)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    // Stats pills
                    HStack(spacing: 10) {
                        statPill(icon: "heart.fill", count: video.diggCount)
                        statPill(icon: "bubble.left.fill", count: video.commentCount)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Fixed height drives the ZStack — image fills within it
            .frame(maxWidth: .infinity)
            .frame(height: 460)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func statPill(icon: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(formatCount(count))
                .font(.system(size: 12, weight: .semibold))
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

    // Other Posts row card
    private func otherPostRow(_ video: TikTokVideo, playerIndex: Int) -> some View {
        Button {
            playerStartIndex = playerIndex
            showingVideoPlayer = true
        } label: {
            HStack(spacing: 14) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            AppTheme.sageLt
                        }
                    }
                    .frame(width: 96, height: 128)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Small play button
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .padding(8)
                }

                // Text content
                VStack(alignment: .leading, spacing: 10) {
                    Text(video.desc)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(AppTheme.onSurface)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    // Location chip
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.sage)
                        Text(rec.address.map { shortAddress($0) } ?? rec.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.sage)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.sageLt)
                    .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(AppTheme.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 16, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private func shortAddress(_ address: String) -> String {
        let parts = address.components(separatedBy: ",")
        if parts.count >= 2 { return parts[parts.count - 2].trimmingCharacters(in: .whitespaces) }
        return address
    }

    // MARK: - ══ REVIEWS TAB ══

    private var reviewsTab: some View {
        VStack(spacing: 0) {
            stubCard(icon: "quote.bubble", message: "Guest reviews\ncoming soon")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stubCard(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.sageMd)
            Text(message)
                .font(.custom("Georgia", size: 16))
                .italic()
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Helpers

    private func dialPhone(_ phone: String) {
        let cleaned = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel://\(cleaned)") { openURL(url) }
    }

    private func openMaps() {
        guard let url = URL(string: rec.mapsUrl) else { return }
        openURL(url)
    }
}
