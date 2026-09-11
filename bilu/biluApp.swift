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
        // Default URLCache.shared is far too small to hold the food-photo icons,
        // TikTok thumbnails, and restaurant photos the app loads via AsyncImage —
        // they'd evict each other constantly. Unsplash/Places already send
        // long-lived Cache-Control headers, so a bigger cache is enough to make
        // repeat loads come from disk instead of the network.
        URLCache.shared = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)

        let container = PersistenceController.makeContainer()
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
