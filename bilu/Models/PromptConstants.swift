//
//  PromptConstants.swift
//  bilu
//

import Foundation

enum PromptConstants {
    static let occasionPrompts: [String: String] = [
        "Grab & Go": "Focus on high-efficiency, window-service, or counter-only spots. Prioritize locations where the total time from order to food is <15 minutes. No formal host stands or lengthy table service.",
        "Sit Down": "Prioritize full-service dining with a curated atmosphere. The setting is as important as the food. Favor places that reward lingering, whether for a date or a group catch-up.",
        "Happy Hour": "Strictly verify and mention active 2026 Happy Hour deals (e.g., '$1.50 Oysters,' '$12 Wagyu Sliders,' or 'Half-off Specialty Cocktails'). Ensure the venue's HH window is currently open."
    ]

    static let vibePrompts: [String: String] = [
        "Trending": "Identify the latest 2026 viral sensations currently topping Beli rankings and TikTok 'Must-Eat' lists. Places that have been getting the most attention online and could have a long line out the door",
        "Local and authentic": "Prioritize 'If you know, you know' legends and street-food icons with massive local cult followings. Look for high-quality, high-soul spots like Leo's Tacos or Sonoratown. Favor cultural enclave staples over polished commercial areas.",
        "The Social Buzz": "Identify high-volume, high-energy bars with a 'see and be seen' atmosphere. Prioritize networking hotspots in DTLA, West Hollywood, or Culver City with communal standing areas.",
        "The Chill Vibe": "Prioritize low-lit, conversation-friendly lounges or hidden garden patios. Favor spots with comfortable bar stools and a 'vinyl bar' or 'neighborhood local' aesthetic.",
        "The Activity Hub": "Search for venues with social hooks: pool tables, retro arcade games, competitive trivia, or live DJ sets that encourage movement.",
        "The Sunset View": "Prioritize elevated rooftops or coastal patios with unobstructed westward views. Favor venues where 'Golden Hour' lighting is a primary architectural feature.",
        "The Aesthetic": "Prioritize visually stunning interiors (maximalist decor, special art and stunning views). Birthday and aniversery style places. Nicer and fancier places that are photogenic and 'Instagram-first.'",
        "Dim & Intimate": "Prioritize intimate, mood-lit settings with booths and low noise levels. Think vibes perfect for a high-end date night. Should also have a beutiful interior and great views.",
        "Trendy & Viral": "Identify the 2026 'It' spots currently dominating the Eater LA Heat Map. Focus on chef-driven concepts like Dama or viral multi-hyphenate bistros that are notoriously hard to get a table at.",
        "Nothing Fancy": "Prioritize 'Unpretentious Elite'—locations where the food is world-class but the service is casual. Favor strip-mall gems or industrial warehouse spots that prioritize flavor over tablecloths."
    ]

    static let hungerPrompts: [String: String] = [
        "Warm & Slurpy": "Focus on broth-depth and noodle-texture. Prioritize high-end Ramen, hand-pulled Biang Biang noodles, or authentic Pasta (e.g., Cacio e Pepe or Carbonara).",
        "Doughy & Loaded": "Focus on the 'Handheld Weight.' Prioritize salt-fat-acid balanced delights: Lebanese Shawarma, Al Pastor trompo tacos, thick-cut Smashburgers, or overloaded Burritos.",
        "Fresh & Crisp": "Focus on 'Clean Energy.' Prioritize dry-aged Sushi, vibrant Mediterranean mezze, or artisanal bowls that use local, non-processed 2026 seasonal produce.",
        "Spicy & Bold": "Focus on high-heat aromatics. Prioritize Nashville Hot Chicken (Level: Spicy), Szechuan Peppercorn-heavy dishes, or authentic Thai 'Jungle' Curries.",
        "Small & Shared": "Focus on 'Variety over Volume.' Prioritize Spanish Tapas, Cantonese Dim Sum, or Izakaya-style small plates meant for the whole table to sample.",
        "Sweet & Treat": "Focus on the best and popular desert and sweet treat places that the users area has to offer",
        "The Shareable Feast": "Prioritize groups of 3+ small plates. Focus on 'crowd-pleasers' like truffle fries, wings, or flatbreads that facilitate communal eating.",
        "The Sip & Snack": "Focus on 'grazing' items that pair with alcohol: Marinated olives, salty pretzels, or high-end tinned fish boards.",
        "The Half-Priced Hero": "Identify the best 'Bang for Buck'—mini versions of expensive classics (e.g., $10 Wagyu sliders or $2 oysters) that feel like a steal.",
        "The Liquid Dinner": "Focus on 'Drink-Forward' experiences: Craft cocktail flights, natural wine tastings, or venues with an elite back-bar and minimal food interference."
    ]

    static func getApplicableDiscoveryRules(selection: VibeSelection) -> [String] {
        var rules: [String] = []
        var seen = Set<String>()

        if !selection.occasion.isEmpty, let msg = occasionPrompts[selection.occasion], !seen.contains(msg) {
            seen.insert(msg)
            rules.append(msg)
        }

        for v in selection.vibe {
            if let msg = vibePrompts[v], !seen.contains(msg) {
                seen.insert(msg)
                rules.append(msg)
            }
        }

        for h in selection.hunger {
            if let msg = hungerPrompts[h], !seen.contains(msg) {
                seen.insert(msg)
                rules.append(msg)
            }
        }

        return rules
    }
}
