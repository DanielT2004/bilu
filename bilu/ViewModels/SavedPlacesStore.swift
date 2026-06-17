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

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Places

    func isSaved(_ rec: Recommendation, in list: SavedListType) -> Bool {
        existing(identityKey: rec.identityKey, list: list) != nil
    }

    /// Toggles a place in/out of a list. Fires haptics so the audio grammar has a
    /// single source — callers keep only their scale animation.
    func toggle(_ rec: Recommendation, list: SavedListType) {
        if let place = existing(identityKey: rec.identityKey, list: list) {
            context.delete(place)
            Haptics.soft()
        } else {
            context.insert(SavedPlace(from: rec, listType: list))
            Haptics.success()
        }
        save()
    }

    func add(_ rec: Recommendation, list: SavedListType) {
        guard existing(identityKey: rec.identityKey, list: list) == nil else { return }
        context.insert(SavedPlace(from: rec, listType: list))
        save()
    }

    func remove(_ place: SavedPlace) {
        context.delete(place)
        save()
    }

    /// Moves a place to another list (flips, never duplicates). If the destination
    /// already holds this place, the source is simply removed.
    func move(_ place: SavedPlace, to list: SavedListType) {
        guard place.listType != list else { return }
        if existing(identityKey: place.identityKey, list: list) != nil {
            context.delete(place)
        } else {
            place.listType = list
        }
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
            Haptics.success()
        }
        save()
    }

    // MARK: - Private

    private func existing(identityKey: String, list: SavedListType) -> SavedPlace? {
        let raw = list.rawValue
        var descriptor = FetchDescriptor<SavedPlace>(
            predicate: #Predicate { $0.identityKey == identityKey && $0.listTypeRaw == raw }
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

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("SavedPlacesStore save failed: \(error)")
        }
    }
}
