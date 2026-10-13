import Combine
import Foundation

/// Coordinates StoreKit delivery with the authoritative server wallet. A
/// successful App Store payment alone never changes a discovery balance.
@MainActor
final class PurchaseStore: ObservableObject {
    static let shared = PurchaseStore()

    @Published private(set) var wallet: PurchaseWallet?
    @Published private(set) var products: [PurchaseProduct] = []
    @Published private(set) var state: PurchaseState = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var hasPendingSync = false
    @Published private(set) var hasPendingApproval = false
    @Published private(set) var hasPurchasesForAnotherAccount = false

    let configuration: PurchaseConfiguration
    private let api: any PurchaseAPIClient
    private let storefront: any PurchaseStorefront
    private let journal: any PurchaseJournal
    private let now: () -> Date
    private var pending: [PurchaseTransaction] = []
    private var approvals: [PurchaseApproval] = []
    private var journalNeedsRecovery = false
    private var approvalJournalNeedsRecovery = false
    private var accountGeneration = UUID()
    private var listener: Task<Void, Never>?
    private var synchronizationTask: Task<Void, Never>?
    private var synchronizationGeneration: UUID?

    init(
        api: (any PurchaseAPIClient)? = nil,
        storefront: (any PurchaseStorefront)? = nil,
        journal: (any PurchaseJournal)? = nil,
        configuration: PurchaseConfiguration? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.api = api ?? PurchaseAPI()
        self.storefront = storefront ?? ApplePurchaseStorefront()
        self.journal = journal ?? FilePurchaseJournal()
        self.configuration = configuration ?? .current
        self.now = now
        do {
            pending = try self.journal.load()
            approvals = try self.journal.loadApprovals()
            hasPendingSync = !pending.isEmpty
        } catch {
            journalNeedsRecovery = true
            hasPendingSync = true
        }
        if hasPendingSync { state = .syncPending }
    }

    deinit { listener?.cancel() }

    var isCommerceAvailable: Bool { configuration.commerceEnabled && wallet?.commerceEnabled == true }
    var requiresSignIn: Bool { wallet?.requiresSignIn ?? true }
    var discoveryPass: PurchaseProduct? { products.first { $0.id == PurchaseProductID.discoveryPass } }
    var proMonthly: PurchaseProduct? { products.first { $0.id == PurchaseProductID.proMonthly } }
    var proAnnual: PurchaseProduct? { products.first { $0.id == PurchaseProductID.proAnnual } }
    var hasActivePro: Bool { wallet?.plan == "pro" }
    var isProAvailable: Bool {
        isCommerceAvailable && configuration.proEnabled && wallet?.proEnabled == true
    }
    var canPurchaseDiscoveryPass: Bool {
        isCommerceAvailable && !requiresSignIn && discoveryPass != nil && !isLoading
            && !hasPendingSync && !hasPendingApproval
    }
    func canPurchasePro(_ productID: String) -> Bool {
        guard productID == PurchaseProductID.proMonthly || productID == PurchaseProductID.proAnnual else { return false }
        return isProAvailable && !hasActivePro && !requiresSignIn
            && products.contains(where: { $0.id == productID }) && !isLoading
            && !hasPendingSync && !hasPendingApproval
    }

    /// Start at app launch, including when offers are disabled, so prior
    /// purchases can still be delivered after an operational kill switch.
    func start() async {
        startListening()
        await retryPendingPurchases()
    }

    func refreshWallet() async {
        let generation = accountGeneration
        do {
            let snapshot = try await api.wallet()
            guard generation == accountGeneration else { return }
            wallet = snapshot
            updatePendingFlags()
            if hasPendingApproval && !hasPendingSync { state = .pendingApproval }
            else if state == .pendingApproval { state = .idle }
        } catch {
            guard generation == accountGeneration else { return }
            // A stale wallet must not admit a new purchase after refresh fails.
            wallet = nil
            updatePendingFlags()
            present(error)
        }
    }

    func purchaseDiscoveryPass() async {
        await purchase(productID: PurchaseProductID.discoveryPass)
    }

    /// Starts an auto-renewable Pro subscription. The server, not the client,
    /// decides whether the signed transaction creates an active entitlement.
    func purchasePro(productID: String) async {
        guard productID == PurchaseProductID.proMonthly || productID == PurchaseProductID.proAnnual else { return }
        await purchase(productID: productID)
    }

