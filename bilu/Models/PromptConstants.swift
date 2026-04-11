//
//  PromptConstants.swift
//  bilu
//

import Foundation

enum PromptConstants {
    static let occasionPrompts: [String: String] = [
        "Quick Bite": "The user needs wants some great food, not a full sit down restaurant but also not a fast food chain.",
        "Date Night": "This is a date. The setting needs to feel like part of the date.",
        "Sit Down Meal": "The user wants a proper sit-down dining experience.",
        "Big Group": "The user is organizing dining for a large group — it needs to actually work for everyone.",
        "Cafe": "The user wants a cafe",
        "Happy Hour": "The user wants Happy Hour deals — verified and real. Mention the specific specials.",
        "Celebration": "The user is celebrating something — it needs to feel special."
    ]

    static let keyQuestionPrompts: [String: String] = [
        // Quick Bite
        "Fastest near me": "The user wants the fastest option — closest with shortest wait. grab and go style",
        "Best quality nearby": "The user wants the best food near them, Amazing ratings on google and top-rated on Yelp, award-winning and a must eat place",
        "Something new & trendy": "The user wants the most viral spot right now — Viral on tik tok, reddit, yelp, and has all the media attention. Long lines are expected.",
        "Cheap & good": "The user wants the best value — great food at a price that surprises them. Mention what things cost.",

        // Date Night
        "Tonight": "The user wants to go tonight — walk-ins or open slots right now only.",
        "Planning ahead": "The user is planning ahead — recommend something worth booking in advance.",
        "Outdoor / patio": "The user wants to sit outside — confirmed outdoor seating only. Describe the setup.",
        "No must-haves": "The user just wants the best date night spot. No prefrences, just the best food, ambiance, and best suggestion you have for a date night.",

        // Sit Down Meal
        "Aesthetic & worth posting": "The user wants somewhere visually impressive and worth posting. Nice asthetic, beutiful interior.",
        "Chill & low-key": "The user wants a chill and lowkey place.",
        "Good value": "The user wants reasonable prices and generous portions — Good prices and worth the price.",
        "Trendy & buzzy": "The user wants the hottest spot right now — viral on TikTok, Beli, Yelp, and Reddit. Long lines are expected.",
        "Just great food": "The user wants the best food available, no prefrences — award-winning, top-rated nationally or locally, 4+ stars with thousands of positive reviews.",

        // Big Group
        "Private or semi-private space": "The group needs their own space — private or semi-private dining. Only recommend if this exists.",
        "Reservation available": "The group needs to book ahead. Confirmed reservation availability required.",
        "Central & easy to get to": "The group needs somewhere easy for everyone to reach — transit-friendly, parking nearby, central.",

        // Cafe
        "Here to study or work": "getting work done or studying. I want to find the best study cafe for locking in. Find me places that are known for being a study spot. They MUST have the following: reliable wifi, enough space, power outlets, and comfortable seating for 2+ hours. Find the most dedicated study spot known for doing work.",
        "Just great coffee": "The user wants the best matcha in the area right now — Places known for their delicious matcha lattes, matcha einspanners, Find places with high review count, even if there is a long line. Ignore food and pasteries, Just best matcha",
        "Catching up with someone": "The user is meeting someone to talk — needs somewhere comfortable and unhurried.",
        "Brunch & bites too": "The user wants real food alongside their coffee — not just pastries.",

        // Happy Hour
        "Rooftop or outdoor": "The user wants a rooftop or strong outdoor experience — confirmed only. Describe the view.",
        "Trendy cocktail bar": "The user wants a craft cocktail bar with real identity — a happy hour worth showing up for.",
        "Chill dive bar": "The user wants a no-frills bar with cheap, genuine happy hour specials.",
        "Wine & grazing": "The user wants to sip wine and pick at food slowly — relaxed and unhurried.",

        // Celebration
        "Birthday dinner": "Someone's birthday — needs to feel special and memorable.",
        "Big night out": "The group wants a high-energy launch pad for the night — great food and late hours.",
        "Anniversary": "A romantic milestone — the most intimate and elevated experience available.",
        "Achievement or graduation": "Celebrating an achievement — impressive but approachable, proud and celebratory."
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

    static let countryPrompts: [String: String] = [
        "American":       "Find the best American restaurant — craft burgers, regional BBQ, smash patties, fried chicken, or comfort food with real identity. Prioritize independent spots over casual-dining chains.",
        "Italian":        "Find the best Italian restaurant — handmade pasta, wood-fired pizza, and authentic regional cooking. Trattorias and osterie over red-sauce chains. Look for imported ingredients, long-standing reputation, and real Italian heritage.",
        "Mexican":        "Find the best Mexican restaurant — from tacos and birria to mole and regional Mexican cooking. Authentic and independent, not Tex-Mex fast-casual. Prioritize places known for a specific regional style or signature dish.",
        "Japanese":       "Find the best Japanese restaurant — ramen, sushi, izakaya, tonkatsu, udon, or omakase. Prioritize chef-driven, specialist spots with authentic technique and sourcing.",
        "Chinese":        "Find the best Chinese restaurant — dim sum, Peking duck, Sichuan, Cantonese, or hand-pulled noodles. Look for regional specificity and depth of flavour over generic takeaway fare.",
        "Indian":         "Find the best Indian restaurant — curries, tandoor, dosas, or North/South Indian regional cooking. Prioritize places with homemade sauces, authentic spicing, and real depth of flavour.",
        "Thai":           "Find the best Thai restaurant — pad thai, curries, larb, and som tam done with real fermented paste and fresh herbs. Avoid tourist-watered-down versions. Prioritize authentic family-run spots.",
        "Korean":         "Find the best Korean restaurant — KBBQ, bibimbap, army stew, fried chicken, or tteokbokki. Look for high-quality meat programs if KBBQ, and genuine banchan culture.",
        "Mediterranean":  "Find the best Mediterranean restaurant — mezze, grilled fish, hummus, kebabs, and wood-fire cooking drawing from Greek, Turkish, Lebanese, or Levantine traditions. Fresh, olive-oil-forward, ingredient-led.",
        "French":         "Find the best French restaurant — bistro classics, steak frites, soufflés, or refined tasting menus. Look for classical French technique and provenance, not just French-adjacent fusion.",
        "Greek":          "Find the best Greek restaurant — grilled octopus, moussaka, souvlaki, spanakopita, and loukoumades. Prioritize family-run tavernas and imported ingredients over American-Greek chains.",
        "Vietnamese":     "Find the best Vietnamese restaurant — pho, banh mi, bun bo hue, vermicelli bowls, or fresh spring rolls. Look for house-made broths and genuine regional recipes, not just americanized Vietnamese.",
        "Middle Eastern": "Find the best Middle Eastern restaurant — shawarma, falafel, hummus, manakish, or slow-roasted meats from Lebanese, Israeli, Persian, or Syrian traditions. Fresh herbs, warm bread, and deep spice profiles.",
        "Spanish":        "Find the best Spanish restaurant — tapas, jamón ibérico, paella, pintxos, or Basque cooking. Look for imported cured meats, good wine programs, and a genuine social dining atmosphere.",
        "Brazilian":      "Find the best Brazilian restaurant — churrasco, feijoada, coxinha, or a proper rodizio with tableside carving. Prioritize authentic Brazilian hospitality and high-quality meat programs.",
        "Ethiopian":      "Find the best Ethiopian restaurant — injera with a full selection of wats, kitfo, and tibs. Look for house-made injera and communal platters that reflect real Ethiopian dining culture.",
        "Peruvian":       "Find the best Peruvian restaurant — ceviche, lomo saltado, causa, anticuchos, and tiradito. Prioritize places with a clear chef identity rooted in Peruvian technique and citrus-forward flavour."
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

        if selection.cuisineMode == "country" && !selection.selectedCountry.isEmpty {
            add(selection.selectedCountry, from: countryPrompts)
        } else {
            for feeling in selection.foodFeelings {
                add(feeling, from: foodFeelingPrompts)
            }
        }

        return rules
    }
}
