import Foundation

@MainActor
protocol PurchaseAPIClient {
    func wallet() async throws -> PurchaseWallet
    func verify(signedTransaction: String) async throws -> PurchaseWallet
}

enum PurchaseAPIError: Error, Equatable {
    case signInRequired
    case accountMismatch
    case unavailable
    case invalidTransaction
    case invalidResponse
    case serviceUnavailable
}

@MainActor
struct PurchaseAPI: PurchaseAPIClient {
    private struct Failure: Decodable { let code: String? }
    var session: URLSession = .shared

    func wallet() async throws -> PurchaseWallet {
        try await post(path: "purchase-wallet", body: [String: String]())
    }

    func verify(signedTransaction: String) async throws -> PurchaseWallet {
        struct Response: Decodable { let wallet: PurchaseWallet }
        let response: Response = try await post(
            path: "purchase-verify", body: ["signedTransaction": signedTransaction]
        )
        return response.wallet
    }

    private func post<Response: Decodable>(path: String, body: [String: String]) async throws -> Response {
        var request = try await AuthenticatedAPIRequest.post(path: path, timeout: 20)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PurchaseAPIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.code
            switch code {
            case "AUTH_REQUIRED", "INVALID_SESSION", "ACCOUNT_REQUIRED":
                throw PurchaseAPIError.signInRequired
            case "PURCHASE_ACCOUNT_MISMATCH": throw PurchaseAPIError.accountMismatch
            case "COMMERCE_DISABLED", "PRODUCT_UNAVAILABLE": throw PurchaseAPIError.unavailable
            case "INVALID_TRANSACTION": throw PurchaseAPIError.invalidTransaction
            default:
                throw http.statusCode == 401 ? PurchaseAPIError.signInRequired : PurchaseAPIError.serviceUnavailable
            }
        }
        return try Self.decoder().decode(Response.self, from: data)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid wallet period")
        }
        return decoder
    }
}
