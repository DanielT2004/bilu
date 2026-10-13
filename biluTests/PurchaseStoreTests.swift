import XCTest
@testable import bilu

@MainActor
final class PurchaseStoreTests: XCTestCase {
    private let account = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let otherAccount = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    func testPaymentWaitsForServerAndUsesStableAccountToken() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let journal = MemoryPurchaseJournal()
        let store = makeStore(api, storefront, journal)
        api.onVerify = { _ in
            XCTAssertEqual(journal.transactions.count, 1, "Persist before contacting the server")
            XCTAssertTrue(storefront.finished.isEmpty, "Never finish before server delivery")
            XCTAssertEqual(store.wallet?.purchased.explore, 0, "No optimistic credits")
            return self.wallet(purchasedExplore: 4, purchasedTikTok: 1)
        }

        await store.purchaseDiscoveryPass()

        XCTAssertEqual(storefront.purchaseTokens, [account])
        XCTAssertEqual(storefront.finished, ["101"])
        XCTAssertEqual(store.wallet?.purchased.explore, 4)
        XCTAssertEqual(store.state, .purchased)
        XCTAssertTrue(journal.transactions.isEmpty)
        XCTAssertFalse(store.hasPendingSync)
    }

    func testFailedDeliveryRetriesWithoutRepurchasing() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        api.verificationError = URLError(.notConnectedToInternet)
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let journal = MemoryPurchaseJournal()
        let store = makeStore(api, storefront, journal)

        await store.purchaseDiscoveryPass()
        XCTAssertEqual(store.state, .syncPending)
        XCTAssertEqual(store.wallet?.purchased.explore, 0)
        XCTAssertTrue(storefront.finished.isEmpty)
        XCTAssertEqual(journal.transactions.count, 1)
        XCTAssertFalse(store.canPurchaseDiscoveryPass)

        api.verificationError = nil
        api.snapshot = wallet(purchasedExplore: 4, purchasedTikTok: 1)
        await store.purchaseDiscoveryPass()

        XCTAssertEqual(storefront.purchaseTokens.count, 1)
        XCTAssertEqual(api.verified.count, 2)
        XCTAssertEqual(storefront.finished, ["101"])
        XCTAssertFalse(store.hasPendingSync)
    }

    func testDurableJournalRecoversPaymentAfterRelaunch() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "pending.json")
        let api = FakePurchaseAPI(snapshot: wallet())
        api.verificationError = URLError(.timedOut)
        let firstStorefront = FakePurchaseStorefront(transaction: transaction())
        let first = makeStore(api, firstStorefront, FilePurchaseJournal(url: url))
        await first.purchaseDiscoveryPass()
        XCTAssertEqual(try FilePurchaseJournal(url: url).load(), [transaction()])

        api.verificationError = nil
        api.snapshot = wallet(purchasedExplore: 4, purchasedTikTok: 1)
        let relaunchedStorefront = FakePurchaseStorefront(transaction: transaction())
        relaunchedStorefront.unfinishedEvents = [.verified(transaction())]
        let relaunched = makeStore(api, relaunchedStorefront, FilePurchaseJournal(url: url))
        await relaunched.start()

        XCTAssertEqual(relaunched.wallet?.purchased.explore, 4)
        XCTAssertEqual(relaunchedStorefront.finished, ["101"])
        XCTAssertTrue(relaunchedStorefront.purchaseTokens.isEmpty)
        XCTAssertTrue(try FilePurchaseJournal(url: url).load().isEmpty)
    }

    func testCancelledAndPendingPaymentsDoNotDeliverCredits() async {
        for outcome in [StorefrontPurchaseResult.cancelled, .pending] {
            let api = FakePurchaseAPI(snapshot: wallet())
            let storefront = FakePurchaseStorefront(transaction: transaction())
            storefront.purchaseResult = outcome
            let store = makeStore(api, storefront)
            await store.purchaseDiscoveryPass()

            XCTAssertTrue(api.verified.isEmpty)
            XCTAssertTrue(storefront.finished.isEmpty)
            XCTAssertEqual(store.wallet?.purchased.explore, 0)
            if case .pending = outcome {
                XCTAssertEqual(store.state, .pendingApproval)
                await store.purchaseDiscoveryPass()
                XCTAssertEqual(storefront.purchaseTokens.count, 1)
            } else {
                XCTAssertEqual(store.state, .cancelled)
            }
        }
    }

    func testAnonymousAccountMustSignInBeforePurchase() async {
        let api = FakePurchaseAPI(snapshot: wallet(requiresSignIn: true))
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let store = makeStore(api, storefront)

        await store.purchaseDiscoveryPass()

        XCTAssertEqual(store.state, .signInRequired)
        XCTAssertTrue(store.requiresSignIn)
        XCTAssertTrue(storefront.purchaseTokens.isEmpty)
        XCTAssertTrue(api.verified.isEmpty)
    }

    func testBothConfigurationAndServerMustEnableCommerce() async {
        for clientEnabled in [false, true] {
            let api = FakePurchaseAPI(snapshot: wallet(commerceEnabled: !clientEnabled))
            let storefront = FakePurchaseStorefront(transaction: transaction())
            let store = PurchaseStore(
                api: api, storefront: storefront, journal: MemoryPurchaseJournal(),
                configuration: PurchaseConfiguration(commerceEnabled: clientEnabled, proEnabled: false)
            )
            await store.purchaseDiscoveryPass()

            XCTAssertEqual(store.state, .unavailable)
            XCTAssertFalse(store.isCommerceAvailable)
            XCTAssertTrue(storefront.requestedProducts.isEmpty)
            XCTAssertTrue(storefront.purchaseTokens.isEmpty)
        }
    }

    func testProRequiresTheClientFlagEvenWhenTheServerOffersIt() async {
        let api = FakePurchaseAPI(snapshot: wallet(proEnabled: true))
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let store = makeStore(api, storefront)

        await store.start()

        XCTAssertEqual(storefront.requestedProducts, [[PurchaseProductID.discoveryPass]])
        XCTAssertEqual(store.discoveryPass?.displayPrice, "€5,49")
        XCTAssertEqual(store.products.count, 1)
    }

    func testProLoadsAndDeliversOnlyAfterBothProGatesOpen() async {
        let transaction = transaction(id: "202", productID: PurchaseProductID.proMonthly)
        let api = FakePurchaseAPI(snapshot: wallet(proEnabled: true))
        let storefront = FakePurchaseStorefront(transaction: transaction)
        let store = makeStore(api, storefront, proEnabled: true)
        api.onVerify = { signedTransaction in
            XCTAssertEqual(signedTransaction, "signed-202")
            return self.wallet(proEnabled: true, plan: "pro", includedExplore: 6, includedTikTok: 1)
        }

        await store.start()

        XCTAssertEqual(storefront.requestedProducts, [PurchaseProductID.all])
        XCTAssertEqual(store.proMonthly?.displayPrice, "€3,99")
        XCTAssertTrue(store.canPurchasePro(PurchaseProductID.proMonthly))

        await store.purchasePro(productID: PurchaseProductID.proMonthly)

        XCTAssertEqual(storefront.purchasedProductIDs, [PurchaseProductID.proMonthly])
        XCTAssertEqual(storefront.purchaseTokens, [account])
        XCTAssertEqual(storefront.finished, ["202"])
        XCTAssertEqual(store.wallet?.plan, "pro")
        XCTAssertEqual(store.wallet?.included.explore, 6)
        XCTAssertEqual(store.wallet?.included.tiktok, 1)
        XCTAssertFalse(store.canPurchasePro(PurchaseProductID.proAnnual))
    }

    func testActiveProDoesNotOpenAnotherSubscriptionSheet() async {
        let api = FakePurchaseAPI(snapshot: wallet(proEnabled: true, plan: "pro", includedExplore: 6, includedTikTok: 1))
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let store = makeStore(api, storefront, proEnabled: true)

        await store.start()
        await store.purchasePro(productID: PurchaseProductID.proAnnual)

        XCTAssertTrue(store.hasActivePro)
        XCTAssertEqual(storefront.requestedProducts, [[PurchaseProductID.discoveryPass]])
        XCTAssertTrue(storefront.purchaseTokens.isEmpty)
        XCTAssertEqual(store.state, PurchaseState.unavailable)
    }

    func testDifferentAccountNeverReceivesOrFinishesPendingPurchase() async {
        let api = FakePurchaseAPI(snapshot: wallet(accountID: otherAccount))
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let journal = MemoryPurchaseJournal(transactions: [transaction()])
        let store = makeStore(api, storefront, journal)

        await store.start()

        XCTAssertTrue(api.verified.isEmpty)
        XCTAssertTrue(storefront.finished.isEmpty)
        XCTAssertEqual(journal.transactions, [transaction()])
        XCTAssertFalse(store.hasPendingSync)
        XCTAssertTrue(store.hasPurchasesForAnotherAccount)
        XCTAssertTrue(store.canPurchaseDiscoveryPass)

        api.snapshot = wallet()
        await store.accountDidChange()
        XCTAssertEqual(storefront.finished, ["101"])
        XCTAssertFalse(store.hasPendingSync)
    }

    func testMixedAccountHistoryRestoresEachAccountWithoutBlockingNewPurchases() async {
        let purchaseA = transaction()
        let purchaseB = transaction(id: "202", accountID: otherAccount)
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: purchaseA)
        storefront.historyEvents = [.verified(purchaseA), .verified(purchaseB)]
        let journal = MemoryPurchaseJournal()
        let store = makeStore(api, storefront, journal)

        await store.restorePurchases()
        XCTAssertEqual(api.verified, ["signed-101"])
        XCTAssertEqual(storefront.finished, ["101"])
        XCTAssertEqual(journal.transactions, [purchaseB])
        XCTAssertEqual(store.state, .restored)
        XCTAssertFalse(store.hasPendingSync)
        XCTAssertTrue(store.hasPurchasesForAnotherAccount)
        XCTAssertTrue(store.canPurchaseDiscoveryPass)

        api.snapshot = wallet(accountID: otherAccount)
        await store.accountDidChange()
        await store.restorePurchases()
        XCTAssertEqual(journal.transactions, [purchaseA])
        XCTAssertEqual(store.state, .restored)
        XCTAssertFalse(store.hasPendingSync)
        XCTAssertTrue(store.canPurchaseDiscoveryPass)

        storefront.purchaseResult = .success(transaction(id: "303", accountID: otherAccount))
        await store.purchaseDiscoveryPass()
        XCTAssertEqual(storefront.purchaseTokens, [otherAccount])
        XCTAssertEqual(api.verified.last, "signed-303")
        XCTAssertEqual(journal.transactions, [purchaseA], "Never drop or deliver the other account's receipt")
    }

    func testPendingApprovalSurvivesRelaunchAndEmptyStoreKitHistory() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "pending.json")
        let api = FakePurchaseAPI(snapshot: wallet())
        let firstStorefront = FakePurchaseStorefront(transaction: transaction())
        firstStorefront.purchaseResult = .pending
        let first = makeStore(api, firstStorefront, FilePurchaseJournal(url: url))
        await first.purchaseDiscoveryPass()
        XCTAssertEqual(try FilePurchaseJournal(url: url).loadApprovals().count, 1)

        let secondStorefront = FakePurchaseStorefront(transaction: transaction())
        let second = makeStore(api, secondStorefront, FilePurchaseJournal(url: url))
        await second.start()
        await second.restorePurchases()
        await second.purchaseDiscoveryPass()

        XCTAssertTrue(second.hasPendingApproval)
        XCTAssertEqual(second.state, .pendingApproval)
        XCTAssertFalse(second.canPurchaseDiscoveryPass)
        XCTAssertTrue(secondStorefront.purchaseTokens.isEmpty)
        XCTAssertTrue(api.verified.isEmpty, "An empty unfinished/history sequence does not mean decline")
    }

    func testApprovalRecoveryRequiresExplicitAcknowledgementAndDoesNotPurchase() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        storefront.purchaseResult = .pending
        let journal = MemoryPurchaseJournal()
        let store = makeStore(api, storefront, journal)
        await store.purchaseDiscoveryPass()
        await store.retryPendingPurchases()
        XCTAssertTrue(store.hasPendingApproval)

        await store.acknowledgeDeclinedOrCancelledApproval()

        XCTAssertEqual(storefront.syncCount, 1)
        XCTAssertFalse(store.hasPendingApproval)
        XCTAssertTrue(journal.approvals.isEmpty)
        XCTAssertEqual(storefront.purchaseTokens.count, 1, "Acknowledging a decline must never initiate a charge")
        XCTAssertTrue(store.canPurchaseDiscoveryPass)

        storefront.purchaseResult = .success(transaction())
        await store.purchaseDiscoveryPass()
        XCTAssertEqual(storefront.purchaseTokens.count, 2, "A fresh purchase requires another explicit action")
    }

    func testOldHistoryDoesNotResolveNewApprovalButApprovedUpdateDoes() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        storefront.purchaseResult = .pending
        let journal = MemoryPurchaseJournal()
        let store = makeStore(api, storefront, journal)
        await store.start()
        await store.purchaseDiscoveryPass()
        storefront.historyEvents = [.verified(transaction(id: "old", purchaseDate: Date(timeIntervalSince1970: 1_700_000_000)))]
        await store.restorePurchases()
        XCTAssertTrue(store.hasPendingApproval)
        XCTAssertEqual(store.state, .pendingApproval)

        let delivered = expectation(description: "Approved request delivered")
        storefront.onFinish = { delivered.fulfill() }
        storefront.continuation.yield(.verified(transaction()))
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertFalse(store.hasPendingApproval)
        XCTAssertTrue(journal.approvals.isEmpty)
        XCTAssertEqual(storefront.purchaseTokens.count, 1)
    }

    func testApprovalAndReceiptsRemainScopedWhenSwitchingAccounts() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        storefront.purchaseResult = .pending
        let journal = MemoryPurchaseJournal()
        let store = makeStore(api, storefront, journal)
        await store.purchaseDiscoveryPass()

        api.snapshot = wallet(accountID: otherAccount)
        await store.accountDidChange()
        XCTAssertFalse(store.hasPendingApproval)
        XCTAssertTrue(store.hasPurchasesForAnotherAccount)
        XCTAssertTrue(store.canPurchaseDiscoveryPass)
        await store.acknowledgeDeclinedOrCancelledApproval()
        XCTAssertEqual(journal.approvals.count, 1, "Other accounts cannot clear this reminder")

        api.snapshot = wallet()
        await store.accountDidChange()
        XCTAssertTrue(store.hasPendingApproval)
        XCTAssertEqual(store.state, .pendingApproval)
        XCTAssertFalse(store.canPurchaseDiscoveryPass)
    }

    func testJournalMigratesLegacyReceiptsWithoutLosingApprovalOrTransactionData() throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "pending.json")
        try JSONEncoder().encode([transaction()]).write(to: url)
        let journal = FilePurchaseJournal(url: url)
        XCTAssertEqual(try journal.load(), [transaction()])
        XCTAssertTrue(try journal.loadApprovals().isEmpty)
        let approval = PurchaseApproval(appAccountToken: account, productID: PurchaseProductID.discoveryPass, requestedAt: Date())
        try journal.saveApprovals([approval])
        XCTAssertEqual(try journal.load(), [transaction()])
        try journal.save([])
        XCTAssertEqual(try journal.loadApprovals(), [approval])
    }

    func testMismatchedServerAcknowledgementDoesNotFinish() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        api.onVerify = { _ in self.wallet(accountID: self.otherAccount) }
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let store = makeStore(api, storefront)

        await store.purchaseDiscoveryPass()

        XCTAssertEqual(store.wallet?.accountId, account)
        XCTAssertTrue(storefront.finished.isEmpty)
        XCTAssertTrue(store.hasPendingSync)
    }

    func testAccountChangeDuringVerificationCannotFinishOrOverwriteNewWallet() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let store = makeStore(api, storefront)
        let verificationStarted = expectation(description: "Verification started")
        let newWalletLoaded = expectation(description: "New account loaded")
        var verificationContinuation: CheckedContinuation<PurchaseWallet, Never>?
        api.onVerify = { _ in
            await withCheckedContinuation { continuation in
                verificationContinuation = continuation
                verificationStarted.fulfill()
            }
        }
        let purchase = Task { await store.purchaseDiscoveryPass() }
        await fulfillment(of: [verificationStarted], timeout: 2)

        api.snapshot = wallet(accountID: otherAccount)
        api.onWallet = { newWalletLoaded.fulfill() }
        let switching = Task { await store.accountDidChange() }
        await fulfillment(of: [newWalletLoaded], timeout: 2)
        verificationContinuation?.resume(returning: wallet(purchasedExplore: 4))
        await purchase.value
        await switching.value

        XCTAssertEqual(store.wallet?.accountId, otherAccount)
        XCTAssertTrue(storefront.finished.isEmpty)
        XCTAssertFalse(store.hasPendingSync)
        XCTAssertTrue(store.hasPurchasesForAnotherAccount)
    }

    func testJournalFailureLeavesStoreKitTransactionUnfinished() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let journal = MemoryPurchaseJournal()
        journal.shouldFail = true
        let store = makeStore(api, storefront, journal)

        await store.purchaseDiscoveryPass()

        XCTAssertTrue(api.verified.isEmpty)
        XCTAssertTrue(storefront.finished.isEmpty)
        XCTAssertEqual(store.state, .syncPending)
        XCTAssertTrue(storefront.purchaseTokens.isEmpty, "Durable recovery must be writable before opening payment")

        journal.shouldFail = false
        await store.retryPendingPurchases()
        XCTAssertFalse(store.hasPendingApproval)
        await store.purchaseDiscoveryPass()
        XCTAssertEqual(storefront.finished, ["101"])
        XCTAssertEqual(storefront.purchaseTokens.count, 1)
    }

    func testRestoreReconcilesHistoryAndRefetchesWallet() async {
        let api = FakePurchaseAPI(snapshot: wallet(purchasedExplore: 3))
        let storefront = FakePurchaseStorefront(transaction: transaction())
        storefront.historyEvents = [.verified(transaction())]
        let store = makeStore(api, storefront)

        await store.restorePurchases()

        XCTAssertEqual(storefront.syncCount, 1)
        XCTAssertEqual(api.walletCount, 2)
        XCTAssertEqual(api.verified, ["signed-101"])
        XCTAssertEqual(storefront.finished, ["101"])
        XCTAssertEqual(store.wallet?.purchased.explore, 3)
        XCTAssertEqual(store.state, .restored)
    }

    func testRestoreDoesNotClaimSuccessForUnverifiedHistory() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        storefront.historyEvents = [.unverified]
        let store = makeStore(api, storefront)

        await store.restorePurchases()

        XCTAssertTrue(api.verified.isEmpty)
        XCTAssertTrue(storefront.finished.isEmpty)
        guard case .failed = store.state else { return XCTFail("Unverified restore cannot succeed") }
    }

    func testListenerReconcilesApprovedPaymentAndRejectsUnverifiedEvent() async {
        let api = FakePurchaseAPI(snapshot: wallet())
        let storefront = FakePurchaseStorefront(transaction: transaction())
        let store = makeStore(api, storefront)
        await store.start()
        let delivered = expectation(description: "Approved purchase delivered")
        storefront.onFinish = { delivered.fulfill() }
        storefront.continuation.yield(.verified(transaction()))
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(api.verified, ["signed-101"])

        storefront.continuation.yield(.unverified)
        // Yield back to the listener without a timing-dependent sleep.
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(api.verified.count, 1)
        XCTAssertEqual(storefront.finished.count, 1)
        guard case .failed = store.state else { return XCTFail("Expected verification error") }
    }

    func testWalletDecoderAcceptsCanonicalFractionalAndWholeSecondDates() throws {
        let data = Data("""
        {"accountId":"\(account.uuidString)","appAccountToken":"\(account.uuidString)",
         "requiresSignIn":false,"plan":"free","periodStart":"2026-10-01T00:00:00.000Z",
         "periodEnd":"2026-11-01T00:00:00Z","included":{"explore":5,"tiktok":1},
         "purchased":{"explore":4,"tiktok":1},"commerceEnabled":true,"proEnabled":false}
        """.utf8)
        let snapshot = try PurchaseAPI.decoder().decode(PurchaseWallet.self, from: data)
        XCTAssertEqual(snapshot.accountId, account)
        XCTAssertEqual(snapshot.remainingExplore, 9)
        XCTAssertEqual(snapshot.remainingTikTok, 2)
        XCTAssertGreaterThan(snapshot.periodEnd, snapshot.periodStart)
    }

    private func wallet(
        accountID: UUID? = nil, requiresSignIn: Bool = false,
        purchasedExplore: Int = 0, purchasedTikTok: Int = 0,
        commerceEnabled: Bool = true, proEnabled: Bool = false,
        plan: String = "free", includedExplore: Int = 5, includedTikTok: Int = 1
    ) -> PurchaseWallet {
        PurchaseWallet(
            accountId: accountID ?? account, requiresSignIn: requiresSignIn,
            appAccountToken: accountID ?? account, plan: plan,
            periodStart: Date(timeIntervalSince1970: 1_790_812_800),
            periodEnd: Date(timeIntervalSince1970: 1_793_491_200),
            included: .init(explore: includedExplore, tiktok: includedTikTok),
            purchased: .init(explore: purchasedExplore, tiktok: purchasedTikTok),
            commerceEnabled: commerceEnabled, proEnabled: proEnabled
        )
    }

    private func transaction(id: String = "101", accountID: UUID? = nil,
                             productID: String = "com.simonsoloman.bilu.discovery_pass",
                             purchaseDate: Date = Date(timeIntervalSince1970: 1_800_000_001)) -> PurchaseTransaction {
        PurchaseTransaction(id: id, productID: productID,
                            appAccountToken: accountID ?? account, signedTransaction: "signed-\(id)", purchaseDate: purchaseDate)
    }

    private func makeStore(
        _ api: FakePurchaseAPI, _ storefront: FakePurchaseStorefront,
        _ journal: (any PurchaseJournal)? = nil, proEnabled: Bool = false
    ) -> PurchaseStore {
        PurchaseStore(
            api: api, storefront: storefront, journal: journal ?? MemoryPurchaseJournal(),
            configuration: PurchaseConfiguration(commerceEnabled: true, proEnabled: proEnabled),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}

@MainActor
private final class FakePurchaseAPI: PurchaseAPIClient {
    var snapshot: PurchaseWallet
    var verificationError: Error?
    var verified: [String] = []
    var walletCount = 0
    var onWallet: (() -> Void)?
    var onVerify: ((String) async throws -> PurchaseWallet)?

    init(snapshot: PurchaseWallet) { self.snapshot = snapshot }
    func wallet() async throws -> PurchaseWallet { walletCount += 1; onWallet?(); return snapshot }
    func verify(signedTransaction: String) async throws -> PurchaseWallet {
        verified.append(signedTransaction)
        if let verificationError { throw verificationError }
        return try await onVerify?(signedTransaction) ?? snapshot
    }
}

@MainActor
private final class FakePurchaseStorefront: PurchaseStorefront {
    var purchaseResult: StorefrontPurchaseResult
    var requestedProducts: [Set<String>] = []
    var purchaseTokens: [UUID] = []
    var purchasedProductIDs: [String] = []
    var finished: [String] = []
    var unfinishedEvents: [PurchaseTransactionEvent] = []
    var historyEvents: [PurchaseTransactionEvent] = []
    var syncCount = 0
    var onFinish: (() -> Void)?
    let stream: AsyncStream<PurchaseTransactionEvent>
    let continuation: AsyncStream<PurchaseTransactionEvent>.Continuation

    init(transaction: PurchaseTransaction) {
        purchaseResult = .success(transaction)
        (stream, continuation) = AsyncStream.makeStream()
    }
    func products(for identifiers: Set<String>) async throws -> [PurchaseProduct] {
        requestedProducts.append(identifiers)
        return identifiers.sorted().compactMap { productID in
            switch productID {
            case PurchaseProductID.discoveryPass:
                return PurchaseProduct(id: productID, displayName: "Discovery Pass", description: "4 Explore + 1 TikTok", displayPrice: "€5,49")
            case PurchaseProductID.proMonthly:
                return PurchaseProduct(id: productID, displayName: "Bilu Pro Monthly", description: "6 Explore + 1 TikTok each month", displayPrice: "€3,99")
            case PurchaseProductID.proAnnual:
                return PurchaseProduct(id: productID, displayName: "Bilu Pro Annual", description: "6 Explore + 1 TikTok each month", displayPrice: "€34,99")
            default:
                return nil
            }
        }
    }
    func purchase(productID: String, appAccountToken: UUID) async throws -> StorefrontPurchaseResult {
        purchasedProductIDs.append(productID)
        purchaseTokens.append(appAccountToken)
        return purchaseResult
    }
    func updates() -> AsyncStream<PurchaseTransactionEvent> { stream }
    func unfinished() async -> [PurchaseTransactionEvent] { unfinishedEvents }
    func history() async -> [PurchaseTransactionEvent] { historyEvents }
    func sync() async throws { syncCount += 1 }
    func finish(transactionID: String) async { finished.append(transactionID); onFinish?() }
}

@MainActor
private final class MemoryPurchaseJournal: PurchaseJournal {
    var transactions: [PurchaseTransaction]
    var approvals: [PurchaseApproval] = []
    var shouldFail = false
    init(transactions: [PurchaseTransaction] = []) { self.transactions = transactions }
    func load() throws -> [PurchaseTransaction] { transactions }
    func loadApprovals() throws -> [PurchaseApproval] { approvals }
    func saveApprovals(_ approvals: [PurchaseApproval]) throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        self.approvals = approvals
    }
    func save(_ transactions: [PurchaseTransaction]) throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        self.transactions = transactions
    }
}
