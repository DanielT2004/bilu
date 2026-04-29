//
//  UserView.swift
//  bilu
//

import SwiftUI

private let C = AppTheme.self

struct UserView: View {
    let selectedTab: Tab
    let onSelectTab: (Tab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(C.sageLt)
                        .frame(width: 88, height: 88)
                    Image(systemName: "person.fill")
                        .font(.system(size: 38, weight: .light))
                        .foregroundColor(C.sage)
                }

                Text("Profile")
                    .font(.custom("Georgia", size: 24))
                    .foregroundColor(C.onSurface)

                Text("Coming soon")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundColor(C.subtle)
            }

            Spacer()

            TabBarView(selectedTab: selectedTab, onSelect: onSelectTab)
        }
        .background(C.surface.ignoresSafeArea())
    }
}

#Preview {
    UserView(selectedTab: .profile, onSelectTab: { _ in })
}
