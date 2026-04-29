//
//  ContentView.swift
//  bilu
//

import SwiftUI

// MARK: - Tab

enum Tab {
    case home, search, profile
}

// MARK: - RootTabView

struct RootTabView: View {
    @State private var selectedTab: Tab = .home

    var body: some View {
        ZStack {
            AppTheme.surface.ignoresSafeArea()
            switch selectedTab {
            case .home:    HomeView(selectedTab: selectedTab, onSelectTab: selectTab)
            case .search:  SearchView(selectedTab: selectedTab, onSelectTab: selectTab)
            case .profile: UserView(selectedTab: selectedTab, onSelectTab: selectTab)
            }
        }
    }

    private func selectTab(_ tab: Tab) {
        selectedTab = tab
    }
}

#Preview {
    RootTabView()
}
