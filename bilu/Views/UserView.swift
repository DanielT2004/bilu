//
//  UserView.swift
//  bilu
//

import SwiftUI
import SwiftData

struct UserView: View {
    @EnvironmentObject private var store: SavedPlacesStore
    @EnvironmentObject private var coordinator: ProfileCoordinator
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \SavedPlace.dateSaved, order: .reverse)
    private var allPlaces: [SavedPlace]
    @Query(sort: \SavedVibe.dateSaved, order: .reverse)
    private var savedVibes: [SavedVibe]

    @State private var selectedList: SavedListType = .saved
    @State private var selectedPlace: SavedPlace? = nil

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

                dietarySection
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
        .sheet(item: $selectedPlace) { place in
            RestaurantDetailView(rec: place.asRecommendation) { [] }
                .environmentObject(store)
        }
        .onAppear { viewModel.refreshPendingShares() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { viewModel.refreshPendingShares() }
        }
    }

    // MARK: - Shared from TikTok

    @ViewBuilder
    private var pendingSharesSection: some View {
        if !viewModel.pendingShares.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("Shared from TikTok")
                PendingSharesRowView(
                    shares: viewModel.pendingShares,
                    onOpen: { share in
                        if let url = URL(string: share.urlString) {
                            openURL(url)
                        }
                    },
                    onDismiss: { share in
                        viewModel.dismissPendingShare(share)
                    }
                )
            }
        }
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
                    icon: selectedList == .saved ? "bookmark" : "airplane.departure",
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
                Label("Move to Want to Go", systemImage: "airplane")
            }
        } else {
            Button {
                store.move(place, to: .saved)
            } label: {
                Label("Move to Saved", systemImage: "bookmark.fill")
            }
        }
        Button(role: .destructive) {
            store.remove(place)
        } label: {
            Label("Remove", systemImage: "trash")
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }
}

#Preview {
    let container = PersistenceController.previewContainer()
    return UserView()
        .environmentObject(SavedPlacesStore(context: container.mainContext))
        .environmentObject(ProfileCoordinator())
        .modelContainer(container)
}
