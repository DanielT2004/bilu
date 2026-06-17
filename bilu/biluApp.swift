//
//  biluApp.swift
//  bilu
//

import SwiftUI
import SwiftData

@main
struct biluApp: App {
    let container: ModelContainer
    @StateObject private var savedStore: SavedPlacesStore
    @StateObject private var coordinator = ProfileCoordinator()

    init() {
        let container = try! ModelContainer(for: SavedPlace.self, SavedVibe.self)
        self.container = container
        _savedStore = StateObject(wrappedValue: SavedPlacesStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(savedStore)
                .environmentObject(coordinator)
        }
        .modelContainer(container)
    }
}
