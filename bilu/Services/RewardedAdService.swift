import Foundation
import Combine
import GoogleMobileAds

@MainActor
final class RewardedAdService: NSObject, ObservableObject {
    static let shared = RewardedAdService()

    @Published private(set) var isReady = false
    @Published private(set) var isBusy = false
    @Published private(set) var isLoadingAd = false
    @Published private(set) var message: String?
    @Published private(set) var privacyOptionsRequired = false

    private var rewardedAd: RewardedAd?
    private var isConfiguring = false
    private let privacy = AdPrivacyService.shared
    private var privacySubscription: AnyCancellable?
    private var adLoadGeneration = UUID()
    private var rewardHandler: ((String) -> Void)?
    private var activeSession: RewardSession?
    private var didEarnActiveReward = false
    private var didDismissActiveAd = false
    private var verifiedRewardToken: String?
    private static let adUnavailableMessage = "An ad isn't available right now. Please try again."

    override init() {
        super.init()
        privacy.$privacyOptionsRequired.assign(to: &$privacyOptionsRequired)
        privacySubscription = privacy.$canRequestAds.sink { [weak self] allowed in
            if !allowed { self?.invalidateCachedAd() }
        }
    }

    func configure() async {
        guard !isConfiguring else { return }
        isConfiguring = true
        defer { isConfiguring = false }
        await privacy.configure()
        guard Config.rewardedAdsAreConfigured else {
            message = "Rewarded ads need a production AdMob ID before release."
            return
        }
        guard privacy.canRequestAds else {
            message = privacy.message
            return
        }
        await loadAd()
    }

    func loadAd() async {
        guard let adUnitID = Config.rewardedAdUnitID,
              privacy.canRequestAds,
              rewardedAd == nil,
              !isLoadingAd else { return }
        isLoadingAd = true
        let generation = adLoadGeneration
        defer {
            if generation == adLoadGeneration { isLoadingAd = false }
        }
        do {
            let ad = try await RewardedAd.load(
                with: adUnitID,
                request: AdPrivacyService.contextualRequest()
            )
            guard generation == adLoadGeneration, privacy.canRequestAds else { return }
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            isReady = true
            // Only clear this load's own error; a reward outcome shown after
            // the previous ad closed must survive the automatic reload.
            if message == Self.adUnavailableMessage { message = nil }
        } catch {
            guard generation == adLoadGeneration else { return }
            isReady = false
            message = Self.adUnavailableMessage
        }
    }

    func showRewardedDiscovery(onReward: @escaping (String) -> Void) async {
        guard !isBusy, !isLoadingAd, privacy.canRequestAds else { return }
        guard let ad = rewardedAd else {
            await loadAd()
            guard rewardedAd != nil else { return }
            return await showRewardedDiscovery(onReward: onReward)
        }

        isBusy = true
        message = nil
        let generation = adLoadGeneration
        do {
            let session = try await RewardSessionAPI.create()
            guard generation == adLoadGeneration, privacy.canRequestAds else {
                isBusy = false
                return
            }
            activeSession = session
            rewardHandler = onReward
            didEarnActiveReward = false
            didDismissActiveAd = false
            verifiedRewardToken = nil

            let options = ServerSideVerificationOptions()
            options.userIdentifier = session.userID
            options.customRewardText = session.token
            ad.serverSideVerificationOptions = options
            ad.present(from: nil) { [weak self] in
                guard let self else { return }
                self.didEarnActiveReward = true
                #if DEBUG
                Task { await self.verifyDebugReward(session: session) }
                #else
                Task { await self.waitForServerVerification(session: session) }
                #endif
            }
        } catch {
            isBusy = false
            message = "The reward couldn't be started. Please try again."
        }
    }

    func presentPrivacyOptions() async {
        guard !isBusy else { return }
        do {
            try await privacy.presentPrivacyOptions()
            await loadAd()
        } catch {
            message = "Privacy choices are unavailable right now."
        }
    }

