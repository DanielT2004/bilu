//
//  UserView.swift
//  bilu
//

import SwiftUI
import SwiftData

struct UserView: View {
    /// RootTabView keeps this view alive while hidden; refresh when it is shown again.
    var isActive = true
    @EnvironmentObject private var store: SavedPlacesStore
    @EnvironmentObject private var coordinator: ProfileCoordinator
    @EnvironmentObject private var discoveryAllowance: DiscoveryAllowance
    @EnvironmentObject private var rewardedAds: RewardedAdService
    @StateObject private var viewModel = ProfileViewModel()
    @StateObject private var shareModel = UserView.makeShareModel()
    @State private var shareNeedingCity: PendingTikTokShare? = nil
    @State private var shareCityDraft = ""
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \SavedPlace.dateSaved, order: .reverse)
    private var allPlaces: [SavedPlace]
    @Query(sort: \SavedVibe.dateSaved, order: .reverse)
    private var savedVibes: [SavedVibe]

    @State private var selectedList: SavedListType = .saved
    @State private var selectedPlace: SavedPlace? = nil
    @State private var showingRewardGate = false
    @State private var showingPurchases = false
    @ObservedObject private var purchases = PurchaseStore.shared
    @ObservedObject private var account = AccountViewModel.shared
    @AppStorage(AppDiagnosticsReporter.consentDefaultsKey)
    private var sharesDiagnostics = false

    private var savedPlaces: [SavedPlace] { allPlaces.filter { $0.listType == .saved } }
    private var wantToGoPlaces: [SavedPlace] { allPlaces.filter { $0.listType == .wantToGo } }
    private var visiblePlaces: [SavedPlace] {
        selectedList == .saved ? savedPlaces : wantToGoPlaces
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ProfileHeaderView(
                    avatarEmoji: viewModel.avatarEmoji,
                    displayName: viewModel.displayName,
                    handle: viewModel.handle,
                    hasName: viewModel.hasName,
                    onEdit: { viewModel.beginEditProfile() }
                )
                .padding(.top, 16)

                ProfileStatsView(
                    savedCount: savedPlaces.count,
                    wantToGoCount: wantToGoPlaces.count,
                    cuisineCount: CuisineClassifier.distinctCount(in: allPlaces)
                )
                .padding(.horizontal, 20)

                pendingSharesSection

                savedVibesSection

                listsSection

                discoveryAccessSection

                dietarySection

                privacySection
                    .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.surface.ignoresSafeArea())
        .sheet(isPresented: $viewModel.showingEditProfile) {
            EditProfileView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingDietaryEditor) {
            DietaryPreferencesView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingPurchases) { PurchaseView() }
        .sheet(isPresented: $showingRewardGate) {
            RewardedDiscoveryView()
                .environmentObject(discoveryAllowance)
                .environmentObject(rewardedAds)
        }
        .sheet(item: $selectedPlace) { place in
            RestaurantDetailView(rec: place.asRecommendation, tags: place.tags) { [] }
                .environmentObject(store)
        }
        // RootTabView builds every tab at launch, so this resolves shares on launch.
        .task { await shareModel.refreshAndResolve() }
        .onChange(of: isActive) { _, active in
            if active { shareModel.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await shareModel.refreshAndResolve() } }
        }
        .alert("Which city is this in?", isPresented: Binding(
            get: { shareNeedingCity != nil },
            set: { if !$0 { shareNeedingCity = nil } }
        )) {
            TextField("City, e.g. Los Angeles, CA", text: $shareCityDraft)
                .textInputAutocapitalization(.words)
            Button("Find place") {
                guard let share = shareNeedingCity else { return }
                let city = shareCityDraft
                shareNeedingCity = nil
                Task { await shareModel.retry(share, city: city) }
            }
            Button("Cancel", role: .cancel) { shareNeedingCity = nil }
        } message: {
            Text("We'll look for the place from your TikTok there.")
        }
    }

    // MARK: - Shared from TikTok

    @ViewBuilder
    private var pendingSharesSection: some View {
        if !shareModel.shares.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                sectionLabel("Shared from TikTok")
                PendingSharesRowView(
                    shares: shareModel.shares,
                    resolving: shareModel.resolving,
                    isInWantToGo: { place in
                        store.isSaved(place.recommendation(caption: nil), in: .wantToGo)
                    },
                    onAddToWantToGo: { share, place in
                        var caption: String?
                        if case let .resolved(video, _) = share.resolution { caption = video.caption }
                        store.add(place.recommendation(caption: caption), list: .wantToGo,
                                  tags: place.tags.isEmpty ? nil : place.tags)
                    },
                    onChooseCity: { share in
                        shareCityDraft = ""
                        shareNeedingCity = share
                    },
                    onOpen: { share in
                        if let url = URL(string: share.urlString) {
                            openURL(url)
                        }
                    },
                    onDismiss: { share in
                        shareModel.dismiss(share)
                    }
                )
            }
        }
    }

    private static func makeShareModel() -> PendingSharesModel {
        #if DEBUG
        if PendingSharesModel.fixtureRequested { return .fixture() }
        #endif
        return PendingSharesModel()
    }

    // MARK: - Saved vibes

    @ViewBuilder
    private var savedVibesSection: some View {
        if !savedVibes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Your vibes")
                SavedVibesRowView(vibes: savedVibes) { vibe in
                    if let selection = vibe.selection {
                        coordinator.rerun(selection)
                    }
                }
            }
        }
    }

    // MARK: - Saved / Want-to-Go lists

    private var listsSection: some View {
        VStack(spacing: 16) {
            ProfileSegmentedControl(
                selection: $selectedList,
                savedCount: savedPlaces.count,
                wantToGoCount: wantToGoPlaces.count
            )
            .padding(.horizontal, 20)

            if visiblePlaces.isEmpty {
                ProfileEmptyState(
                    icon: selectedList == .saved ? AppTheme.Icon.saved : AppTheme.Icon.wantToGo,
                    title: selectedList == .saved ? "No saves yet" : "Nowhere on your list yet",
                    message: selectedList == .saved
                        ? "Tap the bookmark on a place you love and it'll land here."
                        : "Add spots to your Want-to-Go list from any restaurant."
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(visiblePlaces) { place in
                        RecommendationCard(rec: place.asRecommendation) {
                            Haptics.light()
                            selectedPlace = place
                        }
                        .contextMenu { contextActions(for: place) }
                        // VoiceOver users can't reach the long-press menu; offer
                        // the same Move/Remove commands as rotor actions.
                        .accessibilityActions { contextActions(for: place) }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func contextActions(for place: SavedPlace) -> some View {
        if place.listType == .saved {
            Button {
                store.move(place, to: .wantToGo)
            } label: {
                Label("Move to Want to Go", systemImage: AppTheme.Icon.wantToGo)
            }
        } else {
            Button {
                store.move(place, to: .saved)
            } label: {
                Label("Move to Saved", systemImage: AppTheme.Icon.saved)
            }
        }
        Button(role: .destructive) {
            store.remove(place)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    // MARK: - Discovery access

    @ViewBuilder
    private var discoveryAccessSection: some View {
        if purchases.configuration.commerceEnabled || account.isSignedIn || purchases.hasPendingSync || purchases.hasPendingApproval || purchases.hasPurchasesForAnotherAccount {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Discoveries")
                ProfileSettingsRow(
                    icon: "sparkles",
                    title: "Discoveries & account",
                    value: purchases.wallet.map { "\($0.remainingExplore) Explore · \($0.remainingTikTok) TikTok" } ?? "View your balance",
                    onTap: { Haptics.light(); showingPurchases = true }
                )
                .padding(.horizontal, 20)
                .accessibilityIdentifier("profile-discoveries")
            }
        }
        if !purchases.configuration.commerceEnabled { legacyDiscoveryAccessSection }
    }

    private var legacyDiscoveryAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Discoveries")

            Button {
                Haptics.light()
                showingRewardGate = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: discoveryAllowance.hasRewardedDiscovery ? "checkmark.seal.fill" : "play.rectangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.primaryInk)
                        .frame(width: 40, height: 40)
                        .background(AppTheme.sageLt)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rewarded discoveries")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.onSurface)
                        Text(discoveryAllowance.hasRewardedDiscovery
                             ? "One discovery unlocked"
                             : "\(discoveryAllowance.remainingFreeDiscoveries) free discovery left today")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.subtle)
                }
                .padding(16)
                .background(AppTheme.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: AppTheme.shadowColor, radius: 12, x: 0, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Dietary

    private var dietarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Preferences")
            ProfileSettingsRow(
                icon: "leaf.fill",
                title: "Dietary",
                value: viewModel.dietarySummary,
                onTap: { viewModel.showingDietaryEditor = true }
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Privacy")

            VStack(spacing: 0) {
                Toggle(isOn: $sharesDiagnostics) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Share Diagnostics")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.onSurface)
                        Text("Share crash, performance, discovery, and ad metrics")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .tint(AppTheme.sage)
                .padding(16)
                .onChange(of: sharesDiagnostics) { _, isEnabled in
                    AppDiagnosticsReporter.shared.setCollectionEnabled(isEnabled)
                }

                Divider()
                    .padding(.leading, 16)

                Button {
                    Haptics.light()
                    openURL(Config.privacyPolicyURL)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .foregroundStyle(AppTheme.primaryInk)
                        Text("Privacy Policy")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.onSurface)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.subtle)
                    }
                    .padding(16)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Bilu's privacy policy")

                if let supportURL = Config.supportURL {
                    Link(destination: supportURL) {
                        Label("Report an advertisement", systemImage: "flag")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.onSurface)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    .accessibilityHint("Opens Bilu support to report an inappropriate ad")
                }

                if rewardedAds.privacyOptionsRequired {
                    Divider()
                        .padding(.leading, 16)

                    Button {
                        Haptics.light()
                        Task { await rewardedAds.presentPrivacyOptions() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundStyle(AppTheme.primaryInk)
                            Text("Ad privacy choices")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.onSurface)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppTheme.subtle)
                        }
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(AppTheme.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.shadowColor, radius: 12, x: 0, y: 4)
            .padding(.horizontal, 20)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    let container = PersistenceController.previewContainer()
    return UserView()
        .environmentObject(SavedPlacesStore(context: container.mainContext))
        .environmentObject(ProfileCoordinator())
        .environmentObject(DiscoveryAllowance.shared)
        .environmentObject(RewardedAdService.shared)
        .modelContainer(container)
}
