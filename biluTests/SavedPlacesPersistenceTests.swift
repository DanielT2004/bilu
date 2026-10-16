//
//  SavedPlacesPersistenceTests.swift
//  biluTests
//
//  Release gates "Profile and local data" (RELEASE_TEST_PLAN.md): duplicate saves,
//  Saved <-> Want to Go moves, deletions across relaunch, vibe dedupe, migration
//  from earlier builds' stores, preservation of a store that fails to open, and
//  the optional `SavedPlace.tags` field. Every test uses its own on-disk store in
//  a temp directory; "relaunch" means dropping the container and opening the same
//  files again through `PersistenceController.makeContainer(storeURL:)`.
//

import SwiftData
import XCTest
@testable import bilu

// MARK: - Earlier schemas (fixtures)

/// `SavedPlace`/`SavedVibe` as shipped from 82cd6d5 ("profile page") through
/// ccf6a56: no `parking`, no `tags`. Builds 1–3 (CURRENT_PROJECT_VERSION 1).
enum BuildOneSchema {
    @Model
    final class SavedPlace {
        @Attribute(.unique) var identityKey: String
        var name: String
        var dish: String
        var image: String?
        var explanation: String
        var mapsUrl: String
        var address: String?
        var phone: String?
        var website: String?
        var placeId: String?
        var latitude: Double?
        var longitude: Double?
        var rating: Double?
        var reviewCount: Int?
        var isOpen: Bool?
        var photos: [String]?
        var photoRefs: [String]?
        var listTypeRaw: String
        var dateSaved: Date

        init(identityKey: String, name: String, dish: String, placeId: String?, listTypeRaw: String, dateSaved: Date) {
            self.identityKey = identityKey
            self.name = name
            self.dish = dish
            self.image = "https://example.com/\(name).jpg"
            self.explanation = "Fixture \(name)"
            self.mapsUrl = "https://maps.google.com/?q=\(identityKey)"
            self.address = "1 Fixture Way"
            self.phone = "+1 555 0100"
            self.website = "https://example.com"
            self.placeId = placeId
            self.latitude = 34.05
            self.longitude = -118.24
            self.rating = 4.6
            self.reviewCount = 321
            self.isOpen = true
            self.photos = ["https://example.com/a.jpg", "https://example.com/b.jpg"]
            self.photoRefs = ["ref-a", "ref-b"]
            self.listTypeRaw = listTypeRaw
            self.dateSaved = dateSaved
        }
    }

    @Model
    final class SavedVibe {
        @Attribute(.unique) var id: UUID
        var encodedSelection: Data
        var summary: String
        var dateSaved: Date

        init(id: UUID, encodedSelection: Data, summary: String, dateSaved: Date) {
            self.id = id
            self.encodedSelection = encodedSelection
            self.summary = summary
            self.dateSaved = dateSaved
        }
    }

    static let schema = Schema([SavedPlace.self, SavedVibe.self])
}

/// `SavedPlace` as shipped from 2891b11 (build 4) up to this change: adds
/// `parking`, still no `tags`. `SavedVibe` is unchanged from build 1.
enum BuildFourSchema {
    @Model
    final class SavedPlace {
        @Attribute(.unique) var identityKey: String
        var name: String
        var dish: String
        var image: String?
        var explanation: String
        var mapsUrl: String
        var address: String?
        var phone: String?
        var website: String?
        var parking: String?
        var placeId: String?
        var latitude: Double?
        var longitude: Double?
        var rating: Double?
        var reviewCount: Int?
        var isOpen: Bool?
        var photos: [String]?
        var photoRefs: [String]?
        var listTypeRaw: String
        var dateSaved: Date

