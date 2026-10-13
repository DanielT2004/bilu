import Combine
import Foundation
import GoogleMobileAds
import UserMessagingPlatform

/// One consent and SDK lifecycle for passive banners and voluntary rewarded ads.
@MainActor
final class AdPrivacyService: ObservableObject {
    static let shared = AdPrivacyService()

    @Published private(set) var canRequestAds = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var message: String?

    private var configurationTask: Task<Void, Never>?
    private var didConfigure = false
    private var didStartSDK = false
    private var isPresentingPrivacyOptions = false

    func configure() async {
        if let configurationTask {
            await configurationTask.value
            return
        }
        guard !didConfigure else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.updateConsent()
                self.message = nil
                self.didConfigure = true
            } catch {
                // UMP permits its last-known consent state after an update
                // failure. Only canRequestAds may authorize SDK ad requests.
                self.message = "Privacy choices could not be refreshed."
            }
            self.applyConsentState()
        }
        configurationTask = task
        await task.value
        configurationTask = nil
    }

    func presentPrivacyOptions() async throws {
        await configure()
        guard !isPresentingPrivacyOptions else { return }
        isPresentingPrivacyOptions = true
        // Publish the pause before presenting UMP so every placement discards
        // cached ads and rejects late responses from the previous consent state.
        canRequestAds = false
        defer {
            isPresentingPrivacyOptions = false
            applyConsentState()
        }
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
            message = nil
        } catch {
            message = "Privacy choices are unavailable right now."
            throw error
        }
    }

    static func contextualRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    private func applyConsentState() {
        privacyOptionsRequired = ConsentInformation.shared
            .privacyOptionsRequirementStatus == .required
        let allowed = ConsentInformation.shared.canRequestAds
        if allowed { startSDKIfNeeded() }
        canRequestAds = allowed
    }

    private func updateConsent() async throws {
        let parameters = RequestParameters()
        #if DEBUG
        if let geography = ProcessInfo.processInfo.environment["BILU_TEST_UMP_GEOGRAPHY"] {
            let debugSettings = DebugSettings()
            switch geography.lowercased() {
            case "eea": debugSettings.geography = .EEA
            case "us": debugSettings.geography = .regulatedUSState
            default: debugSettings.geography = .other
            }
            parameters.debugSettings = debugSettings
            ConsentInformation.shared.reset()
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
        // Contextual requests do not depend on ATT/IDFA. Disable Google's
        // cross-app publisher first-party identifier before SDK initialization.
        MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
        MobileAds.shared.start()
    }
}
