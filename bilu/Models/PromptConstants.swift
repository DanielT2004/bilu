//
//  PromptConstants.swift
//  bilu
//

import Foundation

enum PromptConstants {
    static let occasionPrompts: [String: String] = [
        "Quick Bite": "The user needs food fast — this is counter-service or grab-and-go. Prioritize spots where the total time from walking in to eating is under 15 minutes. No full-service restaurants, no host stands, no lengthy menus. Think quality fast-casual: taco counters, ramen windows, poke spots, deli counters.",
        "Date Night": "The user is on a date or planning one. Atmosphere is as important as the food — maybe more. Prioritize places where the setting creates a mood: dim lighting, interesting interiors, intimate table spacing. Avoid loud or casual spots. The experience itself should feel like the date.",
        "Sit Down Meal": "The user wants a proper sit-down meal — full table service, a real menu worth exploring, a social occasion. The vibe matters as much as the food. Avoid counter service or anything that feels rushed.",
        "Big Group": "The user is organizing food for a large group — logistics matter as much as food quality. Prioritize places with large table availability, group-friendly menus (family style or shared plates), good noise tolerance, and reservation capability. Avoid tiny intimate spots.",
        "Cafe": "Find me a cafe. It must be within 2 or less miles of my location for ",
        "Happy Hour": "The user specifically wants Happy Hour — verified deals, drinks, and a good early-evening vibe. CRITICAL: only recommend places with active Happy Hour specials. Mention specific deals in the explanation (e.g. '$6 draft beers 4–6pm', 'half-off oysters'). The deal IS the recommendation.",
        "Celebration": "The user is celebrating something meaningful. Prioritize places that feel special and memorable — elevated service, impressive food, a setting that rises to the occasion. This is not a casual meal."
    ]

