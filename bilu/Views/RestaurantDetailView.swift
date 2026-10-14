//
//  RestaurantDetailView.swift
//  bilu
//

import SwiftUI
import MapKit

// MARK: - Tab enum

private enum DetailTab: Int, CaseIterable {
    case overview, media, insights, reviews
    var label: String {
        ["Overview", "Media", "Insights", "Reviews"][rawValue]
    }
    var icon: String {
        ["square.grid.2x2", "play.rectangle.fill", "sparkles", "quote.bubble"][rawValue]
    }
}

// MARK: - View

struct RestaurantDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: SavedPlacesStore
    let rec: Recommendation
    /// Taste tags recorded on the `SavedPlace` if the user saves from this sheet
    /// (survey food feelings + sub-options when opened from results).
    var tags: [String]? = nil
    let fetchTikToks: () async -> [TikTokVideo]

    @State private var tikTokVideos: [TikTokVideo] = []
    @State private var isFetchingTikTok = false
    @State private var currentPhoto = 0
    @State private var selectedTab: DetailTab = .overview
    @State private var ivenBeenHere = false
    @State private var swipeForward = true
    @State private var feedViewModel: VideoFeedViewModel? = nil
    @State private var prewarmedFeedViewModel: VideoFeedViewModel? = nil
    @State private var showingAllPhotos = false
    @State private var galleryPhotos: [String] = []
    @State private var isFetchingAllPhotos = false
    @State private var didRequestGalleryPhotos = false
    @State private var didRequestTikTok = false
    @State private var vibeCheckVisible: Bool = false
    @State private var bookmarkPhase: BookmarkPhase = .idle
    @State private var bookmarkSaved: Bool = false
    @State private var wantToGoSaved: Bool = false
    @State private var showMapsChoice = false
    @State private var distanceText: String = "—"
    @GestureState private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum BookmarkPhase { case idle, pressing }

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
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.translation.height > 0 {
                        state = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                }
        )
        .fullScreenCover(item: $feedViewModel) { vm in
            VideoFeedView(viewModel: vm)
        }
        .sheet(isPresented: $showingAllPhotos) {
            AllPhotosView(heroPhoto: rec.image, galleryPhotos: galleryPhotos, name: rec.name)
        }
        .mapsChoiceDialog(isPresented: $showMapsChoice, recommendation: rec)
        .onAppear {
            refreshSavedState()
            ivenBeenHere = VisitedPlacesStore.isVisited(rec.identityKey)
        }
        .onChange(of: selectedTab) { _, tab in
            guard tab == .media || tab == .insights else { return }
            Task { await loadTikToksIfNeeded() }
        }
        .task {
            guard let lat = rec.latitude, let lng = rec.longitude else { return }
            guard let resolved = try? await LocationService.shared.currentLocation() else { return }
            let userLocation = CLLocation(latitude: resolved.coordinate.latitude, longitude: resolved.coordinate.longitude)
            let placeLocation = CLLocation(latitude: lat, longitude: lng)
            let miles = userLocation.distance(from: placeLocation) / 1609.34
            distanceText = miles < 0.1 ? "< 0.1 mi" : String(format: "%.1f mi", miles)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); dismiss() }) {
                // chevron.left matches the survey and native back buttons.
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.onSurface)
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Spacer()
            Text("bilu")
                .font(AppTheme.title)
                .italic()
                .foregroundStyle(AppTheme.sage)
            Spacer()
            Button(action: tapWantToGo) {
                topBarIcon(wantToGoSaved ? AppTheme.Icon.wantToGoFilled : AppTheme.Icon.wantToGo,
                           tint: wantToGoSaved ? AppTheme.sage : AppTheme.onSurface)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(wantToGoSaved ? "Remove from Want to Go" : "Add to Want to Go")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func topBarIcon(_ name: String, tint: Color = AppTheme.onSurface) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }

    // MARK: - Photo data

    private var allPhotos: [String] {
        var base: [String] = []
        if let img = rec.image { base = [img] }
        else if let photos = rec.photos, !photos.isEmpty { base = photos }
        return base + galleryPhotos
    }

    private var communityPhotos: [String] {
        let all = allPhotos
        guard all.count > 1 else { return [] }
        return Array(all.dropFirst())
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
                AppTheme.surface
            } else {
                TabView(selection: $currentPhoto) {
                    ForEach(Array(allPhotos.enumerated()), id: \.offset) { idx, url in
                        AsyncImage(url: URL(string: url)) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                AppTheme.surface
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
                    .padding(.bottom, 56)
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
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.surface)
                    .clipShape(Capsule())

                Text(rec.name)
                    .font(AppTheme.display)
                    .fontWeight(.bold)
                    .italic()
                    .foregroundStyle(AppTheme.onSurface)
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
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: -6)
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
                            .foregroundStyle(open ? AppTheme.openGreen : AppTheme.destructive)
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
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.terracotta)
                        Text(String(format: "%.1f", r))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(AppTheme.onSurface)
                        if let count = rec.reviewCount, count > 0 {
                            Text("·")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AppTheme.subtle)
                            Text(formatReviewCount(count))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            // Distance
            VStack(alignment: .trailing, spacing: 4) {
                Text("Distance")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.muted)
                Text(distanceText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.onSurface)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func formatReviewCount(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(n)"
    }

    // MARK: - CTA row

    private var ctaRow: some View {
        HStack(spacing: 12) {
            // "I've been here" pill button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let nowVisited = VisitedPlacesStore.toggle(rec.identityKey)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    ivenBeenHere = nowVisited
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

            // Bookmark circle — soft wind-up press + fill swap on commit.
            Button(action: tapBookmark) {
                ZStack {
                    Circle()
                        .fill(bookmarkSaved ? AppTheme.sageLt : AppTheme.neutralBg)
                        .frame(width: 52, height: 52)
                    Image(systemName: bookmarkSaved ? AppTheme.Icon.savedFilled : AppTheme.Icon.saved)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(bookmarkSaved ? AppTheme.sage : AppTheme.onSurface)
                        .scaleEffect(bookmarkPhase == .pressing ? 1.18 : 1.0)
                }
                .animation(AnimationProfile.selection.animation(reduceMotion: reduceMotion),
                           value: bookmarkSaved)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bookmarkSaved ? "Remove from Saved" : "Save")
        }
    }

    /// Bookmark toggle → persists into the Saved list. Tap → medium haptic + brief
    /// 1.18× wind-up scale, then commit. The store owns the save/unsave haptic and is
    /// the source of truth; `bookmarkSaved` mirrors it for the fill swap.
    /// reduceMotion skips the wind-up.
    private func tapBookmark() {
        Haptics.medium()
        if reduceMotion {
            store.toggle(rec, list: .saved, tags: tags)
            refreshSavedState()
            return
        }
        withAnimation(AnimationProfile.selection.animation(reduceMotion: false)) {
            bookmarkPhase = .pressing
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            store.toggle(rec, list: .saved, tags: tags)
            withAnimation(AnimationProfile.stepTransition.animation(reduceMotion: false)) {
                bookmarkPhase = .idle
                refreshSavedState()
            }
        }
    }

    /// Top-bar "Want to Go" toggle → persists into the Want-to-Go list.
    private func tapWantToGo() {
        Haptics.medium()
        store.toggle(rec, list: .wantToGo, tags: tags)
        withAnimation(AnimationProfile.selection.animation(reduceMotion: reduceMotion)) {
            refreshSavedState()
        }
    }

    /// A place lives in one list at a time, so saving to one list can clear the
    /// other — always re-read both from the store.
    private func refreshSavedState() {
        let list = store.listType(of: rec)
        bookmarkSaved = list == .saved
        wantToGoSaved = list == .wantToGo
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.rawValue) { tab in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .light))
                            .foregroundStyle(selectedTab == tab ? AppTheme.sage : AppTheme.subtle)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)

                        Text(tab.label)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.6)
                            .textCase(.uppercase)
                            .foregroundStyle(selectedTab == tab ? AppTheme.sage : AppTheme.subtle)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)

                        // Active underline
                        Rectangle()
                            .fill(selectedTab == tab ? AppTheme.sage : Color.clear)
                            .frame(height: 3)
                            .clipShape(Capsule())
                            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: selectedTab)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Tab content (swipeable)

    private var tabContent: some View {
        Group {
            switch selectedTab {
            case .overview:  overviewTab
            case .media:     mediaTab
            case .insights:  insightsTab
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
            if !galleryPhotos.isEmpty {
                photoRowSection
            } else if rec.placeId != nil {
                loadPhotosCard
            }
            if !tikTokVideos.isEmpty {
                tikTokThumbnailsSection
            } else {
                loadTikToksCard
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
            Text("\u{201C}\(rec.explanation)\u{201D}")
                .font(AppTheme.body)
                .italic()
                .foregroundStyle(AppTheme.onSurface)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Circle().fill(AppTheme.terracotta).frame(width: 7, height: 7)
                Text("AI VIBE CHECK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(vibeCheckVisible ? 1 : 0)
        .scaleEffect(vibeCheckVisible ? 1.0 : 0.97, anchor: .top)
        .animation(reduceMotion ? .linear(duration: 0)
                                : .spring(response: 0.55, dampingFraction: 0.85),
                   value: vibeCheckVisible)
        .task(id: rec.id) {
            vibeCheckVisible = false
            if reduceMotion {
                vibeCheckVisible = true
                return
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            vibeCheckVisible = true
            Haptics.light()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            UIPasteboard.general.string = rec.explanation
            Haptics.success()
        }
    }

    // MARK: - Photo row (Google Maps)

    private var photoRowSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Photos")
                    .font(AppTheme.headline)
                    .foregroundStyle(AppTheme.onSurface)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingAllPhotos = true
                } label: {
                    Text("View All")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.sage)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(galleryPhotos.prefix(5).enumerated()), id: \.offset) { _, url in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showingAllPhotos = true
                        } label: {
                            AsyncImage(url: URL(string: url)) { phase in
                                if let img = phase.image {
                                    img.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    AppTheme.surface
                                }
                            }
                            .frame(width: 140, height: 140)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var loadPhotosCard: some View {
        Button {
            Haptics.light()
            Task { await loadGalleryPhotosIfNeeded() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isFetchingAllPhotos ? "photo.on.rectangle.angled" : "photo.stack")
                    .font(.system(size: 18, weight: .medium))
                Text(isFetchingAllPhotos ? "Loading more photos…" : "Load more photos")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if !isFetchingAllPhotos {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .foregroundStyle(AppTheme.sage)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(AppTheme.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isFetchingAllPhotos || didRequestGalleryPhotos)
        .accessibilityLabel("Load more restaurant photos")
    }

    // MARK: - Community Moments

    private var tikTokThumbnailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TikToks")
                    .font(AppTheme.headline)
                    .foregroundStyle(AppTheme.onSurface)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        selectedTab = .media
                    }
                } label: {
                    Text("View All")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.sage)
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(tikTokVideos.enumerated()), id: \.offset) { idx, video in
                        tikTokThumb(video: video, index: idx)
                    }
                }
            }
        }
    }

    private var loadTikToksCard: some View {
        Button {
            Haptics.light()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                selectedTab = .media
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 18, weight: .medium))
                Text("See TikTok clips")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AppTheme.sage)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .background(AppTheme.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Load TikTok clips")
    }

    private func tikTokThumb(video: TikTokVideo, index: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            presentVideoFeed(at: index)
        } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AppTheme.surface
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
        .buttonStyle(.plain)
    }

    // MARK: - Pro Tips

    private var proTipsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(AppTheme.terracotta)
                Text("Pro Tips")
                    .font(AppTheme.headline)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Visit")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
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
                    .foregroundStyle(open ? AppTheme.openGreen : AppTheme.destructive)
            }
            Label(rec.parkingDisplayText, systemImage: "parkingsign.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.muted)
                .accessibilityLabel("Parking: \(rec.parkingDisplayText)")
            if let phone = rec.phone {
                Button(action: { dialPhone(phone) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "phone.fill").font(.system(size: 13))
                        Text(phone).font(.system(size: 14))
                    }
                    .foregroundStyle(AppTheme.muted)
                }
                .buttonStyle(.plain)
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
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
            }
        }
    }

    // MARK: - ══ INSIGHTS TAB ══

    /// Non-empty captions from the videos already loaded for the Media tab —
    /// real TikTok user text, not a fabricated summary.
    private var tikTokCaptionHighlights: [TikTokVideo] {
        tikTokVideos.filter { !$0.desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var insightsTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isFetchingTikTok && tikTokVideos.isEmpty {
                stubCard(icon: "sparkles", message: "Reading the TikTok\nbuzz…")
            } else if tikTokVideos.isEmpty {
                stubCard(
                    icon: "sparkles",
                    message: didRequestTikTok
                        ? "Not enough TikTok mentions\nyet to summarize"
                        : "Open the Media tab to\nload TikTok insights"
                )
            } else {
                HStack(spacing: 10) {
                    insightStat(icon: "video.fill", value: formatCount(tikTokVideos.count), label: "Clips")
                    insightStat(icon: "eye.fill", value: formatCount(tikTokVideos.reduce(0) { $0 + $1.viewCount }), label: "Views")
                    insightStat(icon: "heart.fill", value: formatCount(tikTokVideos.reduce(0) { $0 + $1.diggCount }), label: "Likes")
                }

                if !tikTokCaptionHighlights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("WHAT PEOPLE ARE SAYING")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1.0)
                            .foregroundStyle(AppTheme.muted)

                        ForEach(tikTokCaptionHighlights.prefix(5)) { video in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(video.desc)
                                    .font(AppTheme.body)
                                    .foregroundStyle(AppTheme.onSurface)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("— @\(video.author.name)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(AppTheme.subtle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(AppTheme.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
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

    private func insightStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.terracotta)
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(AppTheme.onSurface)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
    }

    // MARK: - ══ MEDIA TAB ══

    private var mediaTab: some View {
        VStack(alignment: .leading, spacing: 28) {
            if tikTokVideos.isEmpty {
                stubCard(
                    icon: "video.slash",
                    message: isFetchingTikTok
                        ? "Loading TikTok clips…"
                        : "No TikTok clips found yet"
                )
            } else {
                // Featured hero video
                featuredVideoCard(tikTokVideos[0], index: 0)

                // Other Posts list
                if tikTokVideos.count > 1 {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Text("More Clips")
                                .font(AppTheme.headline)
                                .foregroundStyle(AppTheme.onSurface)
                            Text("TikTok")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.sage)
                                .clipShape(Capsule())
                        }

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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            presentVideoFeed(at: index)
        } label: {
            ZStack(alignment: .bottom) {
                // Thumbnail — fixed frame, fills and clips to card bounds
                AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                    if let img = phase.image {
                        img.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        AppTheme.surface
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

                // VIDEOS badge — top leading
                VStack {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("VIDEOS")
                                .font(.system(size: 10, weight: .bold))
                                .tracking(1.0)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppTheme.sage)
                        .clipShape(Capsule())
                        .padding(16)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)

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
                                Circle().fill(AppTheme.surface)
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
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
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

    private func presentVideoFeed(at index: Int) {
        guard !tikTokVideos.isEmpty, index >= 0, index < tikTokVideos.count else { return }
        let vm = prewarmedFeedViewModel ?? VideoFeedViewModel(videos: tikTokVideos, startIndex: index)
        vm.setStartIndex(index)
        prewarmedFeedViewModel = vm
        feedViewModel = vm
    }

    // Other Posts row card
    private func otherPostRow(_ video: TikTokVideo, playerIndex: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            presentVideoFeed(at: playerIndex)
        } label: {
            HStack(spacing: 14) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: video.thumbnailUrl)) { phase in
                        if let img = phase.image {
                            img.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            AppTheme.surface
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
                            .foregroundStyle(AppTheme.muted)
                        Text(rec.address.map { shortAddress($0) } ?? rec.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.surface)
                    .clipShape(Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(AppTheme.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 6)
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
        VStack(alignment: .leading, spacing: 14) {
            if let reviews = rec.reviews, !reviews.isEmpty {
                ForEach(Array(reviews.enumerated()), id: \.offset) { _, review in
                    reviewCard(review)
                }
            } else {
                VStack(spacing: 14) {
                    stubCard(icon: "quote.bubble", message: "Read the latest guest reviews in Maps")
                    if let url = URL(string: rec.mapsUrl) {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open in Maps", systemImage: "map")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(AppTheme.sage)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewCard(_ review: PlaceReview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(review.authorName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.onSurface)
                Spacer()
                if let time = review.relativeTime {
                    Text(time)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.subtle)
                }
            }
            if let rating = review.rating {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { i in
                        Image(systemName: Double(i) < rating ? "star.fill" : "star")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.terracotta)
                    }
                }
            }
            Text(review.text)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(AppTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: AppTheme.shadowColor, radius: 10, x: 0, y: 4)
    }

    private func stubCard(icon: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.sageMd)
            Text(message)
                .font(AppTheme.body)
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
        Haptics.light()
        showMapsChoice = true
    }

    private func loadGalleryPhotosIfNeeded() async {
        guard let placeId = rec.placeId,
              galleryPhotos.isEmpty,
              !isFetchingAllPhotos,
              !didRequestGalleryPhotos else { return }
        didRequestGalleryPhotos = true
        isFetchingAllPhotos = true
        galleryPhotos = await GeminiService.fetchGalleryPhotos(placeId: placeId)
        isFetchingAllPhotos = false
    }

    private func loadTikToksIfNeeded() async {
        guard tikTokVideos.isEmpty, !isFetchingTikTok, !didRequestTikTok else { return }
        didRequestTikTok = true
        isFetchingTikTok = true
        let fetched = await fetchTikToks()
        tikTokVideos = fetched
        isFetchingTikTok = false
        if !fetched.isEmpty {
            prewarmedFeedViewModel = VideoFeedViewModel(videos: fetched, startIndex: 0)
        }
    }
}

// MARK: - All Photos View

struct AllPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    let heroPhoto: String?
    let galleryPhotos: [String]
    let name: String
    @GestureState private var dragOffset: CGFloat = 0

    private var allPhotos: [String] {
        var result: [String] = []
        if let hero = heroPhoto { result.append(hero) }
        result.append(contentsOf: galleryPhotos)
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)],
                    spacing: 3
                ) {
                    ForEach(Array(allPhotos.enumerated()), id: \.offset) { _, url in
                        AsyncImage(url: URL(string: url)) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                AppTheme.surface
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()
                    }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.onSurface)
                }
            }
        }
        .offset(y: max(0, dragOffset))
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if value.translation.height > 0 { state = value.translation.height }
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    }
                }
        )
    }
}
