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
    @State private var homeReselectCount = 0
    @StateObject private var searchViewModel = SearchViewModel()
    @Namespace private var tabNS
    @EnvironmentObject private var coordinator: ProfileCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.surface.ignoresSafeArea()

            VStack(spacing: 0) {
                // Every tab stays alive so leaving one keeps its progress, results
                // and scroll position. Re-selecting Explore returns it to the start.
                ZStack {
                    tabPage(.home) {
                        HomeView(hideTabBar: $hideTabBar, reselectCount: homeReselectCount)
                    }
                    tabPage(.search) { SearchView(viewModel: searchViewModel) }
                    tabPage(.profile) { UserView(isActive: selectedTab == .profile) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Single tab bar — slides off-screen when HomeView's survey flow asks for it.
                if !(hideTabBar && selectedTab == .home) {
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
        .onChange(of: coordinator.requestedTab) { _, tab in
            // Profile asks to jump to Home (e.g. re-running a saved vibe).
            guard let tab else { return }
            coordinator.requestedTab = nil
            selectTab(tab)
        }
    }

    private func selectTab(_ tab: Tab) {
        guard tab != selectedTab else {
            if tab == .home { homeReselectCount += 1 }
            return
        }
        // Hidden tabs stay alive, so dismiss a keyboard the old tab still owns.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(AnimationProfile.selection.animation(reduceMotion: reduceMotion)) {
            selectedTab = tab
        }
    }

    private func tabPage<Content: View>(_ tab: Tab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = tab == selectedTab
        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
    }
}

#Preview {
    let container = PersistenceController.previewContainer()
    return RootTabView()
        .environmentObject(SavedPlacesStore(context: container.mainContext))
        .environmentObject(ProfileCoordinator())
        .environmentObject(DiscoveryAllowance.shared)
        .environmentObject(RewardedAdService.shared)
        .modelContainer(container)
}
