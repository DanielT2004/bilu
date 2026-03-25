//
//  HomeView.swift
//  bilu
//

import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @FocusState private var locationFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if let idx = viewModel.progressStepIndex {
                progressBar(index: idx)
            }
            ScrollView {
                VStack(spacing: 24) {
                    stepContent
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .occasion:
            occasionStep
        case .vibe:
            vibeStep
        case .hunger:
            hungerStep
        case .location:
            locationStep
        case .survey:
            surveyStep
        case .loading:
            loadingStep
        case .reveal:
            revealStep
        }
    }

    private var header: some View {
        Button(action: { viewModel.reset() }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                        .frame(width: 32, height: 32)
                        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
                        .overlay(
                            Image("BiluLogo")
                                .resizable()
                                .scaledToFill()
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("bilu")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))
            }
            .padding(.horizontal, 15)
            .padding(.top, 44)
            .padding(.bottom, 0)
        }
        .buttonStyle(.plain)
    }

    private func progressBar(index: Int) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Array(HomeViewModel.stepsForProgress.enumerated()), id: \.offset) { i, s in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= index ? Color(hex: "8B5CF6") : Color(hex: "E2E8F0"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                        .shadow(color: i <= index ? Color(hex: "8B5CF6").opacity(0.3) : .clear, radius: 10)
                }
            }
            HStack {
                ForEach(Array(HomeViewModel.stepsForProgress.enumerated()), id: \.offset) { i, s in
                    Button {
                        if i < index { viewModel.step = s.id }
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(i <= index ? Color(hex: "8B5CF6") : Color(hex: "94A3B8"))
                                .frame(width: 8, height: 8)
                            Text(s.label)
                                .font(.system(size: 10, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(i == index ? Color(hex: "8B5CF6") : (i > index ? Color(hex: "0F172A").opacity(0.3) : Color(hex: "0F172A")))
                        }
                    }
                    .buttonStyle(.plain)
                    if i < HomeViewModel.stepsForProgress.count - 1 {
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var occasionStep: some View {
        VStack(spacing: 54) {
            VStack(spacing: 4) {
                Text("The Occasion")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))
                Text("How long you got?")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "64748B"))
            }
            .padding(.top, 40)

            VStack(spacing: 20) {
                HorizontalOccasionCard(
                    title: "Grab & Go !",
                    time: "30m",
                    desc: "In, out, done. No small talk.",
                    color: .amber,
                    action: { viewModel.handleOccasion("Grab & Go") }
                )
                HorizontalOccasionCard(
                    title: "Sit Down Vibes",
                    time: "1-2hr",
                    desc: "Sit down and enjoy a meal",
                    color: .purple,
                    action: { viewModel.handleOccasion("Sit Down") }
                )
                HorizontalOccasionCard(
                    title: "Happy Hour",
                    time: "2h+",
                    desc: "Sit down, enjoy the drinks",
                    color: .teal,
                    action: { viewModel.handleOccasion("Happy Hour") }
                )
            }
        }
    }

    private var vibeStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("The Vibe")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))
                Text("Pick one or more")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "64748B"))
            }
            .padding(.top, 24)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(viewModel.vibesForOccasion, id: \.key) { opt in
                    VibeCard(
                        title: opt.displayTitle,
                        desc: opt.desc,
                        systemImage: opt.systemImage,
                        isSelected: viewModel.selection.vibe.contains(opt.key),
                        action: { viewModel.toggleVibe(opt.key) }
                    )
                    .frame(maxWidth: 170)
                }
            }

            if !viewModel.selection.vibe.isEmpty {
                Button {
                    viewModel.step = .hunger
                } label: {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 20))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "8B5CF6"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hungerStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("The Hunger")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))
                Text("Pick one or more")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "64748B"))
            }
            .padding(.top, 24)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(viewModel.hungerForOccasion, id: \.key) { opt in
                    HungerCard(
                        title: opt.displayTitle,
                        desc: opt.desc,
                        systemImage: opt.systemImage,
                        isSelected: viewModel.selection.hunger.contains(opt.key),
                        action: { viewModel.toggleHunger(opt.key) }
                    )
                    .frame(maxWidth: 170)
                }
            }

            if !viewModel.selection.hunger.isEmpty {
                Button {
                    viewModel.step = .location
                } label: {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 20))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(hex: "8B5CF6"))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var locationStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("The Area")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))
                Text("Where are we eating?")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "64748B"))
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 10) {
                Text("Location")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "64748B"))

                TextField(
                    "Neighborhood, city, or address",
                    text: Binding(
                        get: { viewModel.selection.location },
                        set: { viewModel.selection.location = $0 }
                    )
                )
                .focused($locationFieldFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .submitLabel(.next)
                .onSubmit {
                    if !viewModel.selection.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.step = .survey
                    }
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)

                Text("Leave blank to use the Los Angeles area by default.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "94A3B8"))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 24))

            Button {
                viewModel.step = .survey
            } label: {
                HStack {
                    Text("Next")
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 20))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: "8B5CF6"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private var surveyStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text("Search Options")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: "0F172A"))
                Text("Optional tweaks for your results")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "64748B"))
            }
            .padding(.top, 24)

            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(hex: "8B5CF6").opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: "8B5CF6"))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live Google Search")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: "0F172A"))
                        Text("Verify restaurants in real time (slower but more accurate)")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "64748B"))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { viewModel.selection.googleSearch },
                        set: { viewModel.selection.googleSearch = $0 }
                    ))
                    .labelsHidden()
                    .tint(Color(hex: "8B5CF6"))
                }
                .padding(20)
                .background(Color.white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Thinking Level")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "0F172A"))
                    Text("More thinking = deeper reasoning, but slower")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: "64748B"))
                    HStack(spacing: 12) {
                        ForEach(["LOW", "MEDIUM"], id: \.self) { level in
                            Button {
                                viewModel.selection.thinkingLevel = level
                            } label: {
                                Text(level)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(viewModel.selection.thinkingLevel == level ? .white : Color(hex: "0F172A"))
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(viewModel.selection.thinkingLevel == level ? Color(hex: "8B5CF6") : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color(hex: "E2E8F0"), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }

            Button {
                Task { await viewModel.submitSurvey() }
            } label: {
                HStack {
                    Text("Find My Vibe")
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 20))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: "8B5CF6"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingStep: some View {
        VStack(spacing: 24) {
            LoadingPulseView()
            Text("Scanning the streets for your vibe...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(hex: "0F172A"))
            Text(viewModel.loadingPhase)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "64748B"))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

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

            ForEach(Array(viewModel.recommendations.enumerated()), id: \.offset) { _, rec in
                RecommendationCard(rec: rec)
            }

            Button(action: { viewModel.reset() }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18))
                    Text("New Vibe")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(hex: "8B5CF6"))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    HomeView()
        .background(
            Image("BackgroundPattern")
                .resizable()
                .scaledToFill()      // fills the screen, keep aspect ratio
                .opacity(0.1)
                .ignoresSafeArea()
        )
}
