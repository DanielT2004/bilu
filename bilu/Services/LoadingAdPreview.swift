#if DEBUG
import SwiftUI

/// Deterministic UI tests never call AI providers or spend an allowance. The
/// optional `sdk` scenario uses Google's test banner with fixture AI only.
struct LoadingAdPreview: View {
    static var scenario: String? { ProcessInfo.processInfo.environment["BILU_UI_TEST_LOADING_SCENARIO"] }
    @StateObject private var model: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let scenario: String

    init(scenario: String) {
        self.scenario = scenario
        let defaults = UserDefaults(suiteName: "LoadingAdPreview.\(UUID().uuidString)") ?? .standard
        let ads = LoadingAdController(
            frequency: LoadingAdFrequencyStore(defaults: defaults),
            eligible: { scenario == "sdk" ? AdPrivacyService.shared.canRequestAds : true },
            factory: { width, root in
                if scenario == "sdk", let unit = AdvertisingConfiguration.loadingBannerUnitID {
                    return GoogleLoadingBanner(unitID: unit, width: width, root: root)
                }
                return PreviewBanner(width: width, fails: scenario == "failed")
            }, record: { _, _, _, _, _, _, _, _ in }, observeEnvironment: scenario == "sdk"
        )
        let model = HomeViewModel(loadingAds: ads,
            allowance: DiscoveryAllowance(defaults: defaults), commerceEnabled: { false },
            fetchRecommendations: { _, _ in
                let delay: Double = scenario == "quick" ? 0.01 : (scenario == "success" || scenario == "failed" ? 5 : 300)
                try? await Task.sleep(for: .seconds(delay))
                return VibeFetchOutcome(result: VibeResult(recommendations: [], groundingPlaces: [], relaxed: nil), failure: .noMatches)
            })
        model.selection.occasion = "Date Night"
        model.selection.foodFeelings = ["Rich & indulgent"]
        model.selection.location = "Los Angeles"
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { model.cancelDiscovery() }
                    .lineLimit(1)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("loading-preview-cancel")
                Spacer()
                Text("bilu").font(.custom(AppTheme.FontName.serifRegular, fixedSize: 28))
                Spacer()
                Text("UI TEST").font(.system(size: 10))
            }
            .foregroundStyle(AppTheme.sage)
            .padding(.horizontal, 20)
            ScrollView {
                if model.step == .loading {
                    DiscoveryLoadingView(phase: model.loadingPhase, summary: model.discoveryLoadingSummary, ads: model.loadingAds)
                } else if model.step == .reveal {
                    Text("Results arrived")
                        .accessibilityIdentifier("loading-preview-results")
                        .onAppear { model.loadingAds.resultsArrived() }
                } else {
                    Text("Discovery cancelled").accessibilityIdentifier("loading-preview-cancelled")
                }
            }
        }
        .background(AppTheme.surface)
        .task {
            model.reduceMotionPreference = reduceMotion
            if scenario == "sdk" { await AdPrivacyService.shared.configure() }
            await model.submitSurvey()
        }
        .onDisappear { model.cancelDiscovery() }
    }
}

@MainActor
private final class PreviewBanner: LoadingBannerAd {
    let view: UIView
    let size: CGSize
    var onEvent: ((LoadingBannerEvent) -> Void)?
    private let fails: Bool

    init(width: CGFloat, fails: Bool) {
        self.fails = fails
        self.size = CGSize(width: width, height: 100)
        let label = UILabel(frame: CGRect(origin: .zero, size: size))
        label.text = "TEST FIXTURE\nAdvertisement layout preview"
        label.numberOfLines = 2
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(AppTheme.onSurface)
        label.backgroundColor = UIColor(AppTheme.sageLt)
        label.accessibilityIdentifier = "loading-preview-banner"
        self.view = label
    }
    func load() {
        if fails { onEvent?(.failed(1)) }
        else { onEvent?(.loaded); onEvent?(.impression) }
    }
    func dispose() { view.removeFromSuperview(); onEvent = nil }
}
#endif
