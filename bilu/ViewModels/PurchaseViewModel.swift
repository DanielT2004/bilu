import Combine
import Foundation

@MainActor
final class PurchaseViewModel: ObservableObject {
    enum Intent { case profile, explore, tiktok }
    let intent: Intent
    let purchases: PurchaseStore
    let account: AccountViewModel

    init(intent: Intent = .profile, purchases: PurchaseStore? = nil, account: AccountViewModel? = nil) {
        self.intent = intent
        self.purchases = purchases ?? .shared
        self.account = account ?? .shared
    }

    var canContinue: Bool {
        guard let wallet = purchases.wallet, !purchases.isLoading, !account.isBusy else { return false }
        switch intent {
        case .profile: return false
        case .explore: return wallet.remainingExplore > 0
        case .tiktok: return wallet.remainingTikTok > 0
        }
    }

    var statusTitle: String? {
        switch purchases.state {
        case .idle: return nil
        case .purchasing: return "Confirming your purchase"
        case .pendingApproval: return "Waiting for approval"
        case .syncPending: return "Your purchase is still syncing"
        case .purchased: return "Ready for your next discovery"
        case .restored: return "Purchases restored"
        case .cancelled: return "Purchase cancelled"
        case .signInRequired: return "Keep your discoveries with you"
        case .unavailable: return "Purchases are unavailable"
        case .failed: return "We couldn’t finish"
        }
    }

    var statusMessage: String? {
        switch purchases.state {
        case .idle: return nil
        case .purchasing: return "Complete your purchase in the App Store."
        case .pendingApproval: return "Apple will let Bilu know when your purchase is approved."
        case .syncPending: return "Your payment will be added after verification. Retry sync to continue."
        case .purchased: return "Your purchase is verified and ready to use."
        case .restored: return "Your balance is up to date for this Bilu account."
        case .cancelled: return "You can come back whenever you’re ready."
        case .signInRequired: return "Sign in with Apple to buy or restore discoveries."
        case .unavailable: return "Try again later. Your saved places are always available."
        case .failed(let message): return message
        }
    }

    func load() async {
        await account.load()
        await purchases.retryPendingPurchases()
    }
    func purchaseDiscoveryPass() async { await purchases.purchaseDiscoveryPass() }
    func purchasePro(productID: String) async { await purchases.purchasePro(productID: productID) }
    func restore() async { await purchases.restorePurchases() }
    func retry() async { await purchases.retryPendingPurchases() }
    func acknowledgeApproval() async { await purchases.acknowledgeDeclinedOrCancelledApproval() }
}