    static let keyQuestionPrompts: [String: String] = [
        // Quick Bite
        "Fastest near me": "Speed is the top priority — the user is hungry NOW. Rank by proximity and order speed above all else. A slightly lesser restaurant 2 minutes away beats a great one 15 minutes away. Look for spots with minimal wait, quick service reviews, and high throughput.",
        "Best quality nearby": "The user wants the single best food within a reasonable distance — look for award winning places on yelp and beli, top 100 places to eat, or rankings related to food category and location. think local legends. Favor one-location spot with 3,000 reviews. Favor places with press recognition (Eater, Infatuation, LA Times food section, Beli top lists, Michelin Bib Gourmand)",
        "Something new & trendy": "The user wants discovery — a genuinely new concept with buzz and soul, not a corporate chain opening its 50th location. Prioritize 2023–2026 chef-driven independent openings dominating Eater LA, Beli, or the Infatuation heat map. TikTok food moments, reservation-required buzz spots, first-of-its-kind concepts with recent press coverage. A national fast-casual brand opening a new outpost is NOT this. A debut from a celebrated chef or a viral local concept that just blew up is exactly this. The discovery IS the point.",
        "Cheap & good": "Value is the entire point. Find spots where the food punches way above the price — hidden gems, strip-mall legends, cash-only holes-in-the-wall, taco trucks with cult followings. A $12 plate that tastes like $40 is the target. Explicitly mention pricing in the explanation.",

        // Date Night
        "Tonight": "The user wants to go TONIGHT and needs real availability. Prioritize places where walk-ins are realistic OR where OpenTable/Resy shows open slots tonight. Mention reservation availability in the explanation. Do not recommend places booked weeks out.",
        "Planning ahead": "The user is planning ahead for a specific date. Prioritize places worth booking in advance — tasting menus, chef's tables, highly sought-after restaurants where a reservation is the right move. Incorporate the date context from their selection.",
        "Outdoor / patio": "The user specifically wants to sit outside. ONLY recommend places with verified outdoor or patio seating. Mention the exact setup in the explanation — rooftop, garden patio, sidewalk seating. Do not suggest places where outdoor seating is unconfirmed.",
        "No must-haves": "No constraints — find the absolute best date night spots available. Focus entirely on atmosphere, food quality, and the romantic/intimate factor.",

        // Sit Down Meal
        "Aesthetic & worth posting": "The user wants somewhere visually impressive — for the group experience AND the content. Prioritize stunning interiors, photogenic dishes, architecturally interesting spaces. Reviews should mention 'beautiful', 'stunning', 'great for photos'. The vibe needs to be post-worthy.",
        "Chill & low-key": "The user wants zero pretense — no dress code, no formality, no waiting to be seated by a host. Think neighborhood spots, casual seating, places where everyone's comfortable in whatever they're wearing. Great food in a genuinely relaxed setting.",
        "Good value": "The group is conscious of the bill. Find generous portions at reasonable prices, easy bill-splitting. Not fast food, but not $150/head either. Think crowd-pleasing spots where everyone leaves full and happy without sticker shock.",
        "Trendy & buzzy": "The group wants the 'it' spot — currently hot, people are talking about it. Prioritize the Eater LA Heat Map, new chef-driven concepts with press, spots where getting a table feels like a win. Energy and relevance of the spot matters.",
        "Just great food": "No agenda beyond the food itself — ignore atmosphere, trendiness, and logistics. Find the places with the absolute best food quality for this cuisine and feeling. Michelin Bib Gourmand, James Beard nominees, places locals go purely for the food.",

        // Big Group
        "Private or semi-private space": "The group needs their own space — a private dining room, a semi-private section, or a large corner that doesn't feel like strangers are packed in. ONLY recommend places that can actually accommodate this. Mention the space setup explicitly in the explanation.",
        "Reservation available": "The group needs to be able to book ahead — walk-in is not an option. Prioritize places on OpenTable or Resy with confirmed availability for large groups. Do not recommend places that don't take reservations.",
        "Central & easy to get to": "Location and accessibility matter most. Prioritize spots that are transit-accessible, have parking nearby, or are in a central neighborhood everyone can reach easily. Mention accessibility in the explanation.",

        // Cafe
        "Here to study or work": "getting work done or studying. I want to find the best study cafe for locking in. Find me places that are known for being a study spot. They MUST have the following: reliable wifi, enough space, power outlets, and comfortable seating for 2+ hours. Find the most dedicated study spot known for doing work.",
        "Just great coffee": "The user is a coffee person — they care about espresso quality, bean sourcing, and barista skill above all else. Prioritize specialty third-wave coffee shops: single-origin pour-overs, serious espresso programs, roasters who know their craft. Food is secondary. Starbucks and all chain coffee is the exact opposite of this.",
        "Catching up with someone": "The user is meeting someone for a real conversation — the setting needs to support talking. Prioritize cafes with comfortable seating, medium noise levels (not silent, not overwhelming), no pressure to leave quickly. Cozy booths, garden seating, or relaxed table setups where two people can talk for an hour without being rushed.",
        "Brunch & bites too": "The user wants real food alongside their coffee — not just pastries. Prioritize cafes with full food menus: eggs, sandwiches, bowls, or substantial brunch items. Food quality should match the coffee quality.",

        // Happy Hour
        "Rooftop or outdoor": "The user specifically wants a rooftop or strong outdoor experience for happy hour. ONLY recommend places with confirmed rooftop or outdoor terrace seating. Describe the specific view or outdoor setup in the explanation.",
        "Trendy cocktail bar": "The user wants craft cocktails at a place with an aesthetic and an identity. Prioritize bars with serious cocktail programs, interesting seasonal menus, and a look that's worth showing up for. Happy hour deals on creative cocktails are the ideal.",
        "Chill dive bar": "The user wants zero pretense — cheap drinks, comfortable barstools, maybe a pool table or jukebox. Prioritize neighborhood dives, cash-only bars, places where regulars have been coming for years. Happy hour should mean genuinely cheap, not $14 'discounted' cocktails.",
        "Wine & grazing": "The user wants to sip wine and pick at food slowly — a relaxed, unhurried happy hour. Prioritize wine bars with natural or interesting wine lists, places with charcuterie and cheese boards, spots where the pace is leisurely and the food is meant for sharing over an hour.",

        // Celebration
        "Birthday dinner": "Someone is celebrating a birthday — this needs to feel special and memorable. Prioritize places with standout atmospheres, impressive tasting menus or signature dishes, and ideally spots that acknowledge occasions (special desserts, etc.). The meal should be an event.",
        "Big night out": "The group wants a full EXPERIENCE — high energy, great food, and a launch pad for the night. Prioritize places with strong atmosphere, late kitchen hours, and a social buzz. Bonus if there's a bar attached or it's in an area with nightlife nearby.",
        "Anniversary": "This is a romantic milestone — pull out all the stops. Prioritize the most intimate, romantic, and elevated experiences available: tasting menus, chef's table experiences, or places specifically known for romantic evenings. The meal needs to match the weight of the occasion.",
        "Achievement or graduation": "A group is celebrating someone's achievement — the vibe should be proud and celebratory, likely with people of different ages. Prioritize places that are impressive but not intimidating, celebratory but not nightclub-energy. Private dining rooms are a strong plus."
    ]

