//
//  ContentView.swift
//  bilu
//

import SwiftUI
import SwiftData

// MARK: - Tab

enum Tab {
    case home, search, profile
}

// MARK: - RootTabView

struct RootTabView: View {
    @State private var selectedTab: Tab = .home
    @State private var hideTabBar: Bool = false
    @Namespace private var tabNS
    @EnvironmentObject private var coordinator: ProfileCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                Group {
                    switch selectedTab {
                    case .home:    HomeView(hideTabBar: $hideTabBar)
                    case .search:  SearchView()
                    case .profile: UserView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Single tab bar — slides off-screen when HomeView's survey flow asks for it.
                if !hideTabBar {
                    TabBarView(
                        selectedTab: selectedTab,
                        onSelect: selectTab,
                        namespace: tabNS
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AnimationProfile.selection.animation(reduceMotion: reduceMotion), value: hideTabBar)
        }
        .onChange(of: coordinator.requestedTab) { tab in
            // Profile asks to jump to Home (e.g. re-running a saved vibe).
            guard let tab else { return }
            coordinator.requestedTab = nil
            selectTab(tab)
        }
    }

    private func selectTab(_ tab: Tab) {
        guard tab != selectedTab else { return }
        withAnimation(AnimationProfile.selection.animation(reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: SavedPlace.self, SavedVibe.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootTabView()
        .environmentObject(SavedPlacesStore(context: container.mainContext))
        .environmentObject(ProfileCoordinator())
        .modelContainer(container)
}