        init(identityKey: String, name: String, parking: String?, listTypeRaw: String, dateSaved: Date) {
            self.identityKey = identityKey
            self.name = name
            self.dish = "Dish of \(name)"
            self.image = nil
            self.explanation = "Fixture \(name)"
            self.mapsUrl = "https://maps.google.com/?q=\(identityKey)"
            self.address = nil
            self.phone = nil
            self.website = nil
            self.parking = parking
            self.placeId = identityKey
            self.latitude = nil
            self.longitude = nil
            self.rating = 4.2
            self.reviewCount = 12
            self.isOpen = nil
            self.photos = nil
            self.photoRefs = ["ref-\(identityKey)"]
            self.listTypeRaw = listTypeRaw
            self.dateSaved = dateSaved
        }
    }

    static let schema = Schema([SavedPlace.self, BuildOneSchema.SavedVibe.self])
}

/// A schema the current model can't migrate to (`rating` changes type), used to
/// force a real persistent-store open failure.
enum IncompatibleSchema {
    @Model
    final class SavedPlace {
        @Attribute(.unique) var identityKey: String
        var rating: String
        var listTypeRaw: String

        init(identityKey: String, rating: String, listTypeRaw: String) {
            self.identityKey = identityKey
            self.rating = rating
            self.listTypeRaw = listTypeRaw
        }
    }

    static let schema = Schema([SavedPlace.self, BuildOneSchema.SavedVibe.self])
}

// MARK: - Tests

@MainActor
final class SavedPlacesPersistenceTests: XCTestCase {
    private var directory: URL!
    private var storeURL: URL { directory.appendingPathComponent("bilu-test.store") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedPlacesPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Gate: no duplicate saves

    func testSavingSamePlaceTwiceKeepsOneRecord() throws {
        let (container, store) = try openStore()
        let rec = makeRecommendation(placeId: "place-1")

        store.add(rec, list: .saved)
        store.add(rec, list: .saved)
        // A re-fetched copy of the same place (different card copy, same placeId).
        store.add(makeRecommendation(name: "Renamed", placeId: "place-1"), list: .saved)

        XCTAssertEqual(try places(in: container).count, 1)
        XCTAssertTrue(store.isSaved(rec, in: .saved))
    }

    func testSavingToOtherListMovesInsteadOfDuplicating() throws {
        let (container, store) = try openStore()
        let rec = makeRecommendation(placeId: "place-1")

        store.toggle(rec, list: .saved)
        store.toggle(rec, list: .wantToGo)

        let all = try places(in: container)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.listType, .wantToGo)
        XCTAssertEqual(store.listType(of: rec), .wantToGo)
        XCTAssertFalse(store.isSaved(rec, in: .saved))
        XCTAssertTrue(store.isSaved(rec, in: .wantToGo))
    }

    func testDirectInsertOfDuplicateIdentityIsCollapsedByUniqueConstraint() throws {
        do {
            let container = try open()
            let context = container.mainContext
            context.insert(SavedPlace(from: makeRecommendation(placeId: "dup"), listType: .saved))
            try context.save()
            context.insert(SavedPlace(from: makeRecommendation(placeId: "dup"), listType: .saved))
            try context.save()
        }
        let reopened = try open()
        XCTAssertEqual(try places(in: reopened).count, 1)
    }

    // MARK: Gate: Saved <-> Want to Go moves

    func testMoveSavedToWantToGoAndBackUpdatesCountsImmediately() throws {
        let (container, store) = try openStore()
        store.add(makeRecommendation(placeId: "a"), list: .saved)
        store.add(makeRecommendation(placeId: "b"), list: .saved)
        let a = try XCTUnwrap(try places(in: container).first { $0.identityKey == "a" })

        store.move(a, to: .wantToGo)
        XCTAssertEqual(try count(.saved, in: container), 1)
        XCTAssertEqual(try count(.wantToGo, in: container), 1)

        store.move(a, to: .saved)
        XCTAssertEqual(try count(.saved, in: container), 2)
        XCTAssertEqual(try count(.wantToGo, in: container), 0)
        XCTAssertEqual(try places(in: container).count, 2)
    }

    func testMoveSurvivesRelaunch() throws {
        do {
            let (container, store) = try openStore()
            store.add(makeRecommendation(placeId: "a"), list: .saved)
            let a = try XCTUnwrap(try places(in: container).first)
            store.move(a, to: .wantToGo)
        }
        let reopened = try open()
        XCTAssertEqual(try count(.wantToGo, in: reopened), 1)
        XCTAssertEqual(try count(.saved, in: reopened), 0)
    }

