//
//  HomeView.swift
//  bilu
//

import SwiftUI
import CoreLocation

// MARK: - Design tokens
private let C = BiluColors.self

private enum BiluColors {
    static let cream  = Color(hex: "f0ede6")
    static let green  = Color(hex: "3d5a2e")
    static let greenLt = Color(hex: "e8f0e0")
    static let greenMd = Color(hex: "c8d4b8")
    static let dark   = Color(hex: "1e2d14")
    static let muted  = Color(hex: "7a8a6a")
    static let subtle = Color(hex: "a0aa90")
    static let border = Color(hex: "3d5a2e").opacity(0.1)
    static let white  = Color.white
}

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

    var body: some View {
        VStack(spacing: 0) {
            header
            if let idx = viewModel.progressStepIndex {
                progressBar(index: idx)
            }
            ScrollView {
                VStack(spacing: 0) {
                    stepContent
                }
                .padding(.bottom, viewModel.step == .occasion ? 20 : 100)
            }
            .scrollIndicators(.hidden)

            if viewModel.step == .occasion {
                bottomNavBar
            }
        }
        .background(C.cream)
        .sheet(item: $selectedRestaurant) { rec in
            RestaurantDetailView(rec: rec)
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
                iconButton(systemName: "person", tint: C.green) { }
            } else {
                iconButton(systemName: "chevron.left", tint: C.green) { viewModel.goBack() }
            }
            Spacer()
            Text("bilu")
                .font(.custom("Georgia", size: 22))
                .foregroundColor(C.green)
            Spacer()
            if viewModel.step == .occasion {
                iconButton(systemName: "bell", tint: C.green) { }
            } else {
                iconButton(systemName: "xmark", tint: C.muted) { viewModel.reset() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 52)
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
                .overlay(Circle().stroke(C.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress bar

    private func progressBar(index: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        i < index  ? C.green :
                        i == index ? C.green.opacity(0.45) :
                                     C.green.opacity(0.1)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 3)
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
        .background(C.white)
        .overlay(Rectangle().fill(C.border).frame(height: 0.5), alignment: .top)
    }

    private func navItem(systemName: String, label: String, isActive: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: isActive ? .medium : .light))
            Text(label)
                .font(.system(size: 10))
            Circle()
                .fill(isActive ? C.green : Color.clear)
                .frame(width: 4, height: 4)
        }
        .foregroundColor(isActive ? C.green : C.subtle)
    }

    // MARK: - ══════════ OCCASION STEP ══════════

    private var occasionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Map widget
            HomeMapWidget(
                locationLabel: viewModel.mapLocationLabel,
                onChangeTapped: { viewModel.step = .location },
                onRadiusChanged: { miles, coord in
                    viewModel.selection.radiusMiles = miles
                    viewModel.selection.latitude = coord.latitude
                    viewModel.selection.longitude = coord.longitude
                }
            )
            .padding(.top, 10)

            // Greeting
            VStack(alignment: .leading, spacing: 5) {
                Text("Hi Danny,\nwhere to?")
                    .font(.custom("Georgia", size: 28))
                    .foregroundColor(C.dark)
                    .lineSpacing(2)
                Text("Pick an occasion and we'll find your spot")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(C.muted)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            // Section label
            Text("What's the occasion?")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 10)

            // Occasion grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                occasionCard(title: "Quick Bite",    sub: "Fast & easy",       emoji: "⚡", bgHex: "e8f0e0")
                occasionCard(title: "Date Night",    sub: "Romantic vibes",    emoji: "♡",  bgHex: "fbeaf0")
                occasionCard(title: "Sit Down Meal", sub: "Friends hangout",   emoji: "🍴", bgHex: "e1f5ee")
                occasionCard(title: "Big Group",     sub: "6+ people",         emoji: "👥", bgHex: "e6f1fb")
                occasionCard(title: "Cafe",          sub: "Coffee & hangs",    emoji: "☕", bgHex: "faeeda")
                occasionCard(title: "Happy Hour",    sub: "Drinks & vibes",    emoji: "🍸", bgHex: "faece7")
                occasionCard(title: "Celebration",   sub: "Special occasions", emoji: "🎉", bgHex: "eeedfe")
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func occasionCard(title: String, sub: String, emoji: String, bgHex: String) -> some View {
        Button { viewModel.handleOccasion(title) } label: {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: bgHex))
                    .frame(width: 36, height: 36)
                    .overlay(Text(emoji).font(.system(size: 16)))
                    .padding(.bottom, 10)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(C.dark)
                Text(sub)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(Color(hex: "8a9a7a"))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(C.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(C.border, lineWidth: 0.5))
        }
        .buttonStyle(ScalePress())
    }

    // MARK: - ══════════ KEY QUESTION STEP ══════════

    private var keyQuestionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kq = viewModel.keyQuestion {
                // Stage tag
                Text(kq.columnLabel)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundColor(C.muted)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                // Serif question
                Text(kq.question)
                    .font(.custom("Georgia", size: 30))
                    .foregroundColor(C.dark)
                    .lineSpacing(2)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Choice cards
                VStack(spacing: 9) {
                    ForEach(kq.options, id: \.key) { opt in
                        let isSelected = viewModel.selection.keyQuestionAnswer == opt.key
                        keyChoiceCard(opt: opt, isSelected: isSelected)

                        // Inline sub-picker
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

                // Continue button
                if viewModel.canContinueFromKeyQuestion {
                    continueButton { viewModel.continueFromKeyQuestion() }
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
                // Emoji icon box
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.15) : C.greenLt)
                    .frame(width: 42, height: 42)
                    .overlay(Text(opt.icon).font(.system(size: 20)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(opt.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isSelected ? .white : C.dark)
                        if let badge = opt.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? C.green : Color(hex: "27500a"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white : C.greenLt)
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
            .background(isSelected ? C.green : C.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? C.green : C.border, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func timeWindowPicker(options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What time works for you?")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(C.green)
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
                            .background(isSel ? C.green : C.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .padding(.leading, 14)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.border, lineWidth: 0.5))
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Which date are you thinking?")
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(C.green)
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
            .accentColor(C.green)
        }
        .padding(12)
        .padding(.leading, 14)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.border, lineWidth: 0.5))
    }

    // MARK: - ══════════ FOOD FEELING STEP ══════════

    private var foodFeelingStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stage tag
            Text(viewModel.selection.occasion)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            // Serif question
            Text("How do you want\nthe food to feel?")
                .font(.custom("Georgia", size: 30))
                .foregroundColor(C.dark)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Text("Pick one or more — we'll find the cuisine")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 6)

            // Food feeling cards
            VStack(spacing: 9) {
                ForEach(viewModel.foodFeelingsForOccasion, id: \.key) { opt in
                    foodFeelingCard(opt: opt)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            continueButton { viewModel.continueFromFoodFeeling() }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
                .opacity(viewModel.canContinueFromFoodFeeling ? 1 : 0.4)
                .disabled(!viewModel.canContinueFromFoodFeeling)
        }
    }

    private func foodFeelingCard(opt: FoodFeelingOption) -> some View {
        let isSelected = viewModel.selection.foodFeelings.contains(opt.key)
        return Button { viewModel.selectFoodFeeling(opt.key) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(opt.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : C.dark)
                Text(opt.desc)
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : C.muted)
                    .padding(.top, 1)

                if !isSelected && !opt.exampleMatches.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(opt.exampleMatches, id: \.self) { m in
                                Text(m)
                                    .font(.system(size: 10))
                                    .foregroundColor(C.muted)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(C.cream)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.border, lineWidth: 0.5))
                            }
                        }
                    }
                    .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(isSelected ? C.green : C.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? C.green : C.border,
                        style: opt.isSurprise
                            ? StrokeStyle(lineWidth: 1, dash: [5, 5])
                            : StrokeStyle(lineWidth: 1)
                    )
            )
            .opacity(opt.isSurprise && !isSelected ? 0.75 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - ══════════ FINE-TUNE STEP ══════════

    private var fineTuneStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Stage tag
            Text("The details")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
                .padding(.horizontal, 20)
                .padding(.top, 18)

            // Serif title
            Text(viewModel.fineTuneTitle)
                .font(.custom("Georgia", size: 30))
                .foregroundColor(C.dark)
                .lineSpacing(2)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            VStack(spacing: 0) {
                // Location
                fineTuneSection(title: "Where are we eating?") {
                    AnyView(locationField)
                }

                // Price (conditional)
                if viewModel.showPriceSection {
                    fineTuneSection(title: "Price point") {
                        AnyView(priceButtons)
                    }
                }

                // Party size (conditional)
                if viewModel.showPartySizeSection {
                    partySizeRow
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                }

                // Open now toggle (always)
                openNowToggle
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
            .padding(.top, 14)

            // Find my spot button
            Button {
                Task { await viewModel.submitSurvey() }
            } label: {
                HStack(spacing: 8) {
                    Text("Find my spot")
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(C.green)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
    }

    private func fineTuneSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(C.muted)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var locationField: some View {
        TextField(
            "Neighborhood, city, or address",
            text: Binding(
                get: { viewModel.selection.location },
                set: { viewModel.selection.location = $0 }
            )
        )
        .focused($locationFieldFocused)
        .autocorrectionDisabled(false)
        .font(.system(size: 13))
        .foregroundColor(C.dark)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(C.border, lineWidth: 0.5))
    }

    private var priceButtons: some View {
        HStack(spacing: 7) {
            ForEach(["$", "$$", "$$$", "$$$$"], id: \.self) { tier in
                let isSel = viewModel.selection.pricePoints.contains(tier)
                Button { viewModel.togglePrice(tier) } label: {
                    Text(tier)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSel ? .white : C.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isSel ? C.green : C.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSel ? C.green : C.green.opacity(0.2), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var partySizeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("How many people?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(C.dark)
                Text("We'll find spots that fit")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(C.muted)
            }
            Spacer()
            HStack(spacing: 12) {
                Button { viewModel.adjustPartySize(-1) } label: {
                    Circle()
                        .stroke(C.green.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                        .overlay(Text("−").font(.system(size: 18)).foregroundColor(C.green))
                }
                .buttonStyle(.plain)

                Text(viewModel.selection.partySize < 10
                     ? "0\(viewModel.selection.partySize)"
                     : "\(viewModel.selection.partySize)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(C.green)
                    .frame(minWidth: 28)

                Button { viewModel.adjustPartySize(1) } label: {
                    Circle()
                        .stroke(C.green.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                        .overlay(Text("+").font(.system(size: 18)).foregroundColor(C.green))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.border, lineWidth: 0.5))
    }

    private var openNowToggle: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Open right now")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(C.dark)
                Text("Only show currently open spots")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(C.muted)
            }
            Spacer()
            // Custom toggle matching HTML style
            ZStack(alignment: viewModel.selection.openNow ? .trailing : .leading) {
                Capsule()
                    .fill(viewModel.selection.openNow ? C.green : Color(hex: "c8c8bc"))
                    .frame(width: 44, height: 24)
                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(3)
            }
            .onTapGesture { withAnimation(.spring(duration: 0.2)) { viewModel.toggleOpenNow() } }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(C.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(C.border, lineWidth: 0.5))
    }

    // MARK: - ══════════ LOADING STEP ══════════

    private var loadingStep: some View {
        VStack(spacing: 0) {
            LoadingPulseView()
                .padding(.top, 80)
                .padding(.bottom, 36)

            Text(viewModel.loadingPhase)
                .font(.custom("Georgia", size: 24))
                .foregroundColor(C.dark)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 36)
                .animation(.easeInOut(duration: 0.4), value: viewModel.loadingPhase)

            Text("✦ Using AI to search...")
                .font(.system(size: 13, weight: .light))
                .foregroundColor(C.muted)
                .padding(.top, 10)

            // Progress dots
            HStack(spacing: 7) {
                dotIndicator(color: C.green)
                dotIndicator(color: C.greenMd)
                dotIndicator(color: C.border)
                dotIndicator(color: C.border)
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
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Your Picks")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))
                Text("\(viewModel.recommendations.count) spots for your vibe")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "64748B"))
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity)

            BiluMapView(recommendations: viewModel.recommendations, isLoading: viewModel.isEnriching)

            ForEach(Array(viewModel.recommendations.enumerated()), id: \.offset) { _, rec in
                RecommendationCard(rec: rec, onTap: { selectedRestaurant = rec })
            }

            Button(action: { viewModel.reset() }) {
                HStack {
                    Image(systemName: "arrow.clockwise").font(.system(size: 18))
                    Text("New Vibe")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: "8B5CF6"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
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
            .background(C.green)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HomeView()
}
