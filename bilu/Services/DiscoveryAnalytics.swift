import Foundation

/// Optional first-party diagnostics. Never awaited by discovery or advertising.
/// The queue is memory-only; identifiers are random for each discovery and must
/// never be a backend discovery, account, reward, or advertising identifier.
@MainActor
final class DiscoveryAnalytics {
    static let shared = DiscoveryAnalytics()

    enum Event: String, Codable, CaseIterable {
        case started, completed, failed, cancelled, resultsArrived
        case adRequested, adImpression, adFailed, adRevenue, adClicked, backgrounded
    }

    struct Report: Codable {
        let id: UUID
        let discoveryID: UUID
        let event: Event
        let capturedAt: String
        let durationMilliseconds: Int?
        let adVisible: Bool
        let code: Int?
        let revenue: String?
        let currency: String?
        let precision: Int?
    }

    struct Envelope: Encodable {
        let version = 1
        let appVersion: String
        let build: String
        let events: [Report]
    }

    enum UploadResult { case accepted, retry, discard }
    typealias Uploader = @MainActor ([Report]) async -> UploadResult

    private let defaults: UserDefaults
    private let uploader: Uploader
    private let uploadDelay: Duration
    private let automaticallyUpload: Bool
    private var queue: [Report] = []
    private var uploadTask: Task<Void, Never>?
    private var generation = UUID()
    private var isUploading = false
    private var failureCount = 0
    private let maximumQueuedEvents = 100
    private let maximumBatchSize = 20

    var pendingEventCount: Int { queue.count }

    private convenience init() {
        self.init(defaults: .standard, uploader: Self.upload)
    }

    init(defaults: UserDefaults, uploadDelay: Duration = .seconds(2), automaticallyUpload: Bool = true, uploader: @escaping Uploader) {
        self.defaults = defaults
        self.uploadDelay = uploadDelay
        self.automaticallyUpload = automaticallyUpload
        self.uploader = uploader
    }

    func record(
        _ event: Event,
        discoveryID: UUID,
        duration: TimeInterval? = nil,
        adVisible: Bool = false,
        code: Int? = nil,
        revenue: Decimal? = nil,
        currency: String? = nil,
        precision: Int? = nil
    ) {
        guard defaults.bool(forKey: AppDiagnosticsReporter.consentDefaultsKey) else {
            setCollectionEnabled(false)
            return
        }

        let milliseconds = duration.flatMap { value -> Int? in
            guard value.isFinite, value >= 0 else { return nil }
            return Int((min(value, 3_600) * 1_000).rounded())
        }
        let revenueString: String?
        let currencyCode: String?
        let revenuePrecision: Int?
        if event == .adRevenue, let revenue, !revenue.isNaN,
           revenue >= 0, revenue <= 10_000,
           let currency, currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil,
           let precision, (0...3).contains(precision) {
            revenueString = NSDecimalNumber(decimal: revenue).stringValue
            currencyCode = currency
            revenuePrecision = precision
        } else {
            // Revenue is an all-or-nothing tuple; malformed SDK values are not sent.
            if event == .adRevenue { return }
            revenueString = nil
            currencyCode = nil
            revenuePrecision = nil
        }

        let report = Report(
            id: UUID(), discoveryID: discoveryID, event: event,
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            durationMilliseconds: milliseconds, adVisible: adVisible,
            code: code.map { min(max($0, -100_000), 100_000) },
            revenue: revenueString, currency: currencyCode, precision: revenuePrecision
        )
        if queue.count == maximumQueuedEvents { queue.removeFirst() }
        queue.append(report)
        scheduleUpload(after: uploadDelay)
    }

    /// Called by the existing Share Diagnostics control. Cancel pending network
    /// work and discard all local events immediately when consent is withdrawn.
    func setCollectionEnabled(_ isEnabled: Bool) {
        guard !isEnabled else { return }
        generation = UUID()
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
        queue.removeAll()
        failureCount = 0
    }

    func flush() async {
        guard !isUploading else { return }
        guard defaults.bool(forKey: AppDiagnosticsReporter.consentDefaultsKey) else {
            setCollectionEnabled(false)
            return
        }
        guard !queue.isEmpty else { return }
        isUploading = true
        let uploadGeneration = generation
        let batch = Array(queue.prefix(maximumBatchSize))
        let result = await uploader(batch)
        guard uploadGeneration == generation else { return }
        isUploading = false
        guard !Task.isCancelled else { return }
        uploadTask = nil
        guard defaults.bool(forKey: AppDiagnosticsReporter.consentDefaultsKey) else {
            setCollectionEnabled(false)
            return
        }

        switch result {
        case .accepted, .discard:
            remove(batch)
            failureCount = 0
        case .retry:
            failureCount += 1
            if failureCount >= 3 {
                remove(batch)
                failureCount = 0
            }
        }
        if !queue.isEmpty {
            scheduleUpload(after: failureCount == 0 ? uploadDelay : .seconds(30))
        }
    }

    private func remove(_ batch: [Report]) {
        let ids = Set(batch.map(\.id))
        queue.removeAll { ids.contains($0.id) }
    }

    private func scheduleUpload(after delay: Duration) {
        guard automaticallyUpload, uploadTask == nil else { return }
        uploadTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.flush()
        }
    }

    private static func upload(_ reports: [Report]) async -> UploadResult {
        guard UserDefaults.standard.bool(forKey: AppDiagnosticsReporter.consentDefaultsKey),
              !Task.isCancelled else { return .discard }
        do {
            var request = try await AuthenticatedAPIRequest.post(path: "discovery-telemetry", timeout: 8)
            guard UserDefaults.standard.bool(forKey: AppDiagnosticsReporter.consentDefaultsKey),
                  !Task.isCancelled else { return .discard }
            request.httpBody = try JSONEncoder().encode(Envelope(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                events: reports
            ))
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .retry }
            if (200...299).contains(http.statusCode) { return .accepted }
            if (400...499).contains(http.statusCode) { return .discard }
            return .retry
        } catch {
            return Task.isCancelled ? .discard : .retry
        }
    }
}
