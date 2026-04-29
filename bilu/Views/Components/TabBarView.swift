//
//  TabBarView.swift
//  bilu
//

import SwiftUI

private let C = AppTheme.self

struct TabBarView: View {
    let selectedTab: Tab
    let onSelect: (Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabItem(active: "house.fill",                 inactive: "house",                 label: "Explore", tab: .home)
            tabItem(active: "magnifyingglass",            inactive: "magnifyingglass",       label: "Search",  tab: .search)
            tabItem(active: "person.crop.circle.fill",    inactive: "person.crop.circle",    label: "Profile", tab: .profile)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(AppTheme.surface.opacity(0.88))
        .background(.ultraThinMaterial)
    }

    private func tabItem(active: String, inactive: String, label: String, tab: Tab) -> some View {
        let isActive = selectedTab == tab
        return VStack(spacing: 3) {
            Image(systemName: isActive ? active : inactive)
                .font(.system(size: 18, weight: isActive ? .medium : .light))
            Text(label)
                .font(.system(size: 10))
            Circle()
                .fill(isActive ? C.sage : Color.clear)
                .frame(width: 4, height: 4)
        }
        .foregroundColor(isActive ? C.sage : C.subtle)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(tab)
        }
    }
}