    private func purchase(productID: String) async {
        guard !isLoading else { return }
        // A retry after payment resumes delivery; it never charges again.
        if hasPendingSync {
            await retryPendingPurchases()
            return
        }
        guard !hasPendingApproval else { state = .pendingApproval; return }
        isLoading = true
        defer { isLoading = false }
        let generation = accountGeneration
        await refreshWallet()
        guard generation == accountGeneration else { return }
        guard let snapshot = wallet else { return }
        if hasPendingSync { await synchronizePending(); return }
        guard !hasPendingApproval else { state = .pendingApproval; return }
        guard !snapshot.requiresSignIn else { state = .signInRequired; return }
        guard isCommerceAvailable else { state = .unavailable; return }
        guard isOfferAvailable(productID, wallet: snapshot) else { state = .unavailable; return }
        if products.first(where: { $0.id == productID }) == nil { await loadProducts() }
        guard generation == accountGeneration,
              products.contains(where: { $0.id == productID }) else { return }
        if hasPendingSync { await synchronizePending(); return }
        guard !hasPendingApproval else { state = .pendingApproval; return }
        // Persist before opening Apple's sheet so an interrupted process cannot
        // forget that a purchase may still require external approval.
        let approval = PurchaseApproval(
            appAccountToken: snapshot.appAccountToken,
            productID: productID, requestedAt: now()
        )
        approvals.append(approval)
        guard persistApprovals() else {
            approvals.removeAll { $0 == approval }
            updatePendingFlags()
            return
        }
        state = .purchasing
        do {
            let result = try await storefront.purchase(
                productID: productID,
                appAccountToken: snapshot.appAccountToken
            )
            switch result {
            case .success(let transaction):
                record(transaction, completingApproval: approval)
                await synchronizePending()
            case .pending:
                if generation == accountGeneration { state = .pendingApproval }
            case .cancelled:
                approvals.removeAll { $0 == approval }
                guard persistApprovals() else { return }
                if generation == accountGeneration { state = .cancelled }
            }
        } catch {
            approvals.removeAll { $0 == approval }
            guard persistApprovals() else { return }
            guard generation == accountGeneration else { return }
            present(error)
        }
    }

