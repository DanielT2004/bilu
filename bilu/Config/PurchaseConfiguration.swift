import Foundation

struct PurchaseConfiguration: Equatable {
    let commerceEnabled: Bool
    let proEnabled: Bool

    static var current: PurchaseConfiguration {
        let sandboxManifest = Bundle.main.object(forInfoDictionaryKey: "BILUPaymentSandbox") as? Bool == true
        if !Config.supabase.isConfigured || (sandboxManifest && !Config.supabase.isPaymentSandbox) {
            return PurchaseConfiguration(commerceEnabled: false, proEnabled: false)
        }
        return PurchaseConfiguration(
            commerceEnabled: Bundle.main.object(forInfoDictionaryKey: "BILUCommerceEnabled") as? Bool ?? false,
            // A configured payment sandbox must exercise the same offer gates as
            // production. The flags remain false by default, so this does not
            // expose an offer until both the app and server explicitly allow it.
            proEnabled: Bundle.main.object(forInfoDictionaryKey: "BILUProEnabled") as? Bool ?? false
        )
    }
}

enum PurchaseProductID {
    static let discoveryPass = "com.simonsoloman.bilu.discovery_pass"
    static let proMonthly = "com.simonsoloman.bilu.pro.monthly"
    static let proAnnual = "com.simonsoloman.bilu.pro.annual"
    static let all: Set<String> = [discoveryPass, proMonthly, proAnnual]
}
