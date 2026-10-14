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

/// Native `TabView`: Liquid Glass on iOS 26, the standard bar on iOS 17/18.
/// Each tab item shows only its icon; the text label is kept for VoiceOver.
struct RootTabView: View {
    @State private var selectedTab: Tab = .home
    @State private var hideTabBar: Bool = false
    @State private var homeReselectCount = 0
    @StateObject private var searchViewModel = SearchViewModel()
    @EnvironmentObject private var coordinator: ProfileCoordinator

    var body: some View {
        // TabView keeps every tab alive, so leaving one keeps its progress,
        // results and scroll position. Re-selecting Explore returns it to the start.
        TabView(selection: tabSelection) {
            HomeView(hideTabBar: $hideTabBar, reselectCount: homeReselectCount)
                // HomeView decides when its survey hides the bar (shouldHideTabBar).
                .toolbar(hideTabBar ? .hidden : .visible, for: .tabBar)
                .tabItem { tabIcon("house", label: "Explore") }
                .tag(Tab.home)

            SearchView(viewModel: searchViewModel)
                .tabItem { tabIcon("magnifyingglass", label: "Search") }
                .tag(Tab.search)

            UserView(isActive: selectedTab == .profile)
                .tabItem { tabIcon("person.crop.circle", label: "Profile") }
                .tag(Tab.profile)
        }
        .tint(AppTheme.sage)
        .onChange(of: coordinator.requestedTab) { _, tab in
            // Profile asks to jump to Home (e.g. re-running a saved vibe).
            guard let tab else { return }
            coordinator.requestedTab = nil
            selectTab(tab)
        }
    }

    /// A native TabView only writes its selection when it changes, but it does call
    /// the binding's setter on every tap, so routing writes through `selectTab`
    /// lets a tap on the already-selected Explore tab reset the journey.
    private var tabSelection: Binding<Tab> {
        Binding(get: { selectedTab }, set: { selectTab($0) })
    }

    private func selectTab(_ tab: Tab) {
        guard tab != selectedTab else {
            if tab == .home { homeReselectCount += 1 }
            return
        }
        // Dismiss a keyboard the old tab still owns before switching.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        selectedTab = tab
    }

    /// Icon-only tab item. An image without a `Text` gives the native bar no
    /// visible title; the label is what VoiceOver reads and UI tests query
    /// (`app.tabBars.buttons["Explore"]`; native tab items drop custom identifiers).
    private func tabIcon(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .accessibilityLabel(label)
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
