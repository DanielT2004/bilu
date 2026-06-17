//
//  ProfileViewModel.swift
//  bilu
//
//  Owns the editable identity + dietary preferences (backed by UserDefaults) and
//  the edit-sheet state. The saved-place / saved-vibe lists are NOT here — Views
//  read those live via @Query so they update the instant the store mutates.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var displayName: String
    @Published var avatarEmoji: String
    @Published var dietary: Set<DietaryPreference>

    @Published var showingEditProfile = false
    @Published var showingDietaryEditor = false

    /// Draft fields for the edit sheet so edits can be cancelled without committing.
    @Published var draftName: String = ""
    @Published var draftAvatar: String = ProfileStorageKey.defaultAvatar

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.displayName = defaults.string(forKey: ProfileStorageKey.displayName) ?? ""
        self.avatarEmoji = defaults.string(forKey: ProfileStorageKey.avatarEmoji) ?? ProfileStorageKey.defaultAvatar
        self.dietary = DietaryPreference.decode(defaults.string(forKey: ProfileStorageKey.dietary) ?? "")
        ensureUserId()
    }

    // MARK: - Identity

    /// A stable per-install id, generated once. Migration anchor for a future
    /// cloud backend so local saves can be attached to a real account.
    var userId: String {
        defaults.string(forKey: ProfileStorageKey.userId) ?? ""
    }

    private func ensureUserId() {
        if defaults.string(forKey: ProfileStorageKey.userId) == nil {
            defaults.set(UUID().uuidString, forKey: ProfileStorageKey.userId)
        }
    }

    var hasName: Bool { !displayName.trimmingCharacters(in: .whitespaces).isEmpty }

    /// A playful @handle derived from the name (or a friendly default).
    var handle: String {
        let base = displayName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !base.isEmpty else { return "@food.explorer" }
        let slug = base.replacingOccurrences(of: " ", with: ".")
            .filter { $0.isLetter || $0.isNumber || $0 == "." }
        return "@\(slug)"
    }

    // MARK: - Edit profile flow

    func beginEditProfile() {
        draftName = displayName
        draftAvatar = avatarEmoji
        showingEditProfile = true
    }

    func commitProfile() {
        displayName = draftName.trimmingCharacters(in: .whitespaces)
        avatarEmoji = draftAvatar
        defaults.set(displayName, forKey: ProfileStorageKey.displayName)
        defaults.set(avatarEmoji, forKey: ProfileStorageKey.avatarEmoji)
        Haptics.success()
        showingEditProfile = false
    }

    // MARK: - Dietary

    func toggleDietary(_ pref: DietaryPreference) {
        if dietary.contains(pref) {
            dietary.remove(pref)
        } else {
            dietary.insert(pref)
        }
        defaults.set(DietaryPreference.encode(dietary), forKey: ProfileStorageKey.dietary)
        Haptics.light()
    }

    var dietarySummary: String {
        guard !dietary.isEmpty else { return "None set" }
        return dietary.sorted { $0.label < $1.label }.map(\.label).joined(separator: " · ")
    }
}

/// Shared cuisine heuristic — derives a cuisine label from a place's dish + blurb.
/// Mirrors the logic in RecommendationCard so the Profile's "cuisines explored"
/// stat and the card stay consistent. Returns nil when nothing matches.
enum CuisineClassifier {
    static func cuisine(dish: String, explanation: String) -> String? {
        let text = (dish + " " + explanation).lowercased()
        if text.contains("italian") || text.contains("pasta") || text.contains("pizza") { return "Italian" }
        if text.contains("mexican") || text.contains("taco") || text.contains("burrito") { return "Mexican" }
        if text.contains("japanese") || text.contains("sushi") || text.contains("ramen") { return "Japanese" }
        if text.contains("thai") { return "Thai" }
        if text.contains("indian") { return "Indian" }
        if text.contains("chinese") { return "Chinese" }
        if text.contains("american") || text.contains("burger") || text.contains("bbq") { return "American" }
        if text.contains("french") || text.contains("bistro") || text.contains("brasserie") { return "French" }
        if text.contains("mediterranean") || text.contains("greek") { return "Mediterranean" }
        if text.contains("farm") || text.contains("organic") { return "Farm-to-Table" }
        if text.contains("bakery") || text.contains("pastry") || text.contains("coffee") { return "Café & Bakery" }
        return nil
    }

    /// Distinct cuisine count across a set of saved places.
    static func distinctCount(in places: [SavedPlace]) -> Int {
        Set(places.compactMap { cuisine(dish: $0.dish, explanation: $0.explanation) }).count
    }
}
