import Foundation

/// Public AdMob identifiers are configuration, never server credentials.
enum AdvertisingConfiguration {
    static var loadingBannerUnitID: String? {
        #if DEBUG
        return "ca-app-pub-3940256099942544/2435281174"
        #else
        guard let value = Bundle.main.object(forInfoDictionaryKey: "BILULoadingBannerAdUnitIdentifier") as? String,
              value.hasPrefix("ca-app-pub-"), value.contains("/"),
              !value.contains("3940256099942544"), !value.contains("$(") else { return nil }
        return value
        #endif
    }

    struct Frequency {
        var minimumInterval: TimeInterval = 120
        var maximumRequestsPerUTCDay = 3
        var failureCooldown: TimeInterval = 600
        var discoveryErrorCooldown: TimeInterval = 300
        var quickResponseGrace: TimeInterval = 1
    }

    static let frequency = Frequency()

    /// Sales feature flags never revoke an existing Pro customer's ad-free
    /// entitlement. An unknown wallet or unsettled purchase fails closed.
    @MainActor
    static func permitsLoadingAds(
        wallet: PurchaseWallet?,
        hasPendingSync: Bool,
        purchaseState: PurchaseState
    ) -> Bool {
        wallet?.plan == "free"
            && !hasPendingSync
            && purchaseState != .purchasing
            && purchaseState != .pendingApproval
    }
}

/// Persists attempts as well as impressions, so no-fill and relaunch cannot
/// create request storms. Passive ads never read or write discovery balances.
@MainActor
final class LoadingAdFrequencyStore {
    private let defaults: UserDefaults
    private let now: () -> Date
    let policy: AdvertisingConfiguration.Frequency

    init(defaults: UserDefaults = .standard,
         policy: AdvertisingConfiguration.Frequency? = nil,
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.policy = policy ?? AdvertisingConfiguration.frequency
        self.now = now
    }

    private var day: Int { Int(floor(now().timeIntervalSince1970 / 86_400)) }
    var canRequest: Bool {
        let last = defaults.object(forKey: "ads.loading.lastRequest") as? Date
        let blockedUntil = defaults.object(forKey: "ads.loading.blockedUntil") as? Date ?? .distantPast
        let count = defaults.integer(forKey: "ads.loading.day") == day
            ? defaults.integer(forKey: "ads.loading.requests") : 0
        return now() >= blockedUntil
            && (last == nil || now().timeIntervalSince(last ?? .distantPast) >= policy.minimumInterval)
            && count < policy.maximumRequestsPerUTCDay
    }

    func recordRequest() {
        let count = defaults.integer(forKey: "ads.loading.day") == day
            ? defaults.integer(forKey: "ads.loading.requests") : 0
        defaults.set(day, forKey: "ads.loading.day")
        defaults.set(count + 1, forKey: "ads.loading.requests")
        defaults.set(now(), forKey: "ads.loading.lastRequest")
    }

    func suppressAfterError(adFailure: Bool) {
        let until = now().addingTimeInterval(adFailure ? policy.failureCooldown : policy.discoveryErrorCooldown)
        let previous = defaults.object(forKey: "ads.loading.blockedUntil") as? Date ?? .distantPast
        defaults.set(max(previous, until), forKey: "ads.loading.blockedUntil")
    }
}
