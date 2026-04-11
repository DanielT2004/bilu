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
    @StateObject private var viewModel = HomeViewModel()
    @FocusState private var locationFieldFocused: Bool
    @State private var selectedRestaurant: Recommendation? = nil
    @State private var stepForward = true
    @State private var mapIsExpanded = false

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
                .onChange(of: viewModel.step) { _ in
                    proxy.scrollTo("top", anchor: .top)
                }
            }

            if viewModel.step == .occasion {
                bottomNavBar
            }
        }
        .background(C.surface)
        .sheet(item: $selectedRestaurant) { rec in
            RestaurantDetailView(rec: rec, tikTokVideos: viewModel.tikTokVideos[rec.id] ?? [])
        }
    }

    // MARK: - Step router

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .occasion:     occasionStep
        case .keyQuestion:  keyQuestionStep
        case .foodFeeling:  foodFeelingStep
        case .location:     fineTuneStep
        case .loading:      loadingStep
        case .reveal:       revealStep
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if viewModel.step == .occasion {
                iconButton(systemName: "person", tint: C.sage) { }
            } else {
                iconButton(systemName: "chevron.left", tint: C.sage) { stepForward = false; viewModel.goBack() }
            }
            Spacer()
            Text("bilu")
                .font(.custom("Georgia", size: 22))
                .foregroundColor(C.sage)
            Spacer()
            if viewModel.step == .occasion {
                iconButton(systemName: "bell", tint: C.sage) { }
            } else {
                iconButton(systemName: "xmark", tint: C.muted) { viewModel.reset() }
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
                .shadow(color: C.shadowColor, radius: 6, y: 2)
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

    // MARK: - Bottom nav (occasion step only)

    private var bottomNavBar: some View {
        HStack {
            navItem(systemName: "house",    label: "Explore",   isActive: true)
            Spacer()
            navItem(systemName: "heart",    label: "Saved",     isActive: false)
            Spacer()
            navItem(systemName: "calendar", label: "Bookings",  isActive: false)
            Spacer()
            navItem(systemName: "person",   label: "Profile",   isActive: false)
        }
        .padding(.horizontal, 30)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
    }

    private func navItem(systemName: String, label: String, isActive: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: isActive ? .medium : .light))
            Text(label)
                .font(.system(size: 10))
            Circle()
                .fill(isActive ? C.sage : Color.clear)
                .frame(width: 4, height: 4)
        }
        .foregroundColor(isActive ? C.sage : C.subtle)
    }

    // MARK: - ══════════ OCCASION STEP ══════════

    private var occasionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            HomeMapWidget(
                locationLabel: viewModel.mapLocationLabel,
                isExpanded: $mapIsExpanded,
                onRadiusChanged: { miles, coord in
                    viewModel.selection.radiusMiles = miles
                    viewModel.selection.latitude = coord.latitude
                    viewModel.selection.longitude = coord.longitude
                },
                onLocationResolved: { label in
                    viewModel.detectedLocation = label
                    viewModel.selection.location = label
                }
            )
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 5) {
                Text("Hi Danny,\nwhere to?")
                    .font(.custom("Georgia", size: 28))
                    .foregroundColor(C.onSurface)
                    .lineSpacing(2)
                Text("Pick an occasion and we'll find your spot")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(C.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Text("What's the occasion?")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                occasionCard(title: "Quick Bite",    sub: "Fast & easy",       emoji: "⚡", bgHex: "e8f0e0")
                occasionCard(title: "Date Night",    sub: "Romantic vibes",    emoji: "♡",  bgHex: "f5e8ee")
                occasionCard(title: "Sit Down Meal", sub: "Friends hangout",   emoji: "🍴", bgHex: "e1f5ee")
                occasionCard(title: "Big Group",     sub: "6+ people",         emoji: "👥", bgHex: "e6f1fb")
                occasionCard(title: "Cafe",          sub: "Coffee & hangs",    emoji: "☕", bgHex: "f5eedc")
                occasionCard(title: "Happy Hour",    sub: "Drinks & vibes",    emoji: "🍸", bgHex: "f5e8e4")
                occasionCard(title: "Celebration",   sub: "Special occasions", emoji: "🎉", bgHex: "eeedfe")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.35)) { mapIsExpanded = false }
        }
    }

    private func occasionCard(title: String, sub: String, emoji: String, bgHex: String) -> some View {
        Button { stepForward = true; viewModel.handleOccasion(title) } label: {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: bgHex))
                    .frame(width: 36, height: 36)
                    .overlay(Text(emoji).font(.system(size: 16)))
                    .padding(.bottom, 10)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(C.onSurface)
                Text(sub)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(C.muted)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(C.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: C.shadowColor, radius: 12, x: 0, y: 4)
        }
        .buttonStyle(ScalePress())
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
        Button { viewModel.selectKeyQuestionAnswer(opt.key) } label: {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.15) : C.sageLt)
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
                                .foregroundColor(isSelected ? C.sage : Color(hex: "27500a"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white : C.sageLt)
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
            .shadow(color: isSelected ? C.sage.opacity(0.18) : C.shadowColor, radius: 12, x: 0, y: 4)
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
                    Button { viewModel.selectKeyQuestionTimeWindow(t) } label: {
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
        .shadow(color: C.shadowColor, radius: 10, x: 0, y: 3)
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
        .shadow(color: C.shadowColor, radius: 10, x: 0, y: 3)
    }

    // MARK: - ══════════ FOOD FEELING STEP ══════════

    private var foodFeelingStep: some View {
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
                            .foregroundColor(C.sage)
                            .frame(width: 52, height: 52)
                            .background(C.sageLt)
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
            Capsule().fill(C.sageLt)
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
        return Button { viewModel.selectCountry(name) } label: {
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
            .shadow(color: isSelected ? C.sage.opacity(0.18) : C.shadowColor, radius: 10, x: 0, y: 3)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func foodFeelingCard(opt: FoodFeelingOption) -> some View {
        let isSelected = viewModel.selection.foodFeelings.contains(opt.key)
        return Button { viewModel.selectFoodFeeling(opt.key) } label: {
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
            .shadow(color: isSelected ? C.sage.opacity(0.18) : C.shadowColor, radius: 10, x: 0, y: 3)
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
                ftExtraRow(icon: "clock.fill",   label: "Open Right Now",    isOn: viewModel.selection.openNow)      { withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.toggleOpenNow() } }
                ftExtraRow(icon: "leaf.fill",    label: "Outdoor Seating",   isOn: viewModel.selection.outdoorSeating) { withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.toggleOutdoorSeating() } }
                ftExtraRow(icon: "pawprint.fill", label: "Pet Friendly",     isOn: viewModel.selection.petFriendly)   { withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.togglePetFriendly() } }
                ftExtraRow(icon: "figure.roll",  label: "Wheelchair Access", isOn: viewModel.selection.wheelchairAccess) { withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { viewModel.toggleWheelchairAccess() } }
            }
            .padding(.top, 10)
            .padding(.horizontal, 20)

            // Buttons
            VStack(spacing: 12) {
                Button {
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
                Button { viewModel.togglePrice(tier) } label: {
                    Text(tier)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(isSel ? C.onSurface : C.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isSel ? C.sageLt : C.surface)
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
                Button { viewModel.toggleParking(opt.label) } label: {
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
                    .shadow(color: isSel ? C.sage.opacity(0.15) : C.shadowColor, radius: 8, x: 0, y: 3)
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
                    .fill(isOn ? C.sageLt : Color(hex: "eeecea"))
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
                    .fill(isOn ? C.sage : Color(hex: "c8c8bc"))
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
                        .foregroundStyle(C.sage)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(C.sageLt)
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

                Text("\(viewModel.recommendations.count) spots curated for your vibe")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(C.muted)
            }
            .padding(.top, 24)
            .padding(.horizontal, 4)

            // ── Map ───────────────────────────────────────────────────────
            BiluMapView(recommendations: viewModel.recommendations, isLoading: viewModel.isEnriching)
                .padding(.top, 20)

            // ── Cards ─────────────────────────────────────────────────────
            VStack(spacing: 28) {
                ForEach(Array(viewModel.recommendations.enumerated()), id: \.element.id) { index, rec in
                    RecommendationCard(rec: rec, tikTokVideos: viewModel.tikTokVideos[rec.id] ?? [])
                        .onTapGesture { selectedRestaurant = rec }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.8).delay(Double(index) * 0.07),
                            value: viewModel.recommendations.count
                        )
                }
            }
            .padding(.top, 24)

            // ── New Vibe CTA ──────────────────────────────────────────────
            Button(action: { viewModel.reset() }) {
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

    // MARK: - Shared continue button

    private func continueButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

#Preview {
    HomeView()
}
