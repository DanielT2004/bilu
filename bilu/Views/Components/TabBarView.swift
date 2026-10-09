//
//  TabBarView.swift
//  bilu
//

import SwiftUI

private let C = AppTheme.self

struct TabBarView: View {
    let selectedTab: Tab
    let onSelect: (Tab) -> Void
    let namespace: Namespace.ID

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
            // The active dot uses matchedGeometryEffect so it slides between
            // tabs instead of jump-cutting. Inactive slots render an invisible
            // placeholder of equal size to preserve vertical layout.
            ZStack {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 4, height: 4)
                if isActive {
                    Circle()
                        .fill(C.sage)
                        .frame(width: 4, height: 4)
                        .matchedGeometryEffect(id: "tabDot", in: namespace)
                }
            }
        }
        .foregroundColor(isActive ? C.sage : C.subtle)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.light()
            onSelect(tab)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityIdentifier("tab-\(label.lowercased())")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
