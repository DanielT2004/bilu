//
//  RestaurantDetailView.swift
//  bilu
//

import SwiftUI

// MARK: - Detail color tokens (mirrors HomeView's BiluColors)
private let dGreen  = Color(hex: "3d5a2e")
private let dCream  = Color(hex: "f0ede6")
private let dDark   = Color(hex: "1e2d14")
private let dMuted  = Color(hex: "7a8a6a")
private let dBorder = Color(hex: "3d5a2e").opacity(0.1)
private let dSurface = Color(hex: "f5f3ee")
private let dCard   = Color.white.opacity(0.85)

// MARK: - Rounded-top-corners shape

private struct TopRoundedShape: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath)
    }
}

// MARK: - Tab enum

private enum DetailTab: String, CaseIterable {
    case overview = "Overview"
    case insights = "Insights"
    case media    = "Media"
    case reviews  = "Reviews"
}

// MARK: - RestaurantDetailView

struct RestaurantDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let rec: Recommendation

    @State private var currentPhotoIndex = 0
    @State private var selectedTab: DetailTab = .overview
    @State private var imageErrors: Set<Int> = []

    private let fallbackImage = "https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80"

    private var photos: [String] {
        if let p = rec.photos, !p.isEmpty { return p }
        if let img = rec.image { return [img] }
        return [fallbackImage]
    }

    var body: some View {
        ZStack(alignment: .top) {
            dCream.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroGallery
                    infoSummary
                    actionRow
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    tabBar
                    tabContent
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 60)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .onAppear {
            #if DEBUG
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("[DetailView] OPENED \"\(rec.name)\"")
            print("  photos   : \(rec.photos?.count ?? 0) | image=\(rec.image?.prefix(60) ?? "nil")")
            print("  rating   : \(rec.rating.map(String.init) ?? "nil")")
            print("  reviews  : \(rec.reviews?.count ?? 0)")
            print("  address  : \(rec.address ?? "nil")")
            print("  phone    : \(rec.phone ?? "nil")")
            print("  website  : \(rec.website ?? "nil")")
            print("  isOpen   : \(rec.isOpen.map(String.init) ?? "nil")")
            print("  tips     : \(rec.tips?.count ?? 0) → \(rec.tips?.joined(separator: " | ").prefix(100) ?? "none")")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            #endif
        }
    }

    // MARK: - Hero Gallery

    private var heroGallery: some View {
        ZStack(alignment: .top) {
            TabView(selection: $currentPhotoIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                    AsyncImage(url: URL(string: imageErrors.contains(i) ? fallbackImage : url)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            Color.gray.opacity(0.2)
                                .task { imageErrors.insert(i) }
                        default:
                            Color.gray.opacity(0.15)
                                .overlay(ProgressView().tint(.white))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 300)

            // Top controls
            HStack {
                Button(action: { dismiss() }) {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "chevron.down")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
                Spacer()
                Button(action: shareRestaurant) {
                    Circle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 56)

            // Photo count pill
            if photos.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 5) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 11))
                            Text("\(currentPhotoIndex + 1) / \(photos.count)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.35))
                        .clipShape(Capsule())
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                    }
                }
                .frame(height: 300)
            }
        }
        .frame(height: 300)
    }

    // MARK: - Info Summary

    private var infoSummary: some View {
        VStack(spacing: 0) {
            VStack(alignment: .center, spacing: 6) {
                Text(rec.name)
                    .font(.custom("Georgia", size: 26))
                    .fontWeight(.black)
                    .italic()
                    .foregroundStyle(dGreen)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)
                    .padding(.horizontal, 24)

                if let address = rec.address {
                    Text(address)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(dMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                HStack(spacing: 0) {
                    statPill(title: "Status") {
                        AnyView(Group {
                            if let isOpen = rec.isOpen {
                                Text(isOpen ? "Open now" : "Closed")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(isOpen ? dGreen : Color.red.opacity(0.8))
                            } else {
                                Text("—").font(.system(size: 14, weight: .bold)).foregroundStyle(dMuted)
                            }
                        })
                    }

                    Divider().frame(height: 32)

                    statPill(title: "Rating") {
                        AnyView(Group {
                            if let rating = rec.rating {
                                HStack(spacing: 3) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(hex: "9f402d"))
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(dDark)
                                }
                            } else {
                                Text("—").font(.system(size: 14, weight: .bold)).foregroundStyle(dMuted)
                            }
                        })
                    }

                    Divider().frame(height: 32)

                    statPill(title: "Reviews") {
                        AnyView(Group {
                            if let count = rec.reviewCount {
                                Text(formatCount(count))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(dDark)
                            } else {
                                Text("—").font(.system(size: 14, weight: .bold)).foregroundStyle(dMuted)
                            }
                        })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .background(dCream)
            .clipShape(TopRoundedShape(radius: 28))
            .padding(.top, -28)
        }
    }

    private func statPill(title: String, @ViewBuilder value: () -> AnyView) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(dMuted)
            value()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: openMapsDirections) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text("I've been here")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(dGreen)
                .clipShape(Capsule())
                .shadow(color: dGreen.opacity(0.35), radius: 8, y: 3)
            }
            .buttonStyle(.plain)

            Button(action: { }) {
                Image(systemName: "bookmark")
                    .font(.system(size: 18))
                    .foregroundStyle(dDark)
                    .frame(width: 50, height: 50)
                    .background(dSurface)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(dBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }) {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(selectedTab == tab ? dGreen : dMuted)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                        Rectangle()
                            .fill(selectedTab == tab ? dGreen : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(dCream)
        .overlay(Rectangle().fill(dBorder).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview: overviewTab
        case .insights: insightsTab
        case .media:    mediaTab
        case .reviews:  reviewsTab
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        VStack(spacing: 16) {
            detailCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("About this place")
                        .font(.custom("Georgia", size: 18))
                        .italic()
                        .foregroundStyle(dGreen)
                    Text(rec.explanation)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(dMuted)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let tips = rec.tips, !tips.isEmpty {
                detailCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(dGreen)
                            Text("Tips & Tricks")
                                .font(.custom("Georgia", size: 18))
                                .italic()
                                .foregroundStyle(dGreen)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(tips.prefix(3).enumerated()), id: \.offset) { i, tip in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: tipIcon(index: i))
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color(hex: "9f402d"))
                                        .frame(width: 20)
                                        .padding(.top, 1)
                                    Text(tip)
                                        .font(.system(size: 13, weight: .light))
                                        .foregroundStyle(dMuted)
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                quickActionButton(icon: "location.fill", label: "Directions", action: openMapsDirections)
                if rec.website != nil {
                    quickActionButton(icon: "globe", label: "Website", action: openWebsite)
                }
                if rec.phone != nil {
                    quickActionButton(icon: "phone.fill", label: "Call", action: callRestaurant)
                }
            }

            if let address = rec.address {
                detailCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Location")
                            .font(.custom("Georgia", size: 18))
                            .italic()
                            .foregroundStyle(dGreen)
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(dGreen)
                                .padding(.top, 1)
                            Text(address)
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(dMuted)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(action: openMapsDirections) {
                            Text("Open in Maps")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(dGreen)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(dGreen.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Insights Tab

    private var insightsTab: some View {
        VStack(spacing: 16) {
            detailCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                            .font(.system(size: 15))
                            .foregroundStyle(dGreen)
                        Text("The Bilu Take")
                            .font(.custom("Georgia", size: 18))
                            .italic()
                            .foregroundStyle(dGreen)
                    }
                    Text("\"\(rec.explanation)\"")
                        .font(.system(size: 14, weight: .light))
                        .italic()
                        .foregroundStyle(dMuted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if rec.rating != nil || rec.reviewCount != nil {
                detailCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Quick Stats")
                            .font(.custom("Georgia", size: 18))
                            .italic()
                            .foregroundStyle(dGreen)
                        VStack(spacing: 10) {
                            if let rating = rec.rating {
                                statRow(label: "Google Rating", value: String(format: "%.1f / 5.0 ★", rating))
                            }
                            if let count = rec.reviewCount {
                                statRow(label: "Total Reviews", value: "\(formatCount(count)) reviews")
                            }
                            if let isOpen = rec.isOpen {
                                statRow(label: "Right Now", value: isOpen ? "Open" : "Closed")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Media Tab

    private var mediaTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Photos")
                .font(.custom("Georgia", size: 22))
                .italic()
                .foregroundStyle(dGreen)

            if photos.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                            AsyncImage(url: URL(string: imageErrors.contains(i) ? fallbackImage : url)) { phase in
                                switch phase {
                                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                                default: Color.gray.opacity(0.15)
                                }
                            }
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .onTapGesture { currentPhotoIndex = i }
                        }
                    }
                }

                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                        AsyncImage(url: URL(string: imageErrors.contains(i) ? fallbackImage : url)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                            default: Color.gray.opacity(0.15)
                            }
                        }
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                AsyncImage(url: URL(string: photos.first ?? fallbackImage)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                    default: Color.gray.opacity(0.15)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    // MARK: - Reviews Tab

    private var reviewsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Guest Reflections")
                    .font(.custom("Georgia", size: 22))
                    .italic()
                    .foregroundStyle(dGreen)
                Spacer()
                if let count = rec.reviewCount {
                    Text("\(formatCount(count)) total")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(dMuted)
                }
            }

            if let reviews = rec.reviews, !reviews.isEmpty {
                ForEach(Array(reviews.enumerated()), id: \.offset) { _, review in
                    reviewCard(review: review)
                }
            } else {
                detailCard {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 28))
                            .foregroundStyle(dMuted.opacity(0.4))
                        Text("No reviews loaded yet")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(dMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    // MARK: - Reusable subviews

    @ViewBuilder
    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(dBorder, lineWidth: 1))
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(dGreen)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(dDark)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(dCard)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(dBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(dMuted)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dDark)
        }
        .padding(.vertical, 4)
    }

    private func reviewCard(review: PlaceReview) -> some View {
        detailCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Circle()
                        .fill(dGreen.opacity(0.12))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Text(initials(for: review.authorName))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(dGreen)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(review.authorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(dDark)
                        Text(review.relativeTimeDescription)
                            .font(.system(size: 10, weight: .light))
                            .foregroundStyle(dMuted)
                    }
                    Spacer()
                    HStack(spacing: 1) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= review.rating ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundStyle(Color(hex: "9f402d"))
                        }
                    }
                }
                if !review.text.isEmpty {
                    Text("\"\(review.text)\"")
                        .font(.system(size: 13, weight: .light))
                        .italic()
                        .foregroundStyle(dMuted)
                        .lineSpacing(4)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Helpers

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? (parts.last?.prefix(1) ?? "") : ""
        return "\(first)\(last)".uppercased()
    }

    private func tipIcon(index: Int) -> String {
        let icons = ["clock.fill", "fork.knife", "star.fill"]
        return icons[min(index, icons.count - 1)]
    }

    private func formatCount(_ count: Int) -> String {
        count >= 1000 ? "\(count / 1000).\((count % 1000) / 100)k" : "\(count)"
    }

    private func openMapsDirections() {
        guard let url = URL(string: rec.mapsUrl) else { return }
        openURL(url)
    }

    private func openWebsite() {
        guard let site = rec.website, let url = URL(string: site) else { return }
        openURL(url)
    }

    private func callRestaurant() {
        guard let phone = rec.phone else { return }
        let cleaned = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard let url = URL(string: "tel://\(cleaned)") else { return }
        openURL(url)
    }

    private func shareRestaurant() {
        guard let url = URL(string: rec.mapsUrl) else { return }
        let av = UIActivityViewController(activityItems: [rec.name, url], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}