    private func invalidateCachedAd() {
        adLoadGeneration = UUID()
        if !isBusy { rewardedAd?.fullScreenContentDelegate = nil }
        rewardedAd = nil
        isReady = false
        isLoadingAd = false
    }

    private func waitForServerVerification(session: RewardSession) async {
        // AdMob SSV is normally near-instant, but delivery can be delayed. Keep
        // the earned session alive for a full minute so a transient callback or
        // network delay does not make the user watch another ad unnecessarily.
        for attempt in 0..<60 {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(1))
            }
            guard activeSession?.token == session.token else { return }
            if (try? await RewardSessionAPI.isVerified(token: session.token)) == true {
                markRewardVerified(token: session.token)
                return
            }
        }
        abandonActiveReward(message: "Your ad finished, but verification is delayed. Please try again shortly.")
    }

    #if DEBUG
    private func verifyDebugReward(session: RewardSession) async {
        do {
            try await RewardSessionAPI.debugVerify(token: session.token)
            markRewardVerified(token: session.token)
        } catch {
            print("[RewardedAdService] debug reward rejected; add \(session.userID) to REWARD_DEBUG_USER_IDS")
            guard activeSession?.token == session.token else { return }
            abandonActiveReward(message: "Debug rewards aren't enabled for this account.")
        }
    }
    #endif

    private func abandonActiveReward(message: String) {
        isBusy = false
        self.message = message
        activeSession = nil
        rewardHandler = nil
        didEarnActiveReward = false
        didDismissActiveAd = false
        verifiedRewardToken = nil
    }

    private func markRewardVerified(token: String) {
        guard activeSession?.token == token else { return }
        guard didDismissActiveAd else {
            verifiedRewardToken = token
            return
        }
        deliverReward(token: token)
    }

    private func deliverReward(token: String) {
        isBusy = false
        activeSession = nil
        didEarnActiveReward = false
        didDismissActiveAd = false
        verifiedRewardToken = nil
        let handler = rewardHandler
        rewardHandler = nil
        handler?(token)
    }
}

extension RewardedAdService: FullScreenContentDelegate {
    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        rewardedAd = nil
        isReady = false
        isBusy = false
        activeSession = nil
        didEarnActiveReward = false
        didDismissActiveAd = false
        verifiedRewardToken = nil
        rewardHandler = nil
        message = "The ad couldn't be shown. Please try again."
        Task { await loadAd() }
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        rewardedAd = nil
        isReady = false
        didDismissActiveAd = true
        if let verifiedRewardToken {
            deliverReward(token: verifiedRewardToken)
        }
        if rewardHandler != nil && !didEarnActiveReward {
            isBusy = false
            activeSession = nil
            rewardHandler = nil
            didDismissActiveAd = false
        }
        Task { await loadAd() }
    }
}

private struct RewardSession: Decodable {
    let token: String
    let userID: String

    enum CodingKeys: String, CodingKey {
        case token
        case userID = "userId"
    }
}

private enum RewardSessionAPI {
    static func create() async throws -> RewardSession {
        var request = try await AuthenticatedAPIRequest.post(
            path: "rewarded-access",
            timeout: 10
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["action": "create"]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SupabaseAuthError.invalidResponse
        }
        return try JSONDecoder().decode(RewardSession.self, from: data)
    }

    #if DEBUG
    /// Google's sample ad unit has no SSV callback, so Debug asks the backend to
    /// verify the session. Only accounts in REWARD_DEBUG_USER_IDS succeed.
    static func debugVerify(token: String) async throws {
        var request = try await AuthenticatedAPIRequest.post(
            path: "rewarded-access",
            timeout: 10
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["action": "debug-verify", "token": token]
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SupabaseAuthError.invalidResponse
        }
    }
    #endif

    static func isVerified(token: String) async throws -> Bool {
        var request = try await AuthenticatedAPIRequest.post(
            path: "rewarded-access",
            timeout: 10
        )
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["action": "status", "token": token]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseAuthError.invalidResponse
        }
        return payload["verified"] as? Bool == true
    }
}