    func retryPendingPurchases() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        startListening()
        let generation = accountGeneration
        await refreshWallet()
        await collect(await storefront.unfinished())
        guard generation == accountGeneration else { return }
        await synchronizePending()
        guard generation == accountGeneration else { return }
        await loadProducts()
    }

    /// Explicit user action: AppStore.sync may present an authentication sheet.
    /// Consumable balances are restored from Bilu's account ledger, while
    /// available App Store history reconciles missed/refunded transactions.
    func restorePurchases() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        startListening()
        let generation = accountGeneration
        do {
            try await storefront.sync()
            await refreshWallet()
            let unfinishedVerified = await collect(await storefront.unfinished())
            let historyVerified = await collect(await storefront.history())
            guard generation == accountGeneration else { return }
            await synchronizePending()
            guard generation == accountGeneration else { return }
            await refreshWallet()
            if !unfinishedVerified || !historyVerified {
                state = .failed("Some App Store purchases could not be verified. Try Restore Purchases again.")
            } else if wallet != nil && !hasPendingSync {
                state = hasPendingApproval ? .pendingApproval : .restored
            }
            await loadProducts()
        } catch {
            guard generation == accountGeneration else { return }
            present(error)
        }
    }

    /// Call immediately after auth changes. Pending receipts keep their
    /// original account token and cannot be delivered to the next account.
    func accountDidChange() async {
        accountGeneration = UUID()
        wallet = nil
        updatePendingFlags()
        products = []
        state = hasPendingSync ? .syncPending : .idle
        await refreshWallet()
        await collect(await storefront.unfinished())
        await synchronizePending()
        await loadProducts()
    }

    func resetPresentationState() {
        guard !isLoading, !hasPendingSync, !hasPendingApproval else { return }
        state = .idle
    }

    /// Only call after the user explicitly confirms the original request was
    /// declined/cancelled. StoreKit does not report declined Ask to Buy requests.
    /// This clears a local reminder, never cancels Apple or starts a new charge.
    func acknowledgeDeclinedOrCancelledApproval() async {
        guard !isLoading, hasPendingApproval, let originalWallet = wallet,
              let approvalToClear = approvals.first(where: {
                  $0.appAccountToken == originalWallet.appAccountToken
              }) else { return }
        isLoading = true
        defer { isLoading = false }
        let generation = accountGeneration
        do {
            try await storefront.sync()
            let snapshot = try await api.wallet()
            guard generation == accountGeneration, snapshot.accountId == originalWallet.accountId,
                  snapshot.appAccountToken == originalWallet.appAccountToken,
                  !snapshot.requiresSignIn else { return }
            wallet = snapshot
            updatePendingFlags()
            let unfinishedVerified = await collect(await storefront.unfinished())
            let historyVerified = await collect(await storefront.history())
            guard generation == accountGeneration else { return }
            await synchronizePending()
            guard generation == accountGeneration else { return }
            guard unfinishedVerified, historyVerified else {
                state = .failed("Some App Store purchases could not be verified. Check purchases again before clearing the reminder.")
                return
            }
            guard !hasPendingSync else { return }
            // Clear only the request the person confirmed. Multiple Ask to Buy
            // requests can exist for a single account and should remain visible.
            approvals.removeAll { $0 == approvalToClear }
            guard persistApprovals() else { return }
            state = .idle
        } catch {
            guard generation == accountGeneration else { return }
            present(error)
        }
    }

    private func startListening() {
        guard listener == nil else { return }
        let updates = storefront.updates()
        listener = Task { @MainActor [weak self] in
            for await event in updates {
                guard !Task.isCancelled, let self else { return }
                switch event {
                case .verified(let transaction):
                    self.record(transaction)
                    if self.wallet == nil { await self.refreshWallet() }
                    await self.synchronizePending()
                case .unverified:
                    self.state = .failed("The App Store purchase could not be verified. Try Restore Purchases.")
                }
            }
        }
    }

    /// A Pro offer needs all three rollout gates: local app configuration,
    /// the authoritative wallet response, and a free (non-entitled) account.
    /// Existing Pro members manage renewal in the App Store instead of opening a
    /// second StoreKit purchase sheet from Bilu.
    private func isOfferAvailable(_ productID: String, wallet snapshot: PurchaseWallet) -> Bool {
        switch productID {
        case PurchaseProductID.discoveryPass:
            return snapshot.commerceEnabled
        case PurchaseProductID.proMonthly, PurchaseProductID.proAnnual:
            return configuration.proEnabled && snapshot.proEnabled && snapshot.plan != "pro"
        default:
            return false
        }
    }

    private func loadProducts() async {
        guard isCommerceAvailable else { products = []; return }
        let generation = accountGeneration
        var identifiers: Set<String> = [PurchaseProductID.discoveryPass]
        if let wallet, isOfferAvailable(PurchaseProductID.proMonthly, wallet: wallet) {
            identifiers.formUnion([PurchaseProductID.proMonthly, PurchaseProductID.proAnnual])
        }
        do {
            let loaded = try await storefront.products(for: identifiers)
            guard generation == accountGeneration else { return }
            products = loaded.filter { identifiers.contains($0.id) }
            if products.isEmpty && !hasPendingSync { state = .unavailable }
        } catch {
            guard generation == accountGeneration else { return }
            products = []
            if !hasPendingSync { present(error) }
        }
    }

    @discardableResult
    private func collect(_ events: [PurchaseTransactionEvent]) async -> Bool {
        var allVerified = true
        for event in events {
            switch event {
            case .verified(let transaction): record(transaction)
            case .unverified: allVerified = false
            }
        }
        return allVerified
    }

    private func record(_ transaction: PurchaseTransaction, completingApproval: PurchaseApproval? = nil) {
        guard PurchaseProductID.all.contains(transaction.productID) else { return }
        if let index = pending.firstIndex(where: { $0.id == transaction.id }) {
            // A newer signed representation may report a refund/revocation.
            pending[index] = transaction
        } else {
            pending.append(transaction)
        }
        guard persistPending() else { return }
        approvals.removeAll { approval in
            guard approval.appAccountToken == transaction.appAccountToken,
                  approval.productID == transaction.productID else { return false }
            // Old purchase history/refunds must not clear a newer approval.
            return approval == completingApproval || transaction.purchaseDate.map { $0 >= approval.requestedAt } == true
        }
        guard persistApprovals() else { return }
        if hasPendingSync { state = .syncPending }
    }

    @discardableResult
    private func persistPending() -> Bool {
        do {
            try journal.save(pending)
            journalNeedsRecovery = false
            updatePendingFlags()
            return true
        } catch {
            journalNeedsRecovery = true
            updatePendingFlags()
            state = .syncPending
            return false
        }
    }

    @discardableResult
    private func persistApprovals() -> Bool {
        do {
            try journal.saveApprovals(approvals)
            approvalJournalNeedsRecovery = false
            updatePendingFlags()
            return true
        } catch {
            approvalJournalNeedsRecovery = true
            updatePendingFlags()
            state = .syncPending
            return false
        }
    }

    private func updatePendingFlags() {
        let token = wallet?.appAccountToken
        hasPendingSync = journalNeedsRecovery || approvalJournalNeedsRecovery || pending.contains {
            token == nil || $0.appAccountToken == token
        }
        hasPendingApproval = approvals.contains { $0.appAccountToken == token }
        hasPurchasesForAnotherAccount = token != nil && (pending.contains { $0.appAccountToken != token }
            || approvals.contains { $0.appAccountToken != token })
    }

    private func synchronizePending() async {
        if let synchronizationTask {
            let isPreviousAccount = synchronizationGeneration != accountGeneration
            await synchronizationTask.value
            if isPreviousAccount { await synchronizePending() }
            return
        }
        synchronizationGeneration = accountGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.drainPending()
            self.synchronizationTask = nil
        }
        synchronizationTask = task
        await task.value
    }

    private func drainPending() async {
        if approvalJournalNeedsRecovery && !persistApprovals() { return }
        guard !pending.isEmpty || journalNeedsRecovery else {
            if state == .syncPending { state = hasPendingApproval ? .pendingApproval : .idle }
            return
        }
        guard persistPending() else { return }
        guard !pending.isEmpty else { state = hasPendingApproval ? .pendingApproval : .idle; return }
        guard let snapshot = wallet else { state = .syncPending; return }
        guard !snapshot.requiresSignIn else { state = .signInRequired; return }
        guard pending.contains(where: { $0.appAccountToken == snapshot.appAccountToken }) else {
            if state == .syncPending { state = hasPendingApproval ? .pendingApproval : .idle }
            return
        }
        let generation = accountGeneration
        var attempted: Set<String> = []
        while let transaction = pending.first(where: {
            $0.appAccountToken == snapshot.appAccountToken && !attempted.contains($0.id)
        }) {
            attempted.insert(transaction.id)
            guard generation == accountGeneration else { return }
            do {
                let confirmed = try await api.verify(signedTransaction: transaction.signedTransaction)
                guard generation == accountGeneration else { return }
                guard confirmed.accountId == snapshot.accountId,
                      confirmed.appAccountToken == snapshot.appAccountToken,
                      !confirmed.requiresSignIn else { throw PurchaseAPIError.accountMismatch }
                wallet = confirmed
                // Delivery is committed on the server before StoreKit finish.
                await storefront.finish(transactionID: transaction.id)
                guard generation == accountGeneration else { return }
                // Keep a concurrently received refund representation for a
                // subsequent server reconciliation instead of dropping it.
                pending.removeAll { $0 == transaction }
                guard persistPending() else { return }
                if !hasPendingSync { state = hasPendingApproval ? .pendingApproval : .purchased }
            } catch {
                guard generation == accountGeneration else { return }
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        switch error {
        case PurchaseAPIError.signInRequired:
            state = .signInRequired
        case PurchaseAPIError.accountMismatch:
            state = .failed("This purchase belongs to another Bilu account. Sign in with the account used to buy it, then restore purchases.")
        case PurchaseAPIError.invalidTransaction, PurchaseStorefrontError.unverified:
            state = .failed("The App Store purchase could not be verified. Try Restore Purchases.")
        case PurchaseAPIError.unavailable, PurchaseStorefrontError.unavailable:
            state = hasPendingSync ? .syncPending : .unavailable
        default:
            state = hasPendingSync ? .syncPending : .failed("Purchases couldn’t connect. Check your connection and try again.")
        }
    }
}
