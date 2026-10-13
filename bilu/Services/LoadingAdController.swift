import Combine
import Foundation
import UIKit

/// Owns only passive monetization. Discovery starts/finishes synchronously and
/// never awaits this controller, consent, an SDK request, or an impression.
@MainActor
final class LoadingAdController: ObservableObject {
    typealias Factory = (CGFloat, UIViewController) -> (any LoadingBannerAd)?
    typealias Recorder = (DiscoveryAnalytics.Event, UUID, TimeInterval?, Bool, Int?, Decimal?, String?, Int?) -> Void

    @Published private(set) var bannerView: UIView?
    @Published private(set) var isLoaded = false
    private(set) var discoveryID: UUID?
    private(set) var hadImpression = false
    private var startedAt: TimeInterval = 0
    private var arrivalID: UUID?
    private var arrivalHadImpression = false
    private var attempted = false
    private var suppressed = false
    private var didRecordRevenue = false
    private var ad: (any LoadingBannerAd)?
    private var pending: Task<Void, Never>?
    private var pendingID: UUID?
    private var availableWidth: CGFloat = 0
    private var subscriptions: Set<AnyCancellable> = []
    private let frequency: LoadingAdFrequencyStore
    private let eligible: () -> Bool
    private let factory: Factory
    private let record: Recorder
    private let uptime: () -> TimeInterval
    private let wait: (TimeInterval) async throws -> Void

    init(frequency: LoadingAdFrequencyStore? = nil,
         eligible: (() -> Bool)? = nil,
         factory: Factory? = nil,
         record: Recorder? = nil,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wait: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         observeEnvironment: Bool = true) {
        self.frequency = frequency ?? LoadingAdFrequencyStore()
        self.eligible = eligible ?? {
            let purchases = PurchaseStore.shared
            // Unknown/stale entitlements and pending purchases fail closed,
            // even if the commerce feature flag is temporarily disabled.
            return AdPrivacyService.shared.canRequestAds
                && !RewardedAdService.shared.isBusy
                && AdvertisingConfiguration.permitsLoadingAds(
                    wallet: purchases.wallet,
                    hasPendingSync: purchases.hasPendingSync,
                    purchaseState: purchases.state
                )
                && UIApplication.shared.applicationState == .active
        }
        self.factory = factory ?? { width, root in
            guard let id = AdvertisingConfiguration.loadingBannerUnitID else { return nil }
            return GoogleLoadingBanner(unitID: id, width: width, root: root)
        }
        self.record = record ?? { event, id, duration, visible, code, revenue, currency, precision in
            DiscoveryAnalytics.shared.record(event, discoveryID: id, duration: duration,
                adVisible: visible, code: code, revenue: revenue, currency: currency, precision: precision)
        }
        self.uptime = uptime
        self.wait = wait
        if observeEnvironment {
            AdPrivacyService.shared.$canRequestAds.dropFirst().sink { [weak self] allowed in
                if !allowed { self?.suppress() }
            }.store(in: &subscriptions)
            RewardedAdService.shared.$isBusy.dropFirst().sink { [weak self] busy in
                if busy { self?.suppress() }
            }.store(in: &subscriptions)
            PurchaseStore.shared.$wallet.dropFirst().sink { [weak self] wallet in
                if wallet?.plan != "free" { self?.suppress() }
            }.store(in: &subscriptions)
            PurchaseStore.shared.$hasPendingSync.dropFirst().sink { [weak self] pending in
                if pending { self?.suppress() }
            }.store(in: &subscriptions)
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
                .sink { [weak self] _ in self?.background() }.store(in: &subscriptions)
        }
    }

    func begin(id: UUID, allowAds: Bool = true) {
        if discoveryID != nil { finish(.cancelled) }
        discoveryID = id
        arrivalID = nil
        hadImpression = false
        didRecordRevenue = false
        startedAt = uptime()
        attempted = false
        suppressed = !allowAds
        emit(.started)
    }

    /// Called once layout knows the real safe-area width. A short, cancellable
    /// grace avoids even requesting a banner for near-instant results.
    func prepare(width: CGFloat, root: UIViewController) {
        availableWidth = width
        if let ad, width < ad.size.width { suppress(); return }
        guard let id = discoveryID, !suppressed, !attempted, pending == nil,
              width >= 320, eligible(), frequency.canRequest else { return }
        let delay = max(0, frequency.policy.quickResponseGrace - (uptime() - startedAt))
        let preparationID = UUID()
        pendingID = preparationID
        pending = Task { [weak self, weak root] in
            guard let self else { return }
            defer {
                if self.pendingID == preparationID { self.pending = nil; self.pendingID = nil }
            }
            do { try await self.wait(delay) } catch { return }
            guard !Task.isCancelled, self.pendingID == preparationID,
                  self.discoveryID == id, !self.suppressed, !self.attempted,
                  self.eligible(), self.frequency.canRequest, let root,
                  self.availableWidth >= 320,
                  let ad = self.factory(floor(min(self.availableWidth, 600)), root) else { return }
            self.attempted = true
            self.ad = ad
            ad.view.isHidden = true
            ad.onEvent = { [weak self] event in
                guard let self, self.discoveryID == id, !self.suppressed else { return }
                self.receive(event)
            }
            self.frequency.recordRequest()
            self.emit(.adRequested)
            self.bannerView = ad.view
            ad.load()
        }
    }

    func finish(_ event: DiscoveryAnalytics.Event) {
        guard let id = discoveryID else { return }
        emit(event, duration: max(0, uptime() - startedAt))
        if event == .completed {
            arrivalID = id
            arrivalHadImpression = hadImpression
        }
        if event == .failed { frequency.suppressAfterError(adFailure: false) }
        discoveryID = nil
        suppress()
    }

    func resultsArrived() {
        guard let id = arrivalID else { return }
        record(.resultsArrived, id, nil, arrivalHadImpression, nil, nil, nil, nil)
        arrivalID = nil
    }

    func background() {
        guard discoveryID != nil else { return }
        emit(.backgrounded, duration: max(0, uptime() - startedAt))
        suppress()
    }

    func suppress() {
        suppressed = true
        pending?.cancel()
        pending = nil
        pendingID = nil
        ad?.dispose()
        ad = nil
        bannerView = nil
        isLoaded = false
    }

    private func receive(_ event: LoadingBannerEvent) {
        guard eligible() else { suppress(); return }
        switch event {
        case .loaded:
            isLoaded = true
            ad?.view.isHidden = false
        case .impression:
            guard !hadImpression else { return }
            hadImpression = true
            emit(.adImpression)
        case .clicked: emit(.adClicked)
        case .failed(let code):
            emit(.adFailed, code: code)
            frequency.suppressAfterError(adFailure: true)
            suppress()
        case .revenue(let amount, let currency, let precision):
            guard !didRecordRevenue else { return }
            didRecordRevenue = true
            guard let id = discoveryID else { return }
            record(.adRevenue, id, nil, hadImpression, nil, amount, currency, precision)
        }
    }

    private func emit(_ event: DiscoveryAnalytics.Event, duration: TimeInterval? = nil, code: Int? = nil) {
        guard let id = discoveryID else { return }
        record(event, id, duration, hadImpression, code, nil, nil, nil)
    }
}
