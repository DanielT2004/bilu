//
//  ProfileStorage.swift
//  bilu
//
//  Lightweight, single-row profile identity + dietary preferences.
//  Stored in UserDefaults via @AppStorage (see ProfileViewModel) — a SwiftData
//  singleton would force fetch-or-create on every read for a fixed handful of values.
//

import Foundation

/// UserDefaults keys for the local profile. Centralized so the migration anchor
/// (`userId`) and the editable fields share one source of truth.
enum ProfileStorageKey {
    static let displayName = "profile.displayName"
    static let avatarEmoji = "profile.avatarEmoji"
    static let dietary     = "profile.dietary"      // comma-joined DietaryPreference rawValues
    static let userId      = "profile.userId"       // migration anchor — UUID string

    static let defaultAvatar = "🍜"
}

/// Curated avatar emoji the user can pick from in EditProfileView.
enum ProfileAvatar {
    static let options = [
        "🍜", "🌮", "🍕", "🍣", "🥗", "🍔", "🍦", "🥐",
        "🌶️", "🍙", "🥘", "🍩", "🍤", "🧋", "🥟", "🍷"
    ]
}

/// A dietary constraint the user can set. Stored locally now; a future build can
/// thread these into the search prompt via PromptBuilder (see plan §8).
enum DietaryPreference: String, CaseIterable, Identifiable {
    case halal
    case vegetarian
    case vegan
    case glutenFree
    case dairyFree
    case nutFree
    case pescatarian
    case kosher

    var id: String { rawValue }

    var label: String {
        switch self {
        case .halal:       return "Halal"
        case .vegetarian:  return "Vegetarian"
        case .vegan:       return "Vegan"
        case .glutenFree:  return "Gluten-free"
        case .dairyFree:   return "Dairy-free"
        case .nutFree:     return "Nut-free"
        case .pescatarian: return "Pescatarian"
        case .kosher:      return "Kosher"
        }
    }

    var emoji: String {
        switch self {
        case .halal:       return "🕌"
        case .vegetarian:  return "🥦"
        case .vegan:       return "🌱"
        case .glutenFree:  return "🌾"
        case .dairyFree:   return "🥛"
        case .nutFree:     return "🥜"
        case .pescatarian: return "🐟"
        case .kosher:      return "✡️"
        }
    }
}

extension DietaryPreference {
    /// Encode a set to the comma-joined string stored in UserDefaults.
    static func encode(_ prefs: Set<DietaryPreference>) -> String {
        prefs.map(\.rawValue).sorted().joined(separator: ",")
    }

    /// Decode the comma-joined string back to a set.
    static func decode(_ raw: String) -> Set<DietaryPreference> {
        Set(raw.split(separator: ",").compactMap { DietaryPreference(rawValue: String($0)) })
    }
}
