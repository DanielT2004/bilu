import Foundation

/// The backend is the only authority for balances and subscription status.
struct PurchaseWallet: Codable, Equatable {
    struct Balance: Codable, Equatable {
        let explore: Int
        let tiktok: Int
    }

    let accountId: UUID
    let requiresSignIn: Bool
    let appAccountToken: UUID
    let plan: String
    let periodStart: Date
    let periodEnd: Date
    let included: Balance
    let purchased: Balance
    let commerceEnabled: Bool
    let proEnabled: Bool

    var remainingExplore: Int { max(0, included.explore) + max(0, purchased.explore) }
    var remainingTikTok: Int { max(0, included.tiktok) + max(0, purchased.tiktok) }
}

struct PurchaseProduct: Identifiable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
}

enum PurchaseState: Equatable {
    case idle
    case purchasing
    case pendingApproval
    case syncPending
    case purchased
    case restored
    case cancelled
    case signInRequired
    case unavailable
    case failed(String)
}
