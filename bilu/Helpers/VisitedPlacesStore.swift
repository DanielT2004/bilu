//
//  VisitedPlacesStore.swift
//  bilu
//
//  "I've been here" is independent of the Saved / Want-to-Go lists — a place
//  can be marked visited without ever being bookmarked — so it's tracked as
//  its own identity-key set rather than a SavedPlace field.
//

import Foundation

enum VisitedPlacesStore {
    private static let key = "visited.placeIdentityKeys"

    static func isVisited(_ identityKey: String, defaults: UserDefaults = .standard) -> Bool {
        visitedKeys(defaults: defaults).contains(identityKey)
    }

    static func toggle(_ identityKey: String, defaults: UserDefaults = .standard) -> Bool {
        var keys = visitedKeys(defaults: defaults)
        let nowVisited: Bool
        if keys.contains(identityKey) {
            keys.remove(identityKey)
            nowVisited = false
        } else {
            keys.insert(identityKey)
            nowVisited = true
        }
        defaults.set(Array(keys), forKey: key)
        return nowVisited
    }

    private static func visitedKeys(defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