    // MARK: Gate: deletions survive relaunch

    func testDeletionsSurviveRelaunch() throws {
        do {
            let (container, store) = try openStore()
            store.add(makeRecommendation(placeId: "keep"), list: .saved)
            store.add(makeRecommendation(placeId: "removed-from-profile"), list: .saved)
            store.add(makeRecommendation(placeId: "unbookmarked"), list: .wantToGo)
            store.toggleVibe(VibeSelection(occasion: "Dinner", foodFeelings: ["Handheld"]))

            // Profile context-menu "Remove".
            let removed = try XCTUnwrap(try places(in: container).first { $0.identityKey == "removed-from-profile" })
            store.remove(removed)
            // Detail-sheet toggle off.
            store.toggle(makeRecommendation(placeId: "unbookmarked"), list: .wantToGo)
            // Saved-vibe toggle off.
            store.toggleVibe(VibeSelection(occasion: "Dinner", foodFeelings: ["Handheld"]))
        }

        let (reopened, store) = try openStore()
        XCTAssertEqual(try places(in: reopened).map(\.identityKey), ["keep"])
        XCTAssertTrue(store.savedVibeSelections().isEmpty)
    }

    // MARK: Gate: vibe dedupe regardless of order

    func testEquivalentVibeWithReorderedCategoriesIsNotSavedTwice() throws {
        let original = VibeSelection(
            occasion: "Sit Down",
            keyQuestionAnswer: "Best quality nearby",
            foodFeelings: ["Handheld", "Fresh & light", "Noodles"],
            selectedSubOptions: ["Handheld": ["Taco", "Burger"], "Noodles": ["Ramen", "Pho"]],
            location: "Los Angeles"
        )
        var reordered = original
        reordered.foodFeelings = ["Noodles", "Handheld", "Fresh & light"]
        reordered.selectedSubOptions = ["Noodles": ["Pho", "Ramen"], "Handheld": ["Burger", "Taco"], "Sweet": []]
        reordered.partySize = 6

        do {
            let (container, store) = try openStore()
            // SwiftData models need their container alive; the app holds it for its lifetime.
            defer { withExtendedLifetime(container) {} }
            store.toggleVibe(original)
            XCTAssertTrue(store.isVibeSaved(reordered))
            XCTAssertEqual(store.savedVibeSelections().count, 1)
        }

        // Still matched after relaunch, i.e. against the decoded stored JSON.
        let (container, store) = try openStore()
        // SwiftData models need their container alive; the app holds it for its lifetime.
        defer { withExtendedLifetime(container) {} }
        XCTAssertTrue(store.isVibeSaved(reordered))
        XCTAssertEqual(store.savedVibeSelections().count, 1)
        // Tapping save on the equivalent vibe un-saves it rather than adding a twin.
        store.toggleVibe(reordered)
        XCTAssertEqual(store.savedVibeSelections().count, 0)
    }

    func testVibesWithDifferentSubOptionsAreDistinct() throws {
        let (container, store) = try openStore()
        // SwiftData models need their container alive; the app holds it for its lifetime.
        defer { withExtendedLifetime(container) {} }
        let tacos = VibeSelection(occasion: "Casual", foodFeelings: ["Handheld"], selectedSubOptions: ["Handheld": ["Taco"]])
        var burgers = tacos
        burgers.selectedSubOptions = ["Handheld": ["Burger"]]

        store.toggleVibe(tacos)
        XCTAssertFalse(store.isVibeSaved(burgers))
        store.toggleVibe(burgers)
        XCTAssertEqual(store.savedVibeSelections().count, 2)
    }

    // MARK: Gate: migration from earlier builds' stores

