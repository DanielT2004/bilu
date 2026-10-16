//
//  PersistenceController.swift
//  bilu
//
//  Single place that builds the SwiftData ModelContainer. A persistent-store
//  failure must never erase the user's saved places. The original store stays
//  untouched while the app falls back to a temporary in-memory container, and
//  the fallback is reported (`PersistenceStatus`) so the UI never shows a save
//  as kept when it will vanish on relaunch.
//

import Foundation
import OSLog
import SQLite3
import SwiftData

/// Whether saves made this session will survive a relaunch.
enum PersistenceStatus: Equatable {
    /// The on-disk store opened; saves are kept.
    case persistent
    /// The on-disk store couldn't be opened, so saves only last until the app
    /// closes. The original store files are untouched.
    case temporary(PersistenceFailureReason)

    var isPersistent: Bool { self == .persistent }
}

/// Why the store couldn't open, reduced to what the user can act on.
enum PersistenceFailureReason: Equatable {
    /// The device is out of space (Cocoa out-of-space or SQLite "disk full").
    case lowStorage
    /// Anything else: unreadable/corrupt file, migration failure, locked file.
    case unavailable

    /// Stable, PII-free code for logs and diagnostics.
    var diagnosticCode: String {
        switch self {
        case .lowStorage: return "low_storage"
        case .unavailable: return "unavailable"
        }
    }
}

enum PersistenceController {
    static let schema = Schema([SavedPlace.self, SavedVibe.self])
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.simonsoloman.bilu",
        category: "Persistence"
    )

    struct Opened {
        let container: ModelContainer
        let status: PersistenceStatus
    }

    #if DEBUG
    /// `-SimulatePersistenceFailure YES` forces the in-memory fallback without
    /// touching the real store, for UI tests and screenshots.
    static var isFailureSimulated: Bool {
        UserDefaults.standard.bool(forKey: "SimulatePersistenceFailure")
    }
    #endif

    /// The real, persisted container used at app launch. `storeURL` is for tests;
    /// `nil` uses SwiftData's default store location. Never deletes or replaces an
    /// existing store: if it can't be opened, the files stay exactly as they were.
    /// Opening is attempted once per launch; there is no retry loop.
    static func open(storeURL: URL? = nil, simulateFailure: Bool = false) -> Opened {
        if simulateFailure {
            logger.notice("Simulating a persistent-store failure; the real store is not opened.")
            return Opened(container: inMemoryContainer(), status: .temporary(.unavailable))
        }

        let config = storeURL.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema)
        let reason: PersistenceFailureReason
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return Opened(container: container, status: .persistent)
        } catch {
            reason = failureReason(for: error)
            logger.fault(
                "Persistent store could not be opened (reason: \(reason.diagnosticCode, privacy: .public)); preserving it and using an in-memory fallback. Error: \(error.localizedDescription, privacy: .public)"
            )
        }
        // The persistent files remain in place for recovery by a future launch or
        // app update. Saves made during this degraded session are intentionally
        // temporary so a second database never diverges from the preserved source
        // of truth.
        return Opened(container: inMemoryContainer(), status: .temporary(reason))
    }

    /// Convenience for callers that only need the container.
    static func makeContainer(storeURL: URL? = nil) -> ModelContainer {
        open(storeURL: storeURL).container
    }

    /// In-memory container for #Preview — can only fail from a schema-definition
    /// bug (a programmer error, not a runtime condition), so fatalError is correct here.
    static func previewContainer() -> ModelContainer {
        inMemoryContainer()
    }

    /// Walks the error and its underlying errors for an out-of-space signal.
    static func failureReason(for error: Error) -> PersistenceFailureReason {
        var pending: [NSError] = [error as NSError]
        var visited = 0
        while let current = pending.popLast(), visited < 16 {
            visited += 1
            if current.domain == NSCocoaErrorDomain, current.code == NSFileWriteOutOfSpaceError {
                return .lowStorage
            }
            if current.domain == NSPOSIXErrorDomain, current.code == Int(ENOSPC) {
                return .lowStorage
            }
            if current.domain == "NSSQLiteErrorDomain", current.code == Int(SQLITE_FULL) {
                return .lowStorage
            }
            if let sqliteCode = current.userInfo["NSSQLiteErrorDomain"] as? Int, sqliteCode == Int(SQLITE_FULL) {
                return .lowStorage
            }
            if let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError {
                pending.append(underlying)
            }
            if let detailed = current.userInfo["NSDetailedErrors"] as? [NSError] {
                pending.append(contentsOf: detailed)
            }
        }
        return .unavailable
    }

    private static func inMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create an in-memory ModelContainer — this indicates a bug in the SwiftData schema: \(error)")
        }
    }
}
