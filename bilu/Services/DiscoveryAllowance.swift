import Combine
import Foundation

/// One free discovery per UTC day, plus one server-verified discovery for each
/// completed rewarded ad. The backend enforces the same rule before spending
/// on Gemini; this local state only drives a responsive UI.
@MainActor
final class DiscoveryAllowance: ObservableObject {
    static let shared = DiscoveryAllowance()
    static let dailyFreeLimit = 1

    @Published private(set) var usedFreeDiscoveries = 0
    @Published private(set) var rewardedAccessToken: String?

    private let defaults: UserDefaults
    private let now: () -> Date
    private var activeKey = ""
    private let rewardTokenKey = "ads.pendingRewardedDiscoveryToken"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        rewardedAccessToken = defaults.string(forKey: rewardTokenKey)
        refreshPeriod()
    }

    var remainingFreeDiscoveries: Int {
        refreshPeriod()
        return max(0, Self.dailyFreeLimit - usedFreeDiscoveries)
    }

    var hasRewardedDiscovery: Bool { rewardedAccessToken != nil }
    var canRunDiscovery: Bool { remainingFreeDiscoveries > 0 || hasRewardedDiscovery }

    func grantReward(token: String) {
        guard !token.isEmpty else { return }
        rewardedAccessToken = token
        defaults.set(token, forKey: rewardTokenKey)
    }

    /// Reconciles local UI state when the authoritative backend reports that
    /// neither free nor rewarded access is available. This also drops an
    /// expired or already-consumed reward token so the user can earn a new one.
    func reconcileRewardRequired() {
        refreshPeriod()
        usedFreeDiscoveries = Self.dailyFreeLimit
        defaults.set(usedFreeDiscoveries, forKey: activeKey)
        rewardedAccessToken = nil
        defaults.removeObject(forKey: rewardTokenKey)
    }

    /// Records only completed requests. Transport failures leave the free run
    /// or rewarded token available for a retry.
    func recordDiscovery(usedRewardToken: String?) {
        refreshPeriod()
        if let usedRewardToken,
           usedRewardToken == rewardedAccessToken {
            rewardedAccessToken = nil
            defaults.removeObject(forKey: rewardTokenKey)
        } else if usedFreeDiscoveries < Self.dailyFreeLimit {
            usedFreeDiscoveries += 1
            defaults.set(usedFreeDiscoveries, forKey: activeKey)
        }
    }

    private func refreshPeriod() {
        let components = Calendar(identifier: .gregorian)
            .dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: now())
        let key = "ads.freeDiscoveries.\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        guard key != activeKey else { return }
        activeKey = key
        usedFreeDiscoveries = min(
            Self.dailyFreeLimit,
            max(0, defaults.integer(forKey: key))
        )
    }
}