    func testBuildOneStoreMigratesWithEverySaveIntact() throws {
        let saved = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T18:30:00Z"))
        let vibeID = UUID()
        let vibe = VibeSelection(occasion: "Date Night", foodFeelings: ["Pasta"], location: "Pasadena")
        do {
            let legacy = try ModelContainer(for: BuildOneSchema.schema, configurations: [config(BuildOneSchema.schema)])
            let context = ModelContext(legacy)
            context.insert(BuildOneSchema.SavedPlace(
                identityKey: "gp-123", name: "Bestia", dish: "Bone marrow", placeId: "gp-123",
                listTypeRaw: "saved", dateSaved: saved
            ))
            context.insert(BuildOneSchema.SavedPlace(
                identityKey: "Night + MarketKhao soi", name: "Night + Market", dish: "Khao soi", placeId: nil,
                listTypeRaw: "wantToGo", dateSaved: saved
            ))
            context.insert(BuildOneSchema.SavedVibe(
                id: vibeID, encodedSelection: try JSONEncoder().encode(vibe),
                summary: "Date Night · Pasta · Pasadena", dateSaved: saved
            ))
            try context.save()
        }

        let (container, store) = try openStore()
        let all = try places(in: container).sorted { $0.identityKey < $1.identityKey }
        XCTAssertEqual(all.map(\.identityKey), ["Night + MarketKhao soi", "gp-123"])

        let bestia = try XCTUnwrap(all.last)
        XCTAssertEqual(bestia.name, "Bestia")
        XCTAssertEqual(bestia.dish, "Bone marrow")
        XCTAssertEqual(bestia.image, "https://example.com/Bestia.jpg")
        XCTAssertEqual(bestia.explanation, "Fixture Bestia")
        XCTAssertEqual(bestia.mapsUrl, "https://maps.google.com/?q=gp-123")
        XCTAssertEqual(bestia.address, "1 Fixture Way")
        XCTAssertEqual(bestia.phone, "+1 555 0100")
        XCTAssertEqual(bestia.website, "https://example.com")
        XCTAssertEqual(bestia.placeId, "gp-123")
        XCTAssertEqual(bestia.latitude, 34.05)
        XCTAssertEqual(bestia.longitude, -118.24)
        XCTAssertEqual(bestia.rating, 4.6)
        XCTAssertEqual(bestia.reviewCount, 321)
        XCTAssertEqual(bestia.isOpen, true)
        XCTAssertEqual(bestia.photos, ["https://example.com/a.jpg", "https://example.com/b.jpg"])
        XCTAssertEqual(bestia.photoRefs, ["ref-a", "ref-b"])
        XCTAssertEqual(bestia.listType, .saved)
        XCTAssertEqual(bestia.dateSaved, saved)
        XCTAssertNil(bestia.parking)
        XCTAssertNil(bestia.tags)
        XCTAssertEqual(all.first?.listType, .wantToGo)
        XCTAssertNil(all.first?.tags)

        let vibes = try container.mainContext.fetch(FetchDescriptor<SavedVibe>())
        XCTAssertEqual(vibes.map(\.id), [vibeID])
        XCTAssertEqual(vibes.first?.summary, "Date Night · Pasta · Pasadena")
        XCTAssertTrue(try XCTUnwrap(vibes.first?.selection).matches(vibe))

        // The migrated store is fully usable: identity checks, moves and new tags.
        XCTAssertTrue(store.isSaved(bestia.asRecommendation, in: .saved))
        store.toggle(bestia.asRecommendation, list: .wantToGo, tags: ["Italian"])
        XCTAssertEqual(try places(in: container).count, 2)
    }

