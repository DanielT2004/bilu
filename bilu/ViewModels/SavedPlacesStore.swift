//
//  SavedPlacesStore.swift
//  bilu
//
//  The single place that mutates saved places + vibes. Views read live lists via
//  @Query; every write and membership check routes through here so the bookmark
//  button, the save-vibe action, and the Profile screen share one implementation.
//  This is also the seam for a future cloud (Supabase) backend — swap the internals
//  without touching any view.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class SavedPlacesStore: ObservableObject {
    private let context: ModelContext
    /// Whether saves survive a relaunch. When the on-disk store couldn't open,
    /// saving still works for this session, but views must say it won't be kept.
    let persistenceStatus: PersistenceStatus

    init(context: ModelContext, persistenceStatus: PersistenceStatus = .persistent) {
        self.context = context
        self.persistenceStatus = persistenceStatus
    }

    /// True when saves only last until the app closes.
    var savesAreTemporary: Bool { !persistenceStatus.isPersistent }

    /// Why saves are temporary, or `nil` when they're kept.
    var temporarySaveReason: PersistenceFailureReason? {
        if case .temporary(let reason) = persistenceStatus { return reason }
        return nil
    }

    // MARK: - Places

    func isSaved(_ rec: Recommendation, in list: SavedListType) -> Bool {
        listType(of: rec) == list
    }

    /// The list a place currently lives in, or `nil` when it isn't saved. A place
    /// is in at most one list: `identityKey` is unique across both.
    func listType(of rec: Recommendation) -> SavedListType? {
        existing(identityKey: rec.identityKey)?.listType
    }

    /// Toggles a place in/out of a list. If the place is already in the other list
    /// it moves here (one record per place, never two). `tags` are merged into the
    /// record when it's added or moved; removing ignores them. Fires haptics so the
    /// audio grammar has a single source — callers keep only their scale animation.
    /// A temporary (unkept) save gets a light tap, never the success pulse.
    func toggle(_ rec: Recommendation, list: SavedListType, tags: [String]? = nil) {
        if let place = existing(identityKey: rec.identityKey) {
            if place.listType == list {
                context.delete(place)
                Haptics.soft()
            } else {
                place.listType = list
                place.mergeTags(tags)
                saveHaptic()
            }
        } else {
            context.insert(SavedPlace(from: rec, listType: list, tags: tags))
            saveHaptic()
        }
        save()
    }

    /// Saves a place into `list` without haptics — the entry point for non-UI
    /// callers (e.g. resolved TikTok shares). Idempotent: if the place is already
    /// saved it stays in its current list and only gains the new tags, so a share
    /// never silently moves a place the user filed elsewhere.
    @discardableResult
    func add(_ rec: Recommendation, list: SavedListType, tags: [String]? = nil) -> SavedPlace {
        if let place = existing(identityKey: rec.identityKey) {
            place.mergeTags(tags)
            save()
            return place
        }
        let place = SavedPlace(from: rec, listType: list, tags: tags)
        context.insert(place)
        save()
        return place
    }

    /// Adds tags to an already-saved place. Returns false when the place isn't saved.
    @discardableResult
    func addTags(_ tags: [String], to rec: Recommendation) -> Bool {
        guard let place = existing(identityKey: rec.identityKey) else { return false }
        place.mergeTags(tags)
        save()
        return true
    }

    func remove(_ place: SavedPlace) {
        context.delete(place)
        save()
    }

    /// Moves a place to another list by flipping its list field — the same record,
    /// so it can never duplicate (`identityKey` is unique across both lists).
    func move(_ place: SavedPlace, to list: SavedListType) {
        guard place.listType != list else { return }
        place.listType = list
        Haptics.light()
        save()
    }

    // MARK: - Vibes

    func isVibeSaved(_ selection: VibeSelection) -> Bool {
        savedVibeMatching(selection) != nil
    }

    /// All saved vibe selections, newest first. Used to hydrate HomeViewModel.
    func savedVibeSelections() -> [VibeSelection] {
        var descriptor = FetchDescriptor<SavedVibe>(sortBy: [SortDescriptor(\.dateSaved, order: .reverse)])
        descriptor.includePendingChanges = true
        let vibes = (try? context.fetch(descriptor)) ?? []
        return vibes.compactMap { $0.selection }
    }

    func toggleVibe(_ selection: VibeSelection) {
        if let vibe = savedVibeMatching(selection) {
            context.delete(vibe)
            Haptics.soft()
        } else {
            context.insert(SavedVibe(selection: selection, summary: selection.shortSummary))
            saveHaptic()
        }
        save()
    }

    // MARK: - Private

    private func existing(identityKey: String) -> SavedPlace? {
        var descriptor = FetchDescriptor<SavedPlace>(
            predicate: #Predicate { $0.identityKey == identityKey }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Vibes are matched by user-meaning (VibeSelection.matches), not by stored bytes,
    /// so an equivalent vibe doesn't save twice. Fetches all and compares in memory —
    /// the saved-vibe set is small.
    private func savedVibeMatching(_ selection: VibeSelection) -> SavedVibe? {
        let all = (try? context.fetch(FetchDescriptor<SavedVibe>())) ?? []
        return all.first { $0.selection?.matches(selection) == true }
    }

    private func saveHaptic() {
        if savesAreTemporary { Haptics.light() } else { Haptics.success() }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("SavedPlacesStore save failed: \(error)")
        }
    }
}
