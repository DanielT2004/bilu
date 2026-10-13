import Foundation
import StoreKit

enum PurchaseTransactionEvent {
    case verified(PurchaseTransaction)
    case unverified
}

enum StorefrontPurchaseResult {
    case success(PurchaseTransaction)
    case pending
    case cancelled
}

enum PurchaseStorefrontError: Error {
    case unavailable
    case unverified
}

@MainActor
protocol PurchaseStorefront {
    func products(for identifiers: Set<String>) async throws -> [PurchaseProduct]
    func purchase(productID: String, appAccountToken: UUID) async throws -> StorefrontPurchaseResult
    func updates() -> AsyncStream<PurchaseTransactionEvent>
    func unfinished() async -> [PurchaseTransactionEvent]
    func history() async -> [PurchaseTransactionEvent]
    func sync() async throws
    func finish(transactionID: String) async
}

@MainActor
final class ApplePurchaseStorefront: PurchaseStorefront {
    private var loadedProducts: [String: Product] = [:]
    private var transactions: [String: StoreKit.Transaction] = [:]

    func products(for identifiers: Set<String>) async throws -> [PurchaseProduct] {
        let products = try await Product.products(for: identifiers)
        for product in products { loadedProducts[product.id] = product }
        return products.map {
            PurchaseProduct(id: $0.id, displayName: $0.displayName, description: $0.description, displayPrice: $0.displayPrice)
        }
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> StorefrontPurchaseResult {
        guard let product = loadedProducts[productID] else { throw PurchaseStorefrontError.unavailable }
        switch try await product.purchase(options: [.appAccountToken(appAccountToken)]) {
        case .success(let result):
            guard case .verified(let transaction) = event(result) else { throw PurchaseStorefrontError.unverified }
            return .success(transaction)
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: throw PurchaseStorefrontError.unavailable
        }
    }

    func updates() -> AsyncStream<PurchaseTransactionEvent> {
        AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                for await result in StoreKit.Transaction.updates {
                    guard !Task.isCancelled, let self else { break }
                    continuation.yield(self.event(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func unfinished() async -> [PurchaseTransactionEvent] {
        var results: [PurchaseTransactionEvent] = []
        for await result in StoreKit.Transaction.unfinished { results.append(event(result)) }
        return results
    }

    func history() async -> [PurchaseTransactionEvent] {
        var results: [PurchaseTransactionEvent] = []
        // Finished consumables are included on supported OS versions when the
        // app enables SKIncludeConsumableInAppPurchaseHistory in Info.plist.
        for await result in StoreKit.Transaction.all { results.append(event(result)) }
        return results
    }

    func sync() async throws { try await AppStore.sync() }

    func finish(transactionID: String) async {
        guard let transaction = transactions[transactionID] else { return }
        await transaction.finish()
        transactions.removeValue(forKey: transactionID)
    }

    private func event(_ result: VerificationResult<StoreKit.Transaction>) -> PurchaseTransactionEvent {
        guard case .verified(let transaction) = result else { return .unverified }
        guard PurchaseProductID.all.contains(transaction.productID) else { return .unverified }
        let id = String(transaction.id)
        transactions[id] = transaction
        return .verified(PurchaseTransaction(
            id: id,
            productID: transaction.productID,
            appAccountToken: transaction.appAccountToken,
            signedTransaction: result.jwsRepresentation,
            purchaseDate: transaction.purchaseDate
        ))
    }
}