    /// Owner decision B: a store written without `tags` opens unchanged and its
    /// existing places read `tags == nil`.
    func testStoreWithoutTagsOpensUnchangedAndReadsNilTags() throws {
        let saved = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T09:00:00Z"))
        do {
            let legacy = try ModelContainer(for: BuildFourSchema.schema, configurations: [config(BuildFourSchema.schema)])
            let context = ModelContext(legacy)
            context.insert(BuildFourSchema.SavedPlace(identityKey: "p1", name: "Kato", parking: "Valet", listTypeRaw: "saved", dateSaved: saved))
            context.insert(BuildFourSchema.SavedPlace(identityKey: "p2", name: "Holbox", parking: nil, listTypeRaw: "wantToGo", dateSaved: saved))
            try context.save()
        }

        do {
            let (container, store) = try openStore()
            let all = try places(in: container).sorted { $0.identityKey < $1.identityKey }
            XCTAssertEqual(all.map(\.name), ["Kato", "Holbox"])
            XCTAssertEqual(all.map(\.parking), ["Valet", nil])
            XCTAssertEqual(all.map(\.listType), [.saved, .wantToGo])
            XCTAssertEqual(all.map(\.dateSaved), [saved, saved])
            XCTAssertEqual(all.map(\.photoRefs), [["ref-p1"], ["ref-p2"]])
            XCTAssertTrue(all.allSatisfy { $0.tags == nil })

            // Tagging a migrated place persists.
            XCTAssertTrue(store.addTags(["Japanese", "Tasting menu"], to: try XCTUnwrap(all.first).asRecommendation))
        }

        let reopened = try open()
        let all = try places(in: reopened).sorted { $0.identityKey < $1.identityKey }
        XCTAssertEqual(all.first?.tags, ["Japanese", "Tasting menu"])
        XCTAssertNil(all.last?.tags)
    }

    // MARK: Gate: a store that fails to open is preserved

