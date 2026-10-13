import CryptoKit
import Foundation

enum DiscoveryJobError: Error, Equatable {
    case allowanceRequired
    case pending
    case missingCity
    case unavailable
    case failed
}

/// A request ID survives a lost response. Retrying that request recovers its
/// server result instead of purchasing another provider execution.
@MainActor
final class DiscoveryJobService {
    static let shared = DiscoveryJobService()

    struct TikTokResult: Decodable {
        let videos: [TikTokVideo]
        let locations: [SearchLocation]
        let unresolved: [String]
    }

    private struct Response<Result: Decodable>: Decodable {
        let status: String?
        let result: Result?
        let code: String?
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let requestFactory: (String, TimeInterval) async throws -> URLRequest
    private let walletDidChange: () async -> Void
    private var runningKeys = Set<String>()

    init(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared,
        requestFactory: @escaping (String, TimeInterval) async throws -> URLRequest = {
            try await AuthenticatedAPIRequest.post(path: $0, timeout: $1)
        },
        walletDidChange: @escaping () async -> Void = { await PurchaseStore.shared.refreshWallet() }
    ) {
        self.defaults = defaults
        self.session = session
        self.requestFactory = requestFactory
        self.walletDidChange = walletDidChange
    }

    func explore(input: [String: Any]) async throws -> VibeResult {
        try await run(kind: "explore", input: input)
    }

    func tiktok(query: String, sortType: Int) async throws -> TikTokResult {
        try await run(kind: "tiktok", input: ["query": query, "sortType": sortType])
    }

    private func run<Result: Decodable>(kind: String, input: [String: Any]) async throws -> Result {
        // Fetch identity authoritatively before selecting the account-scoped job.
        var walletRequest = try await requestFactory("purchase-wallet", 20)
        walletRequest.httpBody = Data("{}".utf8)
        let (walletData, walletResponse) = try await session.data(for: walletRequest)
        guard let httpWallet = walletResponse as? HTTPURLResponse,
              (200...299).contains(httpWallet.statusCode) else { throw DiscoveryJobError.unavailable }
        let wallet = try PurchaseAPI.decoder().decode(PurchaseWallet.self, from: walletData)
        let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])
        let digest = SHA256.hash(data: inputData).map { String(format: "%02x", $0) }.joined()
        let key = "purchases.discovery.\(wallet.accountId.uuidString).\(kind).\(digest)"
        guard !runningKeys.contains(key) else { throw DiscoveryJobError.pending }
        runningKeys.insert(key)
        defer { runningKeys.remove(key) }

        let existingID = defaults.string(forKey: key)
        let id = existingID ?? UUID().uuidString
        guard wallet.commerceEnabled || existingID != nil else { throw DiscoveryJobError.unavailable }
        defaults.set(id, forKey: key)
        var shouldCheckStatus = existingID != nil

        // A limited foreground recovery window. The persisted ID allows another
        // attempt after relaunch without running the paid job twice.
        for attempt in 0..<4 {
            try Task.checkCancellation()
            // Keep the exact bearer used to read the wallet. An account switch
            // while this task awaits cannot spend the next account's allowance.
            guard let url = URL(string: "\(Config.apiBaseURL)/discovery") else {
                throw DiscoveryJobError.unavailable
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.allHTTPHeaderFields = walletRequest.allHTTPHeaderFields
            request.timeoutInterval = 110
            var body: [String: Any] = ["discoveryId": id, "kind": kind]
            if shouldCheckStatus {
                body["action"] = "status"
            } else {
                body["action"] = "start"
                body["input"] = input
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                // Keep the ID: the server may have completed after disconnection.
                throw error
            }
            guard let http = response as? HTTPURLResponse else { throw DiscoveryJobError.failed }
            let decoded = try? JSONDecoder().decode(Response<Result>.self, from: data)
            if http.statusCode == 404 && shouldCheckStatus {
                guard wallet.commerceEnabled else { throw DiscoveryJobError.unavailable }
                shouldCheckStatus = false
                continue
            }
            if http.statusCode == 202 {
                shouldCheckStatus = true
                if attempt < 3 { try await Task.sleep(nanoseconds: 1_000_000_000) }
                continue
            }
            if http.statusCode == 402 {
                defaults.removeObject(forKey: key)
                await walletDidChange()
                throw DiscoveryJobError.allowanceRequired
            }
            if decoded?.code == "MISSING_CITY" {
                defaults.removeObject(forKey: key)
                throw DiscoveryJobError.missingCity
            }
            guard (200...299).contains(http.statusCode), let decoded else {
                // Do not discard uncertain server state on a transient failure.
                throw DiscoveryJobError.unavailable
            }
            switch decoded.status {
            case "committed", "released":
                defaults.removeObject(forKey: key)
                await walletDidChange()
                if let result = decoded.result { return result }
                // A prior failed job is terminal; another explicit search gets a new ID.
                throw DiscoveryJobError.failed
            case "expired", "revoked":
                defaults.removeObject(forKey: key)
                await walletDidChange()
                throw DiscoveryJobError.failed
            default:
                throw DiscoveryJobError.pending
            }
        }
        throw DiscoveryJobError.pending
    }
}
