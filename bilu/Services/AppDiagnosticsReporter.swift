import Foundation
import MetricKit
import OSLog

/// Collects Apple's production crash, hang, and performance reports and queues
/// them until the authenticated telemetry endpoint accepts them.
nonisolated final class AppDiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = AppDiagnosticsReporter()
    static let consentDefaultsKey = "privacy.shareDiagnostics"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.simonsoloman.bilu",
        category: "Diagnostics"
    )
    private var started = false

    private override init() {
        super.init()
    }

    func startIfConsented() {
        if UserDefaults.standard.bool(forKey: Self.consentDefaultsKey) {
            start()
        } else {
            // Earlier development builds collected before this preference
            // existed. Do not leave those queued reports on upgraded devices.
            Task { await DiagnosticUploadQueue.shared.removeAll() }
        }
    }

    func setCollectionEnabled(_ isEnabled: Bool) {
        Task { @MainActor in
            DiscoveryAnalytics.shared.setCollectionEnabled(isEnabled)
        }
        if isEnabled {
            start()
        } else {
            stop()
            Task { await DiagnosticUploadQueue.shared.removeAll() }
        }
    }

    /// Queues a one-off note that the saved-places store fell back to memory.
    /// Only a fixed event name and reason code are sent (no paths, no user data),
    /// and only when the user has opted in to sharing diagnostics.
    func recordPersistenceFallback(reasonCode: String) {
        guard UserDefaults.standard.bool(forKey: Self.consentDefaultsKey),
              let payload = try? JSONSerialization.data(
                  withJSONObject: ["event": "persistence_fallback", "reason": reasonCode]
              ) else { return }
        Task { await DiagnosticUploadQueue.shared.enqueue(kind: "diagnostic", payload: payload) }
    }

    private func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
        Task { await DiagnosticUploadQueue.shared.flush() }
    }

    private func stop() {
        guard started else { return }
        MXMetricManager.shared.remove(self)
        started = false
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Task { await DiagnosticUploadQueue.shared.enqueue(kind: "diagnostic", payload: data) }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let data = payload.jsonRepresentation()
            Task { await DiagnosticUploadQueue.shared.enqueue(kind: "metric", payload: data) }
        }
    }

    deinit {
        stop()
        logger.debug("MetricKit diagnostics subscriber removed")
    }
}

private actor DiagnosticUploadQueue {
    static let shared = DiagnosticUploadQueue()

    private struct Report: Codable {
        let id: UUID
        let kind: String
        let payload: String
        let appVersion: String
        let build: String
        let osVersion: String
        let capturedAt: String
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.simonsoloman.bilu",
        category: "DiagnosticUpload"
    )
    private let maximumPayloadBytes = 450_000

    func enqueue(kind: String, payload: Data) async {
        guard payload.count <= maximumPayloadBytes,
              let payloadString = String(data: payload, encoding: .utf8) else {
            logger.error("Discarding an invalid or oversized MetricKit payload")
            return
        }

        let info = Bundle.main.infoDictionary
        let report = Report(
            id: UUID(),
            kind: kind,
            payload: payloadString,
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            capturedAt: ISO8601DateFormatter().string(from: Date())
        )

        guard let fileURL = persist(report) else { return }
        await upload(report, from: fileURL)
    }

    func flush() async {
        guard let directory = queueDirectory(createIfNeeded: false),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return }

        for fileURL in files where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let report = try? JSONDecoder().decode(Report.self, from: data) else {
                continue
            }
            await upload(report, from: fileURL)
        }
    }

    func removeAll() {
        guard let directory = queueDirectory(createIfNeeded: false),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil
              ) else { return }

        for fileURL in files where fileURL.pathExtension == "json" {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist(_ report: Report) -> URL? {
        guard let directory = queueDirectory(createIfNeeded: true),
              let data = try? JSONEncoder().encode(report) else { return nil }
        let fileURL = directory.appendingPathComponent("\(report.id.uuidString).json")
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return fileURL
        } catch {
            logger.error("Could not queue MetricKit report: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func upload(_ report: Report, from fileURL: URL) async {
        do {
            var request = try await AuthenticatedAPIRequest.post(path: "telemetry", timeout: 10)
            request.httpBody = try JSONEncoder().encode(report)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if (200...299).contains(http.statusCode)
                || ((400...499).contains(http.statusCode) && http.statusCode != 429) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            // Keep the queued report for the next app launch.
            logger.debug("MetricKit upload deferred: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func queueDirectory(createIfNeeded: Bool) -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport.appendingPathComponent("DiagnosticsQueue", isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return directory
    }
}
