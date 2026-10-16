//
//  CuisineLabel.swift
//  bilu
//
//  One short cuisine label ("Mexican", "Japanese", "Café & Bakery") for a
//  place, shared by result cards and feed cards. Uses only what's already on
//  the device (tags, name, dish, description); never a network call. Returns
//  nil rather than guessing when nothing matches.
//

import Foundation

enum CuisineLabel {
    /// Ordered: earlier rows win, so a "sushi burrito" reads as Japanese and a
    /// "pizza café" as Italian.
    private static let table: [(label: String, keywords: [String])] = [
        ("Japanese", ["japanese", "sushi", "ramen", "udon", "izakaya", "omakase", "yakitori", "tonkatsu", "donburi"]),
        ("Korean", ["korean", "kbbq", "bibimbap", "bulgogi", "tteok", "soondubu"]),
        ("Chinese", ["chinese", "dim sum", "dumpling", "szechuan", "sichuan", "hot pot", "cantonese", "bao"]),
        ("Thai", ["thai", "pad thai", "khao soi", "tom yum"]),
        ("Vietnamese", ["vietnamese", "pho", "banh mi", "bún"]),
        ("Indian", ["indian", "curry", "tandoor", "biryani", "masala", "dosa"]),
        ("Mexican", ["mexican", "taco", "taquer", "burrito", "birria", "elote", "quesadilla", "mole", "al pastor"]),
        ("Italian", ["italian", "pizza", "pizzeria", "pasta", "trattoria", "risotto", "gelato"]),
        ("Mediterranean", ["mediterranean", "greek", "falafel", "shawarma", "gyro", "mezze", "hummus", "lebanese"]),
        ("French", ["french", "bistro", "brasserie", "crêpe", "crepe"]),
        ("Seafood", ["seafood", "oyster", "lobster", "crab", "poke", "fish"]),
        ("American", ["american", "burger", "bbq", "barbecue", "smokehouse", "fried chicken", "diner", "wings"]),
        ("Café & Bakery", ["bakery", "pastry", "pastries", "croissant", "café", "cafe", "coffee", "espresso", "matcha"]),
        ("Dessert", ["dessert", "ice cream", "donut", "doughnut", "boba", "cake", "cookie"]),
        ("Bar", ["cocktail", "wine bar", "brewery", "taproom", "speakeasy"]),
    ]

    static var allLabels: [String] { table.map(\.label) }

    static func infer(name: String = "", dish: String = "", explanation: String = "",
                      tags: [String]? = nil) -> String? {
        // An explicit cuisine tag (e.g. from a resolved TikTok) wins.
        for tag in tags ?? [] {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            if let exact = table.first(where: { $0.label.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return exact.label
            }
        }
        let text = ([name, dish, explanation] + (tags ?? [])).joined(separator: " ").lowercased()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return table.first { row in row.keywords.contains { matches($0, in: text) } }?.label
    }

    /// Whole-word-ish match so "pho" doesn't fire inside "phone" and "bao"
    /// doesn't fire inside "baobab".
    private static func matches(_ keyword: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: keyword, range: searchRange) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            let startsWord = before.map { !$0.isLetter } ?? true
            // Allow simple plurals/suffixes ("tacos", "taqueria", "dumplings").
            let endsWordOrSuffix = after.map { !$0.isLetter || "sei".contains($0) } ?? true
            if startsWord && endsWordOrSuffix { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }
}