    func testUnreadableStoreFileIsPreservedAndAppFallsBackToMemory() throws {
        let garbage = Data("this is not a sqlite database".utf8)
        try garbage.write(to: storeURL)

        let container = PersistenceController.makeContainer(storeURL: storeURL)

        XCTAssertEqual(container.configurations.first?.isStoredInMemoryOnly, true)
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage)
        // The degraded session still works; it just isn't written to the bad store.
        let store = SavedPlacesStore(context: container.mainContext)
        store.add(makeRecommendation(placeId: "temp"), list: .saved)
        XCTAssertEqual(try places(in: container).count, 1)
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage)
    }

    func testStoreThatCannotMigrateIsPreservedWithItsData() throws {
        do {
            let legacy = try ModelContainer(for: IncompatibleSchema.schema, configurations: [config(IncompatibleSchema.schema)])
            let context = ModelContext(legacy)
            context.insert(IncompatibleSchema.SavedPlace(identityKey: "keep-me", rating: "great", listTypeRaw: "saved"))
            try context.save()
        }
        let filesBefore = try storeFiles()
        XCTAssertFalse(filesBefore.isEmpty)

        do {
            let container = PersistenceController.makeContainer(storeURL: storeURL)
            XCTAssertEqual(container.configurations.first?.isStoredInMemoryOnly, true)
            let store = SavedPlacesStore(context: container.mainContext)
            store.add(makeRecommendation(placeId: "temp"), list: .saved)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        // The original rows are still readable with the schema that wrote them.
        let legacy = try ModelContainer(for: IncompatibleSchema.schema, configurations: [config(IncompatibleSchema.schema)])
        let rows = try ModelContext(legacy).fetch(FetchDescriptor<IncompatibleSchema.SavedPlace>())
        XCTAssertEqual(rows.map(\.identityKey), ["keep-me"])
        XCTAssertEqual(rows.first?.rating, "great")
    }

    // MARK: Degraded state is reported, never hidden

    func testHealthyStoreReportsPersistentStatus() throws {
        let opened = PersistenceController.open(storeURL: storeURL)
        XCTAssertEqual(opened.status, .persistent)
        XCTAssertTrue(opened.status.isPersistent)
        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, false)

        let store = SavedPlacesStore(context: opened.container.mainContext, persistenceStatus: opened.status)
        XCTAssertFalse(store.savesAreTemporary)
        XCTAssertNil(store.temporarySaveReason)
    }

    func testUnreadableStoreReportsTemporaryStatusAndStoreExposesIt() throws {
        let garbage = Data("this is not a sqlite database".utf8)
        try garbage.write(to: storeURL)

        let opened = PersistenceController.open(storeURL: storeURL)

        XCTAssertEqual(opened.status, .temporary(.unavailable))
        XCTAssertFalse(opened.status.isPersistent)
        XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, true)
        let store = SavedPlacesStore(context: opened.container.mainContext, persistenceStatus: opened.status)
        XCTAssertTrue(store.savesAreTemporary)
        XCTAssertEqual(store.temporarySaveReason, .unavailable)
        // Saving still works for the session and the bad file is untouched.
        store.add(makeRecommendation(placeId: "session-only"), list: .wantToGo)
        XCTAssertEqual(try places(in: opened.container).count, 1)
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage)
    }

    func testStoreThatCannotMigrateReportsTemporaryStatus() throws {
        do {
            let legacy = try ModelContainer(for: IncompatibleSchema.schema, configurations: [config(IncompatibleSchema.schema)])
            let context = ModelContext(legacy)
            context.insert(IncompatibleSchema.SavedPlace(identityKey: "keep-me", rating: "great", listTypeRaw: "saved"))
            try context.save()
        }
        XCTAssertFalse(PersistenceController.open(storeURL: storeURL).status.isPersistent)
    }

    func testSimulatedFailureUsesMemoryAndLeavesRealStoreAlone() throws {
        do {
            let (container, store) = try openStore()
            defer { withExtendedLifetime(container) {} }
            store.add(makeRecommendation(placeId: "real"), list: .saved)
        }
        let filesBefore = try storeFiles()

        do {
            let opened = PersistenceController.open(storeURL: storeURL, simulateFailure: true)
            XCTAssertEqual(opened.status, .temporary(.unavailable))
            XCTAssertEqual(opened.container.configurations.first?.isStoredInMemoryOnly, true)
            XCTAssertTrue(try places(in: opened.container).isEmpty)
            SavedPlacesStore(context: opened.container.mainContext, persistenceStatus: opened.status)
                .add(makeRecommendation(placeId: "temp"), list: .saved)
        }

        XCTAssertEqual(try storeFiles(), filesBefore)
        // Keep the container alive while reading the fetched models.
        let reopened = try open()
        XCTAssertEqual(try places(in: reopened).map(\.identityKey), ["real"])
    }

    func testStoreDefaultsToPersistent() throws {
        let container = PersistenceController.previewContainer()
        XCTAssertFalse(SavedPlacesStore(context: container.mainContext).savesAreTemporary)
    }

    func testOutOfSpaceErrorsAreReportedAsLowStorage() {
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let wrapped = NSError(domain: "SwiftData.SwiftDataError", code: 1, userInfo: [NSUnderlyingErrorKey: cocoa])
        let sqliteFull = NSError(domain: "NSSQLiteErrorDomain", code: 13)
        let coreDataWithSQLite = NSError(domain: NSCocoaErrorDomain, code: 134_030, userInfo: ["NSSQLiteErrorDomain": 13])
        let detailed = NSError(domain: NSCocoaErrorDomain, code: 1560, userInfo: ["NSDetailedErrors": [sqliteFull]])
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))

        for error in [cocoa, wrapped, sqliteFull, coreDataWithSQLite, detailed, posix] {
            XCTAssertEqual(PersistenceController.failureReason(for: error), .lowStorage, "\(error)")
        }
        let corrupt = NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError)
        let migration = NSError(domain: NSCocoaErrorDomain, code: 134_110)
        XCTAssertEqual(PersistenceController.failureReason(for: corrupt), .unavailable)
        XCTAssertEqual(PersistenceController.failureReason(for: migration), .unavailable)
    }

    // MARK: Owner decision B: tags

    func testTasteTagsComeFromFoodFeelingsAndSubOptions() {
        let selection = VibeSelection(
            occasion: "Casual",
            foodFeelings: ["Handheld", "Surprise me", "Noodles"],
            selectedSubOptions: ["Noodles": ["Ramen"], "Handheld": ["Taco", "Burger"], "Sweet": ["Boba"], "Rice": []]
        )
        XCTAssertEqual(selection.tasteTags, ["Handheld", "Taco", "Burger", "Noodles", "Ramen", "Boba"])
        XCTAssertEqual(VibeSelection(foodFeelings: ["Surprise me"]).tasteTags, [])
    }

    func testTagsAreNormalized() {
        XCTAssertEqual(SavedPlace.normalizedTags([" Korean ", "korean", "", "BBQ", "  "]), ["Korean", "BBQ"])
        XCTAssertNil(SavedPlace.normalizedTags([" ", ""]))
        XCTAssertNil(SavedPlace.normalizedTags(nil))
    }

    func testSavingWithTagsPersistsAndMergesAcrossSaves() throws {
        let rec = makeRecommendation(placeId: "tagged")
        do {
            let (container, store) = try openStore()
            // SwiftData models need their container alive; the app holds it for its lifetime.
            defer { withExtendedLifetime(container) {} }
            store.toggle(rec, list: .saved, tags: ["Handheld", "Taco"])
            // A later save from elsewhere (e.g. a TikTok share) adds, never drops, tags
            // and doesn't move the place out of the list the user picked.
            let place = store.add(rec, list: .wantToGo, tags: ["taco", "Mexican"])
            XCTAssertEqual(place.listType, .saved)
            // Moving via the other list's toggle keeps and merges tags too.
            store.toggle(rec, list: .wantToGo, tags: ["Late night"])
        }

        let reopened = try open()
        let place = try XCTUnwrap(try places(in: reopened).first)
        XCTAssertEqual(place.tags, ["Handheld", "Taco", "Mexican", "Late night"])
        XCTAssertEqual(place.listType, .wantToGo)
    }

    func testSavingWithoutTagsLeavesTagsNil() throws {
        let (container, store) = try openStore()
        store.toggle(makeRecommendation(placeId: "plain"), list: .saved)
        store.add(makeRecommendation(placeId: "empty"), list: .saved, tags: [])
        XCTAssertTrue(try places(in: container).allSatisfy { $0.tags == nil })
        XCTAssertFalse(store.addTags(["x"], to: makeRecommendation(placeId: "not-saved")))
    }

    // MARK: - Helpers

    private func config(_ schema: Schema) -> ModelConfiguration {
        ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    }

    /// Opens the store exactly as the app does at launch and requires that it
    /// really is the on-disk store (not the in-memory fallback).
    private func open() throws -> ModelContainer {
        let container = PersistenceController.makeContainer(storeURL: storeURL)
        XCTAssertEqual(container.configurations.first?.isStoredInMemoryOnly, false, "Store fell back to memory")
        XCTAssertEqual(container.configurations.first?.url.standardizedFileURL, storeURL.standardizedFileURL)
        return container
    }

    private func openStore() throws -> (ModelContainer, SavedPlacesStore) {
        let container = try open()
        return (container, SavedPlacesStore(context: container.mainContext))
    }

    private func places(in container: ModelContainer) throws -> [SavedPlace] {
        try container.mainContext.fetch(FetchDescriptor<SavedPlace>())
    }

    /// Mirrors the Profile's per-list `@Query`.
    private func count(_ list: SavedListType, in container: ModelContainer) throws -> Int {
        let raw = list.rawValue
        return try container.mainContext.fetchCount(
            FetchDescriptor<SavedPlace>(predicate: #Predicate { $0.listTypeRaw == raw })
        )
    }

    private func storeFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(storeURL.lastPathComponent) }
    }

    private func makeRecommendation(name: String = "Test Kitchen", placeId: String? = nil) -> Recommendation {
        Recommendation(
            name: name,
            dish: "House Special",
            image: nil,
            explanation: "A test recommendation.",
            mapsUrl: "https://maps.google.com",
            latitude: 34.05,
            longitude: -118.24,
            rating: 4.7,
            reviewCount: 120,
            isOpen: true,
            photos: nil,
            address: "123 Test Street",
            phone: nil,
            website: nil,
            parking: nil,
            placeId: placeId,
            photoRefs: nil,
            reviews: nil
        )
    }
}
