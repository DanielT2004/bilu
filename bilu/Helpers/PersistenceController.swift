//
//  PersistenceController.swift
//  bilu
//
//  Single place that builds the SwiftData ModelContainer. A persistent-store
//  failure must never erase the user's saved places. The original store stays
//  untouched while the app falls back to a temporary in-memory container.
//

import Foundation
import OSLog
import SwiftData

enum PersistenceController {
    static let schema = Schema([SavedPlace.self, SavedVibe.self])
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.simonsoloman.bilu",
        category: "Persistence"
    )

    /// The real, persisted container used at app launch.
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return container
        } catch {
            logger.fault(
                "Persistent store could not be opened; preserving it and using an in-memory fallback. Error: \(error.localizedDescription, privacy: .public)"
            )
        }

        // The persistent files remain in place for recovery by a future app update.
        // Saves made during this degraded session are intentionally temporary so a
        // second database never diverges from the preserved source of truth.
        guard let inMemory = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        ) else {
            fatalError("Could not create even an in-memory ModelContainer — this indicates a bug in the SwiftData schema.")
        }
        return inMemory
    }

    /// In-memory container for #Preview — can only fail from a schema-definition
    /// bug (a programmer error, not a runtime condition), so fatalError is correct here.
    static func previewContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Preview ModelContainer failed — this indicates a bug in the SwiftData schema: \(error)")
        }
    }
}
