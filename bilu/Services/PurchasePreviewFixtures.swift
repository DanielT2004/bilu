#if DEBUG
import Foundation

/// Debug-only, dependency-injected screen fixtures. These never use Supabase,
/// StoreKit, the device Keychain, or the durable purchase journal.
@MainActor
final class PurchasePreviewFixtures {
    static let current: PurchasePreviewFixtures? = {
        let arguments = ProcessInfo.processInfo.arguments
        let state: String?
        if let flag = arguments.firstIndex(of: "-BILUPurchasePreview"), arguments.indices.contains(flag + 1) {
            state = arguments[flag + 1]
        } else {
            state = UserDefaults.standard.string(forKey: "BILUPurchasePreview")
        }
        guard let state, ["signed-out", "ready", "unavailable", "pending", "pending-sync", "restored", "error"].contains(state) else { return nil }
        return PurchasePreviewFixtures(state: state)
    }()

    let purchases: PurchaseStore
    let account: AccountViewModel
    private let state: String

    private init(state: String) {
        self.state = state
        let id = UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID()
        let isGuest = state == "signed-out"
        let wallet = PurchaseWallet(
            accountId: id, requiresSignIn: isGuest, appAccountToken: id, plan: "free",
            periodStart: Date(), periodEnd: Date().addingTimeInterval(30 * 86400),
            included: .init(explore: 0, tiktok: 0), purchased: .init(explore: state == "restored" ? 4 : 0, tiktok: state == "restored" ? 1 : 0),
            commerceEnabled: state != "unavailable", proEnabled: false
        )
        let journal = PreviewPurchaseJournal()
        if state == "pending-sync" {
            journal.transactions = [.init(id: "preview-only", productID: PurchaseProductID.discoveryPass, appAccountToken: id, signedTransaction: "preview-never-transmitted")]
        }
        purchases = PurchaseStore(
            api: PreviewPurchaseAPI(snapshot: wallet, fails: state == "error"),
            storefront: PreviewPurchaseStorefront(), journal: journal,
            configuration: PurchaseConfiguration(commerceEnabled: true, proEnabled: false)
        )
        account = AccountViewModel(service: PreviewAccountService(user: BiluAccount(id: id, isAnonymous: isGuest, email: nil)), purchases: purchases)
    }

    func prepare() async {
        await purchases.retryPendingPurchases()
        if state == "pending" { await purchases.purchaseDiscoveryPass() }
        if state == "restored" { await purchases.restorePurchases() }
    }
}

@MainActor private final class PreviewPurchaseAPI: PurchaseAPIClient {
    let snapshot: PurchaseWallet
    let fails: Bool
    init(snapshot: PurchaseWallet, fails: Bool) { self.snapshot = snapshot; self.fails = fails }
    func wallet() async throws -> PurchaseWallet {
        if fails { throw PurchaseAPIError.serviceUnavailable }
        return snapshot
    }
    func verify(signedTransaction: String) async throws -> PurchaseWallet { throw PurchaseAPIError.serviceUnavailable }
}

@MainActor private final class PreviewPurchaseStorefront: PurchaseStorefront {
    func products(for identifiers: Set<String>) async throws -> [PurchaseProduct] {
        [PurchaseProduct(id: PurchaseProductID.discoveryPass, displayName: "Discovery Pass", description: "4 Explore + 1 TikTok", displayPrice: "$4.99")]
    }
    func purchase(productID: String, appAccountToken: UUID) async throws -> StorefrontPurchaseResult { .pending }
    func updates() -> AsyncStream<PurchaseTransactionEvent> { AsyncStream { $0.finish() } }
    func unfinished() async -> [PurchaseTransactionEvent] { [] }
    func history() async -> [PurchaseTransactionEvent] { [] }
    func sync() async throws {}
    func finish(transactionID: String) async {}
}

@MainActor private final class PreviewPurchaseJournal: PurchaseJournal {
    var transactions: [PurchaseTransaction] = []
    var approvals: [PurchaseApproval] = []
    func loadApprovals() throws -> [PurchaseApproval] { approvals }
    func saveApprovals(_ approvals: [PurchaseApproval]) throws { self.approvals = approvals }
    func load() throws -> [PurchaseTransaction] { transactions }
    func save(_ transactions: [PurchaseTransaction]) throws { self.transactions = transactions }
}

nonisolated private struct PreviewAccountService: AccountServicing {
    let user: BiluAccount
    func account() async throws -> BiluAccount { user }
    func cachedAccount() async -> BiluAccount? { user }
    func signIn(idToken: String, nonce: String, requireAccount: UUID?, linkGuest: Bool) async throws -> BiluAccount { throw SupabaseAuthError.invalidResponse }
    func signOut() async throws {}
    func deleteAccount(_ accountID: UUID, authorizationCode: String) async throws { throw SupabaseAuthError.invalidResponse }
}
#endif