    static let foodFeelingPrompts: [String: String] = [
        "Fresh & crisp": "The user wants food that feels clean, light, and energizing — not heavy or rich. Think fresh ingredients, bright flavors, acid-forward dishes. Any cuisine works as long as it leaves you feeling good, not weighed down. Avoid anything fried, heavy, or sauce-drenched.",
        "Doughy & loaded": "The user wants something substantial and hands-on — carb-forward, generously loaded, built for satisfying hunger. Think anything with bread, dough, or a stuffed/stacked quality: burgers, sandwiches, pizza, tacos, shawarma, burritos, and beyond. The vibe is salt, fat, and acid in balance. Don't limit to those examples — any cuisine that hits this feeling counts.",
        "Soupy & warming": "The user wants something brothy, cozy, and deeply comforting. Any cuisine with a great bowl or pot — noodle soups, stews, broths, dumplings in soup. The warmth and depth of the liquid is the main signal. Find the best bowl near them regardless of cuisine origin.",
        "Crispy & crunchy": "The user wants texture — the satisfying crunch of well-fried or well-roasted food. Any cuisine that delivers real crispiness counts: fried chicken, tempura, crispy tacos, spring rolls, schnitzel, katsu, chicharrón. The crunch is the point, not the cuisine type.",
        "Spicy & bold": "The user wants heat — food with a real spicy kick. Any cuisine that delivers genuine spice: spicy noodles, hot chicken, spicy curries, chile-forward dishes, fiery Korean, bold Thai, spicy Mexican. Don't overthink heat complexity — just find the best spicy food near them.",
        "Rich & indulgent": "The user wants to treat themselves — something decadent, fatty, and deeply satisfying. Any cuisine with richness: buttery, creamy, heavily sauced, or luxurious. This is the meal where calories don't count. Find the most indulgent, high-quality option near them.",
        "Stew-y & saucy": "The user wants something saucy and slow-cooked — food where the sauce or stew is the star. Any cuisine built around a rich, flavourful sauce or braise: curries, tagines, ragu, stews, slow-cooked meats. The food should feel like it's been building flavor for hours.",
        "Smoky & charred": "The user wants fire and smoke — food cooked over real heat with char and smokiness as a feature. Any cuisine that delivers this: BBQ, grilled meats, charcoal chicken, kebabs, yakitori, wood-fired anything. The smoke and char should be unmistakable.",
        "Surprise me": "The user has no cuisine preference — find them the single best, most soul-satisfying, culturally interesting restaurant near them right now. This is your chance to make the pick they wouldn't have thought of themselves. Choose based purely on quality, local legend status, and current buzz. Don't default to generic American — be bold and specific."
    ]

    static func getApplicableDiscoveryRules(selection: VibeSelection) -> [String] {
        var rules: [String] = []
        var seen = Set<String>()

        func add(_ key: String, from dict: [String: String]) {
            guard let msg = dict[key], !seen.contains(msg) else { return }
            seen.insert(msg)
            rules.append(msg)
        }

        add(selection.occasion, from: occasionPrompts)
        add(selection.keyQuestionAnswer, from: keyQuestionPrompts)
        for feeling in selection.foodFeelings {
            add(feeling, from: foodFeelingPrompts)
        }

        return rules
    }
}
