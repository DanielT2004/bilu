import Foundation
import Combine
import GoogleMobileAds
import UserMessagingPlatform

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
    private var didStartSDK = false
    private var didApplyDebugConsentReset = false
    private var rewardHandler: ((String) -> Void)?
    private var activeSession: RewardSession?
    private var didEarnActiveReward = false
    private var didDismissActiveAd = false
    private var verifiedRewardToken: String?

    func configure() async {
        guard !isConfiguring else { return }
        guard Config.rewardedAdsAreConfigured else {
            message = "Rewarded ads need a production AdMob ID before release."
            return
        }
        isConfiguring = true
        defer { isConfiguring = false }

        do {
            try await updateConsent()
        } catch {
            // UMP permits using the last-known consent state after an update
            // error. Never request an ad unless canRequestAds confirms it.
            message = "Privacy choices could not be refreshed."
        }

        privacyOptionsRequired = ConsentInformation.shared
            .privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else { return }
        startSDKIfNeeded()
        await loadAd()
    }

    func loadAd() async {
        guard let adUnitID = Config.rewardedAdUnitID,
              ConsentInformation.shared.canRequestAds,
              rewardedAd == nil,
              !isLoadingAd else { return }
        isLoadingAd = true
        defer { isLoadingAd = false }
        do {
            let request = Request()
            let extras = Extras()
            // Bilu uses privacy-first contextual rewarded ads. Do not request
            // personalized ads or depend on ATT/IDFA for monetization.
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
            let ad = try await RewardedAd.load(with: adUnitID, request: request)
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
            isReady = true
            message = nil
        } catch {
            isReady = false
            message = "An ad isn't available right now. Please try again."
        }
    }

    func showRewardedDiscovery(onReward: @escaping (String) -> Void) async {
        guard !isBusy, !isLoadingAd else { return }
        guard let ad = rewardedAd else {
            await loadAd()
            guard rewardedAd != nil else { return }
            return await showRewardedDiscovery(onReward: onReward)
        }

        isBusy = true
        do {
            let session = try await RewardSessionAPI.create()
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
                self.markRewardVerified(token: session.token)
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
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            privacyOptionsRequired = ConsentInformation.shared
                .privacyOptionsRequirementStatus == .required
            // A cached ad may have been requested under the previous consent
            // state. Discard it and make the next request with the new choices.
            rewardedAd = nil
            isReady = false
            if ConsentInformation.shared.canRequestAds {
                startSDKIfNeeded()
                await loadAd()
            }
        } catch {
            message = "Privacy choices are unavailable right now."
        }
    }

    private func updateConsent() async throws {
        let parameters = RequestParameters()
        #if DEBUG
        // Allows deterministic testing of the published AdMob privacy messages
        // without changing production geography. Simulators are automatically
        // accepted as UMP test devices.
        if let geography = ProcessInfo.processInfo.environment["BILU_TEST_UMP_GEOGRAPHY"] {
            let debugSettings = DebugSettings()
            switch geography.lowercased() {
            case "eea": debugSettings.geography = .EEA
            case "us": debugSettings.geography = .regulatedUSState
            default: debugSettings.geography = .other
            }
            parameters.debugSettings = debugSettings
            if !didApplyDebugConsentReset {
                ConsentInformation.shared.reset()
                didApplyDebugConsentReset = true
            }
        }
        #endif
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        try await ConsentForm.loadAndPresentIfRequired(from: nil)
    }

    private func startSDKIfNeeded() {
        guard !didStartSDK else { return }
        didStartSDK = true
        // Bilu does not use Google's cross-app publisher first-party identifier.
        // Keep rewarded ads contextual/consent-driven and minimize identifiers
        // before the SDK starts.
        MobileAds.shared.requestConfiguration
            .setPublisherFirstPartyIDEnabled(false)
        MobileAds.shared.start()
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
        isBusy = false
        message = "Your ad finished, but verification is delayed. Please try again shortly."
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
        #if DEBUG
        // Google's sample ad unit has no configurable SSV callback. Debug still
        // exercises consent, loading and presentation with a one-time test token.
        return RewardSession(token: UUID().uuidString, userID: "debug-test-user")
        #else
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
        #endif
    }

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
