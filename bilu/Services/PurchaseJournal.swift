import Foundation

/// Signed StoreKit data is retained until the server acknowledges delivery.
/// A relaunch recovers the matching StoreKit transaction before finishing it.
struct PurchaseTransaction: Codable, Equatable {
    let id: String
    let productID: String
    let appAccountToken: UUID?
    let signedTransaction: String
    let purchaseDate: Date?

    init(id: String, productID: String, appAccountToken: UUID?, signedTransaction: String, purchaseDate: Date? = nil) {
        self.id = id
        self.productID = productID
        self.appAccountToken = appAccountToken
        self.signedTransaction = signedTransaction
        self.purchaseDate = purchaseDate
    }
}

struct PurchaseApproval: Codable, Equatable {
    let appAccountToken: UUID
    let productID: String
    let requestedAt: Date
}

@MainActor
protocol PurchaseJournal {
    func load() throws -> [PurchaseTransaction]
    func save(_ transactions: [PurchaseTransaction]) throws
    func loadApprovals() throws -> [PurchaseApproval]
    func saveApprovals(_ approvals: [PurchaseApproval]) throws
}

@MainActor
struct FilePurchaseJournal: PurchaseJournal {
    private struct Contents: Codable {
        var transactions: [PurchaseTransaction]
        var approvals: [PurchaseApproval]
    }
    let url: URL

    init(url: URL? = nil, configuration: SupabaseClientConfiguration = Config.supabase) {
        var directory = URL.applicationSupportDirectory.appending(path: "Commerce", directoryHint: .isDirectory)
        if configuration.isPaymentSandbox {
            directory = directory.appending(path: "Sandbox", directoryHint: .isDirectory)
                .appending(path: configuration.projectReference, directoryHint: .isDirectory)
        }
        self.url = url ?? directory.appending(path: "PendingPurchases.json")
    }

    func load() throws -> [PurchaseTransaction] {
        try contents().transactions
    }

    func save(_ transactions: [PurchaseTransaction]) throws {
        var contents = try contents()
        contents.transactions = transactions
        try write(contents)
    }

    func loadApprovals() throws -> [PurchaseApproval] { try contents().approvals }

    func saveApprovals(_ approvals: [PurchaseApproval]) throws {
        var contents = try contents()
        contents.approvals = approvals
        try write(contents)
    }

    private func contents() throws -> Contents {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Contents(transactions: [], approvals: [])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        // Preserve queues written before approval persistence was introduced.
        if let transactions = try? decoder.decode([PurchaseTransaction].self, from: data) {
            return Contents(transactions: transactions, approvals: [])
        }
        return try decoder.decode(Contents.self, from: data)
    }

    private func write(_ contents: Contents) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(contents)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
}
