//
//  ProfileCoordinator.swift
//  bilu
//
//  Tiny cross-tab channel for the one coupling the Profile needs: tapping a saved
//  vibe should jump to the Home tab and re-run that search. RootTabView observes
//  `requestedTab`; HomeView consumes `pendingVibe` (watching the Equatable token
//  since VibeSelection isn't Equatable).
//

import Foundation
import Combine

@MainActor
final class ProfileCoordinator: ObservableObject {
    /// Set by Profile to ask RootTabView to switch tabs.
    @Published var requestedTab: Tab?
    /// Bumped each time a re-run is requested — an Equatable signal HomeView can observe.
    @Published var pendingVibeToken: Int = 0
    /// The vibe to restore + re-run once Home reads the bumped token.
    var pendingVibe: VibeSelection?

    func rerun(_ selection: VibeSelection) {
        pendingVibe = selection
        pendingVibeToken += 1
        requestedTab = .home
    }
}
