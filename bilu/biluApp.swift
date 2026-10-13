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
    @StateObject private var discoveryAllowance = DiscoveryAllowance.shared
    @StateObject private var rewardedAds = RewardedAdService.shared
    @StateObject private var purchases = PurchaseStore.shared
    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    private let purchasePreview = PurchasePreviewFixtures.current
    #endif

    init() {
        // Default URLCache.shared is far too small to hold the food-photo icons,
        // TikTok thumbnails, and restaurant photos the app loads via AsyncImage —
        // they'd evict each other constantly. Unsplash/Places already send
        // long-lived Cache-Control headers, so a bigger cache is enough to make
        // repeat loads come from disk instead of the network.
        URLCache.shared = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        AppDiagnosticsReporter.shared.startIfConsented()

        let container = PersistenceController.makeContainer()
        self.container = container
        _savedStore = StateObject(wrappedValue: SavedPlacesStore(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            appContent
                .environmentObject(savedStore)
                .environmentObject(coordinator)
                .environmentObject(discoveryAllowance)
                .environmentObject(rewardedAds)
                .task {
                    #if DEBUG
                    if LoadingAdPreview.scenario != nil { return }
                    if let purchasePreview { await purchasePreview.prepare(); return }
                    #endif
                    await AccountViewModel.shared.loadCachedAccount()
                    await purchases.start()
                }
                .task {
                    #if DEBUG
                    if purchasePreview != nil || LoadingAdPreview.scenario != nil { return }
                    #endif
                    await AdPrivacyService.shared.configure()
                    if !purchases.configuration.commerceEnabled { await rewardedAds.configure() }
                }
                .onChange(of: scenePhase) { _, phase in
                    #if DEBUG
                    if purchasePreview != nil || LoadingAdPreview.scenario != nil { return }
                    #endif
                    if phase == .active { Task { await purchases.retryPendingPurchases() } }
                }
        }
        .modelContainer(container)
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
        if let scenario = LoadingAdPreview.scenario {
            LoadingAdPreview(scenario: scenario)
        } else if let purchasePreview {
            PurchaseView(purchases: purchasePreview.purchases, account: purchasePreview.account)
        } else {
            RootTabView()
        }
        #else
        RootTabView()
        #endif
    }
}
