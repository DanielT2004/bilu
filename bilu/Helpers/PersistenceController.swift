//
//  PersistenceController.swift
//  bilu
//
//  Single place that builds the SwiftData ModelContainer. A bare `try!` here
//  would hard-crash the app on every launch if the on-disk store is ever
//  corrupted or a schema migration fails — this recovers by resetting the
//  store once instead of crash-looping the user forever.
//

import Foundation
import SwiftData

enum PersistenceController {
    static let schema = Schema([SavedPlace.self, SavedVibe.self])

    /// The real, persisted container used at app launch.
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema)
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        // Store is corrupted or the schema migration failed — remove the store
        // and start fresh rather than crashing on every future launch too.
        if let storeURL = config.url as URL?, storeURL.isFileURL {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: storeURL.path + suffix)
            }
        }
        if let container = try? ModelContainer(for: schema, configurations: [config]) {
            return container
        }

        // Environment can't support on-disk persistence at all (e.g. disk full,
        // sandbox permissions). Fall back to in-memory so the app still launches
        // in a degraded state instead of hard-crashing.
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
