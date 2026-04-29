//
//  HomeView.swift
//  bilu
//

import SwiftUI
import CoreLocation

// MARK: - Convenience alias
private let C = AppTheme.self

// MARK: - Scale press button style
private struct ScalePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - HomeView

struct HomeView: View {
    let selectedTab: Tab
    let onSelectTab: (Tab) -> Void
    @StateObject private var viewModel = HomeViewModel()
    @FocusState private var locationFieldFocused: Bool
    @State private var selectedRestaurant: Recommendation? = nil
    @State private var stepForward = true
    @State private var mapIsExpanded = false
    @State private var expandedCategoryKey: String? = nil
    @State private var subOptionRevealTrigger: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            if let idx = viewModel.progressStepIndex {
                progressBar(index: idx)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        stepContent
                            .id(viewModel.step)
                            .transition(.asymmetric(
                                insertion: .move(edge: stepForward ? .trailing : .leading).combined(with: .opacity),
                                removal:   .move(edge: stepForward ? .leading  : .trailing).combined(with: .opacity)
                            ))
                    }
                    .padding(.bottom, viewModel.step == .occasion ? 20 : 100)
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(mapIsExpanded)
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: viewModel.step)
                .onChange(of: viewModel.step) { newStep in
                    proxy.scrollTo("top", anchor: .top)
                    expandedCategoryKey = nil
                    if newStep == .reveal {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            }

            if viewModel.step == .occasion {
                TabBarView(selectedTab: selectedTab, onSelect: onSelectTab)
            }
        }
        .background(C.surface)
        .sheet(item: $selectedRestaurant) { rec in
            RestaurantDetailView(rec: rec) {
                    await viewModel.fetchTikTokVideos(for: rec)
                }
        }
    }

    // MARK: - Step router

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .occasion:       occasionStep
        case .keyQuestion:    keyQuestionStep
        case .drinksSubFlow:  drinksSubFlowStep
        case .foodFeeling:    foodFeelingStep
        case .location:       fineTuneStep
        case .loading:        loadingStep
        case .reveal:         revealStep
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if viewModel.step == .occasion {
                iconButton(systemName: "person", tint: C.onSurface) { }
            } else {
                iconButton(systemName: "chevron.left", tint: C.onSurface) { UIImpactFeedbackGenerator(style: .light).impactOccurred(); stepForward = false; viewModel.goBack() }
            }
            Spacer()
            Text("bilu")
                .font(.custom("Georgia", size: 22))
                .foregroundColor(C.sage)
            Spacer()
            if viewModel.step == .occasion {
                iconButton(systemName: "bell", tint: C.onSurface) { }
            } else {
                iconButton(systemName: "xmark", tint: C.muted) { UIImpactFeedbackGenerator(style: .light).impactOccurred(); viewModel.reset() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 0)
    }

    private func iconButton(systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(C.white)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(tint)
                )
                .shadow(color: Color.black.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress bar

    private func progressBar(index: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        i < index  ? C.sage :
                        i == index ? C.sage.opacity(0.45) :
                                     C.sage.opacity(0.1)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: index)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    // MARK: - ══════════ OCCASION STEP ══════════

    private var occasionStep: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Eat / Drinks & more tab switcher
            eatDrinksTabSwitcher
                .padding(.horizontal, 20)
                .padding(.top, 14)

            HomeMapWidget(
                locationLabel: viewModel.mapLocationLabel,
                isExpanded: $mapIsExpanded,
                onRadiusChanged: { miles, coord in
                    viewModel.selection.radiusMiles = miles
                    viewModel.selection.latitude = coord.latitude
                    viewModel.selection.longitude = coord.longitude
                    viewModel.selection.useRadiusSearch = true
                },
                onLocationResolved: { label in
                    viewModel.detectedLocation = label
                    viewModel.selection.location = label
                },
                onRadiusModeChanged: { isRadiusMode in
                    viewModel.selection.useRadiusSearch = isRadiusMode
                    if !isRadiusMode {
                        viewModel.selection.latitude = nil
                        viewModel.selection.longitude = nil
                    }
                }
            )
            .padding(.top, 10)

            if viewModel.serviceCategory == "eat" {
                eatOccasionContent
            } else {
                drinksOccasionContent
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.35)) { mapIsExpanded = false }
        }
    }

    // MARK: - Eat / Drinks tab switcher

    private var eatDrinksTabSwitcher: some View {
        ZStack {
            Capsule().fill(C.neutralBg)
            HStack(spacing: 0) {
                tabSegment("Eat",           isActive: viewModel.serviceCategory == "eat")    { viewModel.serviceCategory = "eat" }
                tabSegment("Drinks & more", isActive: viewModel.serviceCategory == "drinks") { viewModel.serviceCategory = "drinks" }
            }
            .clipShape(Capsule())
        }
        .frame(height: 44)
    }

    private func tabSegment(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { action() }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? .white : C.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isActive ? C.sage : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Eat occasion content

    private var eatOccasionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("How much ").foregroundColor(C.onSurface) + Text("time").foregroundColor(C.sage))
                    .font(.system(size: 34, weight: .black))
                Text("do you have?")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(C.onSurface)
            }
            .tracking(-0.5)
            .padding(.horizontal, 20)
            .padding(.top, 18)

            VStack(spacing: 12) {
                timeCard(occasion: "Casual",   icon: "bolt.fill",   label: "Grab & Go!",     sub: "Quick fuel for a busy day",        badge: "30M • FAST",      accentColor: C.sage)
                timeCard(occasion: "Sit Down", icon: "fork.knife",  label: "Sit Down Vibes", sub: "Unwind with a proper meal",        badge: "1-2HR • RELAXED", accentColor: C.terracotta)
                timeCard(occasion: "No Rush",  icon: "clock",       label: "No Rush",        sub: "Make a night of it",               badge: "2HR+ • SLOW",     accentColor: C.openGreen)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            HStack(spacing: 10) {
                occasionChip(occasion: "Brunch",     icon: "sun.and.horizon.fill", label: "Brunch",     isDark: false)
                occasionChip(occasion: "Late Night", icon: "moon.stars.fill",      label: "Late Night", isDark: true)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            trendingNowSection
        }
    }

    // MARK: - Drinks occasion content

    private var drinksOccasionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                (Text("What are ").foregroundColor(C.onSurface) + Text("you").foregroundColor(C.sage))
                    .font(.system(size: 34, weight: .black))
                Text("after?")
                    .font(.system(size: 34, weight: .black))
                    .foregroundColor(C.onSurface)
            }
            .tracking(-0.5)
            .padding(.horizontal, 20)
            .padding(.top, 18)

            VStack(spacing: 12) {
                timeCard(occasion: "Cafe",    icon: "cup.and.saucer.fill", label: "Cafe Vibes",   sub: "Coffee, study, and good energy", badge: "ANYTIME",  accentColor: C.sage)
                timeCard(occasion: "Bakery",  icon: "leaf.fill",            label: "Fresh Baked",  sub: "Pastries, bread, and morning joy", badge: "MORNING",  accentColor: C.terracotta)
                timeCard(occasion: "Dessert", icon: "birthday.cake.fill",   label: "Sweet Tooth",  sub: "Ice cream, cake, dessert bars",   badge: "SWEET",    accentColor: C.sage)
                timeCard(occasion: "Drinks",  icon: "wineglass.fill",       label: "Drinks Out",   sub: "Bars, cocktails, and good vibes",  badge: "EVENING",  accentColor: C.terracotta)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Occasion card helpers

    private func timeCard(occasion: String, icon: String, label: String, sub: String, badge: String, accentColor: Color) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            stepForward = true
            viewModel.handleOccasion(occasion)
        } label: {
            HStack(spacing: 0) {
                // Flush full-height left border bar
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 9)

                // Content area
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(badge)
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.2)
                            .foregroundColor(accentColor)
                        Text(label)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundColor(C.onSurface)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(sub)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(C.muted)
                            .lineLimit(1)
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 18)

                    Spacer()

                    // Ghost icon — decorative background element
                    Image(systemName: icon)
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(Color.black.opacity(0.07))
                        .padding(.trailing, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 106)
            .background(C.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 14, x: 0, y: 5)
        }
        .buttonStyle(ScalePress())
    }

    private func occasionChip(occasion: String, icon: String, label: String, isDark: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            stepForward = true
            viewModel.handleOccasion(occasion)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isDark ? .white : C.terracotta)
                    .frame(width: 32, height: 32)
                    .background(isDark ? Color.white.opacity(0.12) : C.terracotta.opacity(0.10))
                    .clipShape(Circle())
                Text(label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(isDark ? .white : C.onSurface)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isDark ? C.darkSurface : C.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(isDark ? 0.2 : 0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(ScalePress())
    }

    // MARK: - Trending Now section

    private var trendingNowSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                (Text("Trending ").foregroundColor(C.onSurface) + Text("Now").foregroundColor(C.sage))
                    .font(.system(size: 26, weight: .black))
                    .tracking(-0.5)
                Spacer()
                Button(action: {}) {
                    Text("View all")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(C.sage)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    trendingCard(name: "The Rusty Grill", category: "Aged Steaks & Malbec", trayColor: C.traySlate,  badge: "NEW ENTRY")
                    trendingCard(name: "Neon Noodle",     category: "Bangkok Heat & Bass",   trayColor: C.trayAmber, badge: "TOP RATED")
                    trendingCard(name: "Lasa",            category: "Filipino Fine Dining",  trayColor: C.trayMoss)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func trendingCard(name: String, category: String, trayColor: Color, badge: String? = nil) -> some View {
        ZStack(alignment: .bottom) {
            // Photo background (tray color as placeholder)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(trayColor)
                .overlay(
                    Image(systemName: "fork.knife")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(C.subtle.opacity(0.5))
                )

            // Gradient scrim
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Bottom metadata
            VStack(alignment: .leading, spacing: 2) {
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.8)
                        .foregroundColor(C.mintBadgeText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(C.mintBadge)
                        .clipShape(Capsule())
                }
                Text(name)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(category)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .frame(width: 200, height: 260)
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 6)
    }

    // MARK: - ══════════ KEY QUESTION STEP ══════════

    private var keyQuestionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kq = viewModel.keyQuestion {
                Text(kq.columnLabel)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundColor(C.muted)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                Text(kq.question)
                    .font(.custom("Georgia", size: 30))
                    .foregroundColor(C.onSurface)
                    .lineSpacing(2)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                VStack(spacing: 9) {
                    ForEach(kq.options, id: \.key) { opt in
                        let isSelected = viewModel.selection.keyQuestionAnswer == opt.key
                        keyChoiceCard(opt: opt, isSelected: isSelected)

                        if isSelected {
                            switch opt.subPicker {
                            case .none: EmptyView()
                            case .timeWindows(let options):
                                timeWindowPicker(options: options)
                            case .date:
                                datePicker
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)

                if viewModel.canContinueFromKeyQuestion {
                    continueButton { stepForward = true; viewModel.continueFromKeyQuestion() }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                }

                Spacer(minLength: 40)
            }
        }
    }

    private func keyChoiceCard(opt: KeyQuestionOption, isSelected: Bool) -> some View {
        Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); viewModel.selectKeyQuestionAnswer(opt.key) } label: {
             HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.15) : C.neutralBg)
                    .frame(width: 42, height: 42)
                    .overlay(Text(opt.icon).font(.system(size: 20)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(opt.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isSelected ? .white : C.onSurface)
                        if let badge = opt.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? C.sage : C.darkSage)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white : C.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Text(opt.desc)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : C.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(isSelected ? C.sage : C.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: isSelected ? C.sage.opacity(0.18) : Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func timeWindowPicker(options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What time works for you?")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(C.sage)
            VStack(spacing: 5) {
                ForEach(options, id: \.self) { t in
                    let isSel = viewModel.selection.keyQuestionTimeWindow == t
                    Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); viewModel.selectKeyQuestionTimeWindow(t) } label: {
                        Text(t)
                            .font(.system(size: 12))
                            .foregroundColor(isSel ? .white : C.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isSel ? C.sage : C.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .padding(.leading, 14)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which date are you thinking?")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(C.sage)
            DatePicker(
                "",
                selection: Binding(
                    get: {
                        if let v = viewModel.selection.keyQuestionDate,
                           let d = ISO8601DateFormatter().date(from: v + "T00:00:00Z") { return d }
                        return Date()
                    },
                    set: { newValue in
                        let df = DateFormatter()
                        df.calendar = Calendar(identifier: .gregorian)
                        df.locale = Locale(identifier: "en_US_POSIX")
                        df.timeZone = TimeZone(secondsFromGMT: 0)
                        df.dateFormat = "yyyy-MM-dd"
                        viewModel.selectKeyQuestionDate(df.string(from: newValue))
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .accentColor(C.sage)
        }
        .padding(12)
        .padding(.leading, 14)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - ══════════ FOOD FEELING STEP ══════════

    private var foodFeelingStep: some View {
        Group {
            if HomeViewModel.newTimeOccasions.contains(viewModel.selection.occasion)
               && viewModel.cuisineMode == .vibe {
                newFoodFeelingStep
            } else {
                legacyFoodFeelingStep
            }
        }
    }

    // MARK: - New food feeling step (time-based occasions)

    private var newFoodFeelingStep: some View {
        let isNoRush = viewModel.selection.occasion == "No Rush"
        return VStack(alignment: .leading, spacing: 0) {
            Text(breadcrumbLabel)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Text(isNoRush ? "What's the occasion?" : "What are you feeling?")
                .font(.custom("Georgia", size: 30))
                .foregroundColor(C.onSurface)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            if isNoRush {
                // No Rush: occasion sub-picker pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["🍽 Best food", "⚡ Date night", "🎉 Special occasion"], id: \.self) { opt in
                            noRushOccasionPill(opt)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 14)
            } else {
                // Vibe toggle pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.vibeOptions(for: viewModel.selection.occasion), id: \.self) { vibe in
                            vibePill(vibe)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 14)
            }

            // Food category list (expands to sub-options on tap)
            let categories = viewModel.foodCategoriesForOccasion
            let gridItems  = categories.filter { !$0.isFullWidth }
            let surprise   = categories.first(where: { $0.isFullWidth })

            VStack(spacing: 10) {
                ForEach(pairedRows(from: gridItems), id: \.id) { row in
                    rowOfCards(row)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .contentShape(Rectangle())
            .onTapGesture {
                guard expandedCategoryKey != nil else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    expandedCategoryKey = nil
                }
            }

            if let surprise = surprise {
                surpriseCard(surprise, dismissExpanded: expandedCategoryKey != nil)
                    .opacity(expandedCategoryKey != nil ? 0.18 : 1.0)
                    .scaleEffect(expandedCategoryKey != nil ? 0.96 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.72), value: expandedCategoryKey)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
            }

            // Continue + fine-tune buttons
            HStack(spacing: 10) {
                continueButton { stepForward = true; viewModel.continueFromFoodFeeling() }
                    .opacity(viewModel.canContinueFromFoodFeeling ? 1 : 0.4)
                    .disabled(!viewModel.canContinueFromFoodFeeling)

                if viewModel.fineTuneType != "none" {
                    Button { viewModel.openFineTune() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(C.onSurface)
                            .frame(width: 52, height: 52)
                            .background(C.neutralBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(ScalePress())
                    .disabled(!viewModel.canContinueFromFoodFeeling)
                    .opacity(viewModel.canContinueFromFoodFeeling ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            // Browse by cuisine link
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    viewModel.setCuisineMode(.country)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Browse by cuisine")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(C.sage)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(C.sage)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        // Catch any remaining taps on this step that weren't consumed by a
        // child button — covers empty padding areas, text labels, etc.
        .contentShape(Rectangle())
        .onTapGesture {
            guard expandedCategoryKey != nil else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                expandedCategoryKey = nil
            }
        }
    }

    private var breadcrumbLabel: String {
        switch viewModel.selection.occasion {
        case "Casual":     return "Casual · counter service"
        case "Sit Down":   return "Sit down · table service"
        case "No Rush":    return "No rush · making it a night"
        case "Brunch":     return "Brunch"
        case "Late Night": return "Late night eats"
        default:           return viewModel.selection.occasion
        }
    }

    private func vibePill(_ vibe: String) -> some View {
        let isSelected = viewModel.selectedVibe == vibe
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                viewModel.selectVibe(vibe)
            }
        } label: {
            Text(vibe)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : C.onSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? C.sage : C.white)
                .clipShape(Capsule())
                .shadow(color: isSelected ? C.sage.opacity(0.18) : Color.black.opacity(0.06), radius: isSelected ? 8 : 5, x: 0, y: 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func noRushOccasionPill(_ opt: String) -> some View {
        let isSelected = viewModel.selectedNoRushOccasion == opt
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                viewModel.selectNoRushOccasion(opt)
            }
        } label: {
            Text(opt)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .white : C.onSurface)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? C.sage : C.white)
                .clipShape(Capsule())
                .shadow(color: isSelected ? C.sage.opacity(0.18) : Color.black.opacity(0.06), radius: isSelected ? 8 : 5, x: 0, y: 2)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Food category card row helpers

    private struct CardRow: Identifiable {
        let id: String
        let left: FoodCategoryOption
        let right: FoodCategoryOption?
    }

    private func pairedRows(from items: [FoodCategoryOption]) -> [CardRow] {
        var rows: [CardRow] = []
        var i = 0
        while i < items.count {
            let left = items[i]
            let right = i + 1 < items.count ? items[i + 1] : nil
            rows.append(CardRow(id: left.key + (right?.key ?? ""), left: left, right: right))
            i += 2
        }
        return rows
    }

    @ViewBuilder
    private func rowOfCards(_ row: CardRow) -> some View {
        let leftExpanded  = expandedCategoryKey == row.left.key
        let rightExpanded = row.right.map { expandedCategoryKey == $0.key } ?? false

        if leftExpanded || rightExpanded {
            HStack(spacing: 10) {
                if leftExpanded {
                    foodCategoryCard(row.left)
                    if let right = row.right {
                        compactDimmedCard(right)
                    }
                } else if let right = row.right, rightExpanded {
                    compactDimmedCard(row.left)
                    foodCategoryCard(right)
                }
            }
        } else {
            HStack(spacing: 10) {
                foodCategoryCard(row.left)
                if let right = row.right {
                    foodCategoryCard(right)
                } else {
                    Spacer()
                }
            }
        }
    }

    private func compactDimmedCard(_ cat: FoodCategoryOption) -> some View {
        let isSelected = viewModel.selection.foodFeelings.contains(cat.key)
        // Tapping the compact sibling is a "dismiss" gesture, not an expand.
        // The user gets a clean grid on this first tap; they can then tap this
        // card again as a deliberate second choice.
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                expandedCategoryKey = nil
            }
        } label: {
            VStack(spacing: 4) {
                Text(cat.emoji)
                    .font(.system(size: 22))
                Text(cat.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? C.sage : C.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(C.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? C.sage : Color.clear, lineWidth: 2)
            )
            .opacity(0.35)
            .scaleEffect(0.92)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: expandedCategoryKey)
    }

    // MARK: - Expanded food category card

    private func foodCategoryCard(_ cat: FoodCategoryOption) -> some View {
        let isExpanded   = expandedCategoryKey == cat.key
        let isDimmed     = expandedCategoryKey != nil && !isExpanded
        let isSelected   = viewModel.selection.foodFeelings.contains(cat.key)
        let selectedSubs = viewModel.selection.selectedSubOptions[cat.key] ?? []

        // Badge label shown in collapsed card header when sub-options are picked
        let badgeLabel: String = {
            if selectedSubs.isEmpty { return "" }
            if selectedSubs.count == 1 { return selectedSubs[0] }
            return "\(selectedSubs.count) picked"
        }()

        return VStack(alignment: .leading, spacing: 0) {
            // Header — tappable to expand/collapse.
            // When this card is dimmed (another card is open), the first tap is
            // "dismiss the open dropdown" only — the user gets a clean neutral grid
            // and can then tap any card as a second deliberate tap.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    if isDimmed {
                        // First tap: just close the open dropdown, don't expand this card.
                        expandedCategoryKey = nil
                    } else if expandedCategoryKey == cat.key {
                        // Tapping the expanded card's header collapses + deselects
                        expandedCategoryKey = nil
                        viewModel.selectFoodFeeling(cat.key)  // toggles off (removes + clears subs)
                    } else {
                        expandedCategoryKey = cat.key
                        subOptionRevealTrigger += 1
                        if !viewModel.selection.foodFeelings.contains(cat.key) {
                            viewModel.selectFoodFeeling(cat.key)
                        }
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        Text(cat.emoji)
                            .font(.system(size: isExpanded ? 28 : 24))
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isExpanded)
                        Spacer()
                        // Chosen-sub badge: visible on collapsed selected cards
                        if !badgeLabel.isEmpty && !isExpanded {
                            Text(badgeLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(C.sage)
                                .clipShape(Capsule())
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, 8)

                    Text(cat.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isExpanded ? .white : C.onSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(cat.subtitle)
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(isExpanded ? .white.opacity(0.75) : C.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(14)
            }
            .buttonStyle(.plain)

            // Sub-options row — pops in when expanded
            if isExpanded && !cat.subOptions.isEmpty {
                subOptionsRow(cat: cat, trigger: subOptionRevealTrigger)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .background(isExpanded ? C.sage : C.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Red border on collapsed cards that have a selection
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    (isSelected && !isExpanded) ? C.sage : Color.clear,
                    lineWidth: 2
                )
        )
        .shadow(
            color: isExpanded ? C.sage.opacity(0.22) : (isSelected ? C.sage.opacity(0.12) : Color.black.opacity(0.06)),
            radius: 12, x: 0, y: 4
        )
        .scaleEffect(isDimmed ? 0.96 : (isExpanded ? 1.01 : 1.0))
        .opacity(isDimmed ? 0.18 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: isDimmed)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }

    @ViewBuilder
    private func subOptionsRow(cat: FoodCategoryOption, trigger: Int) -> some View {
        let selectedSubs = viewModel.selection.selectedSubOptions[cat.key] ?? []
        HStack(spacing: 0) {
            ForEach(Array(cat.subOptions.enumerated()), id: \.element.key) { index, sub in
                SubBubble(
                    sub: sub,
                    index: index,
                    trigger: trigger,
                    isSelected: selectedSubs.contains(sub.key),
                    onTap: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            viewModel.selectSubOption(sub.key, forCategory: cat.key)
                        }
                    }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func surpriseCard(_ cat: FoodCategoryOption, dismissExpanded: Bool = false) -> some View {
        let isSelected = viewModel.selection.foodFeelings.contains(cat.key)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if dismissExpanded {
                // While a dropdown is open this card acts as a dismiss target,
                // not as a selection — same two-tap contract as the dimmed cards.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                    expandedCategoryKey = nil
                }
            } else {
                viewModel.selectFoodFeeling(cat.key)
            }
        } label: {
            HStack(spacing: 12) {
                Text(cat.emoji)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : C.onSurface)
                    Text(cat.subtitle)
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(isSelected ? .white.opacity(0.75) : C.muted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(isSelected ? C.sage : C.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: isSelected ? C.sage.opacity(0.18) : Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
            .opacity(isSelected ? 1.0 : 0.78)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(ScalePress())
    }

    // MARK: - ══════════ DRINKS SUB-FLOW STEP ══════════

    private var drinksSubFlowStep: some View {
        let occasion = viewModel.selection.occasion
        let headline: String = {
            switch occasion {
            case "Cafe":    return "What brings you in?"
            case "Dessert": return "What are you after?"
            default:        return "What kind of spot?"
            }
        }()
        let options = viewModel.drinksSubFlowOptions

        return VStack(alignment: .leading, spacing: 0) {
            Text(occasion.lowercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Text(headline)
                .font(.custom("Georgia", size: 30))
                .foregroundColor(C.onSurface)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(options, id: \.title) { opt in
                    drinksSubCard(emoji: opt.emoji, title: opt.title, sub: opt.sub)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
    }

    private func drinksSubCard(emoji: String, title: String, sub: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            stepForward = true
            viewModel.selectDrinksSubType(title)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(emoji)
                    .font(.system(size: 28))
                    .padding(.bottom, 10)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(C.onSurface)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sub)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(C.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(C.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
        }
        .buttonStyle(ScalePress())
    }

    // MARK: - Legacy food feeling step (old occasions)

    private var legacyFoodFeelingStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(viewModel.selection.occasion)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundColor(C.muted)
                Spacer()
                cuisineModeToggle
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Text(viewModel.cuisineMode == .vibe
                 ? "How do you want\nthe food to feel?"
                 : "What cuisine\nare you craving?")
                .font(.custom("Georgia", size: 30))
                .foregroundColor(C.onSurface)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .animation(.none, value: viewModel.cuisineMode == .vibe)

            Text(viewModel.cuisineMode == .vibe
                 ? "Pick one or more — we'll find the cuisine"
                 : "Pick a country — we'll find the best local spot")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            if viewModel.cuisineMode == .vibe {
                VStack(spacing: 9) {
                    ForEach(viewModel.foodFeelingsForOccasion, id: \.key) { opt in
                        foodFeelingCard(opt: opt)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
            } else {
                VStack(spacing: 9) {
                    ForEach(HomeViewModel.countries, id: \.name) { entry in
                        countryCard(flag: entry.flag, name: entry.name)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
            }

            HStack(spacing: 10) {
                continueButton { stepForward = true; viewModel.continueFromFoodFeeling() }
                    .opacity(viewModel.canContinueFromFoodFeeling ? 1 : 0.4)
                    .disabled(!viewModel.canContinueFromFoodFeeling)

                if viewModel.fineTuneType != "none" {
                    Button { viewModel.openFineTune() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(C.onSurface)
                            .frame(width: 52, height: 52)
                            .background(C.neutralBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(ScalePress())
                    .disabled(!viewModel.canContinueFromFoodFeeling)
                    .opacity(viewModel.canContinueFromFoodFeeling ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    private var cuisineModeToggle: some View {
        ZStack {
            Capsule().fill(C.neutralBg)
            HStack(spacing: 0) {
                toggleSegment("Vibe", isActive: viewModel.cuisineMode == .vibe) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { viewModel.setCuisineMode(.vibe) }
                }
                toggleSegment("Country", isActive: viewModel.cuisineMode == .country) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { viewModel.setCuisineMode(.country) }
                }
            }
            .clipShape(Capsule())
        }
    }

    private func toggleSegment(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .white : C.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? C.sage : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countryCard(flag: String, name: String) -> some View {
        let isSelected = viewModel.selection.selectedCountry == name
        return Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); viewModel.selectCountry(name) } label: {
            HStack(spacing: 10) {
                Text(flag).font(.system(size: 18))
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : C.onSurface)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(isSelected ? C.sage : C.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: isSelected ? C.sage.opacity(0.18) : Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func foodFeelingCard(opt: FoodFeelingOption) -> some View {
        let isSelected = viewModel.selection.foodFeelings.contains(opt.key)
        return Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); viewModel.selectFoodFeeling(opt.key) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(opt.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : C.onSurface)
                Text(opt.desc)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : C.muted)
                    .padding(.top, 1)

                if !opt.exampleMatches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(opt.exampleMatches, id: \.self) { m in
                                Text(m)
                                    .font(.system(size: 10))
                                    .foregroundColor(isSelected ? .white.opacity(0.7) : C.muted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(isSelected ? Color.white.opacity(0.15) : C.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(isSelected ? C.sage : C.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: isSelected ? C.sage.opacity(0.18) : Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
            .opacity(opt.isSurprise && !isSelected ? 0.75 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: - ══════════ FINE-TUNE STEP ══════════

    private var fineTuneStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("The details")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Text("Fine-tune your\nsearch")
                .font(.custom("Georgia", size: 30))
                .foregroundColor(C.onSurface)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            // Price Point
            ftSectionLabel("Price Point")
                .padding(.top, 28)
            ftPriceGrid
                .padding(.top, 10)
                .padding(.horizontal, 20)

            // Party Size
            ftSectionLabel("Party Size")
                .padding(.top, 28)
            ftPartySizeCard
                .padding(.top, 10)
                .padding(.horizontal, 20)

            // Parking
            ftSectionLabel("Parking")
                .padding(.top, 28)
            ftParkingChips
                .padding(.top, 10)
                .padding(.horizontal, 20)

            // Extras
            ftSectionLabel("Extras")
                .padding(.top, 28)
            VStack(spacing: 10) {
                ftExtraRow(icon: "clock.fill",   label: "Open Right Now",    isOn: viewModel.selection.openNow)      { UIImpactFeedbackGenerator(style: .light).impactOccurred(); withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.toggleOpenNow() } }
                ftExtraRow(icon: "leaf.fill",    label: "Outdoor Seating",   isOn: viewModel.selection.outdoorSeating) { UIImpactFeedbackGenerator(style: .light).impactOccurred(); withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.toggleOutdoorSeating() } }
                ftExtraRow(icon: "pawprint.fill", label: "Pet Friendly",     isOn: viewModel.selection.petFriendly)   { UIImpactFeedbackGenerator(style: .light).impactOccurred(); withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.togglePetFriendly() } }
                ftExtraRow(icon: "figure.roll",  label: "Wheelchair Access", isOn: viewModel.selection.wheelchairAccess) { UIImpactFeedbackGenerator(style: .light).impactOccurred(); withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.toggleWheelchairAccess() } }
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)

            // Buttons
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await viewModel.proceedWithFineTune() }
                } label: {
                    HStack(spacing: 8) {
                        Text("Apply & find my spot")
                            .font(.system(size: 15, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(C.terracotta)
                    .clipShape(Capsule())
                    .shadow(color: C.terracotta.opacity(0.25), radius: 16, x: 0, y: 6)
                }
                .buttonStyle(ScalePress())

                Button { viewModel.removeFineTune() } label: {
                    Text("Remove fine-tune")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(C.muted)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 48)
        }
    }

    private func ftSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundColor(C.muted)
            .padding(.horizontal, 20)
    }

    private var ftPriceGrid: some View {
        HStack(spacing: 10) {
            ForEach(["$", "$$", "$$$", "$$$$"], id: \.self) { tier in
                let isSel = viewModel.selection.pricePoints.contains(tier)
                Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); viewModel.togglePrice(tier) } label: {
                    Text(tier)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isSel ? C.onSurface : C.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isSel ? C.neutralBg : C.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSel)
                }
                .buttonStyle(ScalePress())
            }
        }
    }

    private var ftPartySizeCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Party Size")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(C.muted)
                Spacer()
                Text(viewModel.selection.partySize < 10
                     ? "0\(viewModel.selection.partySize) people"
                     : "\(viewModel.selection.partySize) people")
                    .font(.custom("Georgia", size: 22))
                    .foregroundColor(C.sage)
                    .contentTransition(.numericText())
            }

            // Dots + stepper pill
            HStack {
                Button { viewModel.adjustPartySize(-1) } label: {
                    Circle()
                        .fill(C.surface)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(C.onSurface)
                        )
                }
                .buttonStyle(ScalePress())

                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { i in
                        Circle()
                            .fill(i < viewModel.selection.partySize ? C.sage : C.sageMd)
                            .frame(width: 8, height: 8)
                            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: viewModel.selection.partySize)
                    }
                }
                Spacer()

                Button { viewModel.adjustPartySize(1) } label: {
                    Circle()
                        .fill(C.sage)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        )
                }
                .buttonStyle(ScalePress())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(C.white)
            .clipShape(Capsule())
        }
        .padding(20)
        .background(C.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var ftParkingChips: some View {
        let options: [(icon: String, label: String)] = [
            ("car", "Street"),
            ("key.fill", "Valet"),
            ("parkingsign", "Private Lot")
        ]
        return HStack(spacing: 10) {
            ForEach(options, id: \.label) { opt in
                let isSel = viewModel.selection.parking.contains(opt.label)
                Button { UIImpactFeedbackGenerator(style: .light).impactOccurred(); viewModel.toggleParking(opt.label) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: opt.icon)
                            .font(.system(size: 13))
                        Text(opt.label)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(isSel ? .white : C.onSurface)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isSel ? C.sage : C.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(isSel ? C.sage : C.ghostBorder, lineWidth: 1))
                    .shadow(color: isSel ? C.sage.opacity(0.15) : Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSel)
                }
                .buttonStyle(ScalePress())
            }
            Spacer()
        }
    }

    private func ftExtraRow(icon: String, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? C.surface : C.neutralBg)
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(isOn ? C.sage : C.muted)
            }
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(C.onSurface)
            Spacer()
            // Toggle
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? C.sage : C.toggleOff)
                    .frame(width: 48, height: 26)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .padding(3)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            }
        }
        .padding(16)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { action() }
    }

    // MARK: - ══════════ LOADING STEP ══════════

    private var loadingStep: some View {
        VStack(spacing: 0) {
            LoadingPulseView()
                .padding(.top, 80)
                .padding(.bottom, 36)

            Text(viewModel.loadingPhase)
                .font(.custom("Georgia", size: 24))
                .foregroundColor(C.onSurface)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 36)
                .animation(.easeInOut(duration: 0.4), value: viewModel.loadingPhase)

            Text("✦ Using AI to search...")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(C.muted)
                .padding(.top, 10)

            HStack(spacing: 7) {
                dotIndicator(color: C.sage)
                dotIndicator(color: C.sageMd)
                dotIndicator(color: C.sage.opacity(0.2))
                dotIndicator(color: C.sage.opacity(0.2))
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private func dotIndicator(color: Color) -> some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }

    // MARK: - ══════════ REVEAL STEP ══════════

    private var revealStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ────────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Vibe Matches")
                        .font(.system(size: 10, weight: .medium))
                        .tracking(1.0)
                        .textCase(.uppercase)
                        .foregroundStyle(C.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(C.surface)
                        .clipShape(Capsule())

                    Text("· \(viewModel.selection.occasion)")
                        .font(.system(size: 12, weight: .light))
                        .foregroundStyle(C.muted)
                }

                Text("Results for '\(viewModel.selection.location.isEmpty ? "you" : viewModel.selection.location)'")
                    .font(.custom("Georgia", size: 28))
                    .foregroundStyle(C.onSurface)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if !viewModel.recommendations.isEmpty {
                    Text("\(viewModel.recommendations.count) spots curated for your vibe")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(C.muted)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 4)

            // ── Relaxed banner ────────────────────────────────────────────
            if viewModel.lastSearchWasRelaxed && !viewModel.recommendations.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(C.sage)
                    Text("We loosened your filters to find these — adjust to refine.")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(C.onSurface)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(C.sageLt)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 16)
            }

            if viewModel.recommendations.isEmpty {
                emptyResultsState
                    .padding(.top, 32)
            } else {
                // ── Map ───────────────────────────────────────────────────
                BiluMapView(recommendations: viewModel.recommendations, isLoading: viewModel.isEnriching)
                    .padding(.top, 20)

                // ── Cards ─────────────────────────────────────────────────
                VStack(spacing: 28) {
                    ForEach(Array(viewModel.recommendations.enumerated()), id: \.element.id) { index, rec in
                        RecommendationCard(rec: rec)
                            .onTapGesture { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); selectedRestaurant = rec }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.07),
                                value: viewModel.recommendations.count
                            )
                    }
                }
                .padding(.top, 24)
            }

            // ── New Vibe CTA ──────────────────────────────────────────────
            Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); viewModel.reset() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 15))
                    Text("New Vibe")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(C.terracotta)
                .clipShape(Capsule())
            }
            .buttonStyle(ScalePress())
            .padding(.top, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: - Empty / error state for the reveal step

    @ViewBuilder
    private var emptyResultsState: some View {
        let isTransport = viewModel.lastSearchFailure == .transportError
        VStack(spacing: 14) {
            Image(systemName: isTransport ? "wifi.exclamationmark" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(C.sage)
                .frame(width: 56, height: 56)
                .background(C.sageLt)
                .clipShape(Circle())

            Text(isTransport ? "Couldn't reach us" : "Nothing matched, yet")
                .font(.custom("Georgia", size: 22))
                .foregroundStyle(C.onSurface)

            Text(isTransport
                 ? "Something went wrong on our end. Tap retry — usually works the second time."
                 : "Try a different vibe or widen your search — there's always something nearby worth trying.")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(C.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            if isTransport {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task { await viewModel.submitSurvey() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 14, weight: .medium))
                        Text("Try again").font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(C.sage)
                    .clipShape(Capsule())
                }
                .buttonStyle(ScalePress())
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: C.shadowColor, radius: 16, x: 0, y: 6)
    }

    // MARK: - Shared continue button

    private func continueButton(action: @escaping () -> Void) -> some View {
        Button(action: { UIImpactFeedbackGenerator(style: .medium).impactOccurred(); action() }) {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.system(size: 15, weight: .medium))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(C.sage)
            .clipShape(Capsule())
        }
        .buttonStyle(ScalePress())
    }
}

// MARK: - Sub-option bubble (needs @State for stagger animation)

private struct SubBubble: View {
    let sub: FoodSubOption
    let index: Int
    let trigger: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Text(sub.emoji)
                    .font(.system(size: 22))
                    .frame(width: 48, height: 48)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.white.opacity(0.15))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? Color.white : Color.clear, lineWidth: 2)
                    )
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
                Text(sub.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(appeared ? 0.9 : 0))
                    .lineLimit(1)
                    .animation(
                        .spring(response: 0.3, dampingFraction: 0.65)
                            .delay(Double(index) * 0.075 + 0.10),
                        value: appeared
                    )
            }
        }
        .buttonStyle(.plain)
        .offset(y: appeared ? 0 : 16)
        .scaleEffect(appeared ? 1.0 : 0.78)
        .animation(
            .spring(response: 0.3, dampingFraction: 0.65)
                .delay(Double(index) * 0.075),
            value: appeared
        )
        .task(id: trigger) {
            appeared = false
            try? await Task.sleep(nanoseconds: 16_000_000)
            appeared = true
        }
    }
}

#Preview {
    HomeView(selectedTab: .home, onSelectTab: { _ in })
}
