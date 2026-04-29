//
//  PromptConstants.swift
//  bilu
//

import Foundation

enum PromptConstants {
    static let occasionPrompts: [String: String] = [
        // Legacy occasions
        "Quick Bite":    "The user wants great food fast — not a full sit-down restaurant but not a fast food chain either.",
        "Date Night":    "This is a date. The setting needs to feel like part of the date.",
        "Sit Down Meal": "The user wants a proper sit-down dining experience.",
        "Big Group":     "The user is organizing dining for a large group — it needs to actually work for everyone.",
        "Cafe":          "The user wants a cafe.",
        "Happy Hour":    "The user wants Happy Hour deals — verified and real. Mention the specific specials.",
        "Celebration":   "The user is celebrating something — it needs to feel special.",
        // New time-based occasions
        "Casual":        "The user wants good, casual food — counter service or a relaxed grab-and-go spot. Not a chain.",
        "Sit Down":      "The user wants a proper sit-down meal. The place should feel like a destination.",
        "No Rush":       "The user wants to make a night of it. Quality and atmosphere both matter.",
        "Brunch":        "The user wants a great brunch spot.",
        "Late Night":    "The user wants somewhere open late with real food.",
        // Drinks tab
        "Bakery":        "The user wants a great bakery.",
        "Dessert":       "The user wants dessert — find the best sweet spot.",
        "Drinks":        "The user wants a drinks spot — bar, cocktails, or wine.",
    ]

    static let keyQuestionPrompts: [String: String] = [
        // Quick Bite
        "Fastest near me": "The user wants the fastest option — closest with shortest wait. Grab-and-go style.",
        "Best quality nearby": "The user wants the best food — amazing ratings on Google and top-rated on Yelp, award-winning and a must-eat place.",
        "Something new & trendy": "The user wants the most viral spot right now — viral on TikTok, Reddit, Yelp, and has all the media attention. Long lines are expected.",
        "Cheap & good": "The user wants the best value — great food at a price that surprises them. Mention what things cost.",

        // Date Night
        "Tonight": "The user wants to go tonight — walk-ins or open slots right now only.",
        "Planning ahead": "The user is planning ahead — recommend something worth booking in advance.",
        "Outdoor / patio": "The user wants to sit outside — confirmed outdoor seating only. Describe the setup.",
        "No must-haves": "The user just wants the best date night spot. No preferences, just the best food, ambiance, and best suggestion you have for a date night.",

        // Sit Down Meal
        "Aesthetic & worth posting": "The user wants somewhere visually impressive and worth posting. Nice aesthetic, beautiful interior.",
        "Chill & low-key": "The user wants a chill and low-key place.",
        "Good value": "The user wants reasonable prices and generous portions — good prices and worth every dollar.",
        "Trendy & buzzy": "The user wants the hottest spot right now — viral on TikTok, Beli, Yelp, and Reddit. Long lines are expected.",
        "Just great food": "The user wants the best food available, no preferences — award-winning, top-rated nationally or locally, 4+ stars with thousands of positive reviews.",

        // Big Group
        "Private or semi-private space": "The group needs their own space — private or semi-private dining. Only recommend if this exists.",
        "Reservation available": "The group needs to book ahead. Confirmed reservation availability required.",
        "Central & easy to get to": "The group needs somewhere easy for everyone to reach — transit-friendly, parking nearby, central.",

        // Cafe
        "Here to study or work": "Getting work done or studying. Find the best study café — known for being a study spot. Must have: reliable wifi, enough space, power outlets, and comfortable seating for 2+ hours.",
        "Just great coffee": "The user wants the best specialty coffee — espresso-forward café, great lattes, or quality matcha. High review count, known for their drinks. Focus on the coffee, not the food.",
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
        "Achievement or graduation": "Celebrating an achievement — impressive but approachable, proud and celebratory.",

        // Drinks sub-flow — Cafe
        "Great coffee":        "The user wants the best specialty coffee — quality-first, great espresso or matcha.",
        "Work or study":       "The user wants a café to work or study — reliable wifi, quiet, comfortable for a long stay.",
        "Catching up":         "The user wants a relaxed café to catch up with someone — comfortable, unhurried, conversational.",
        "Coffee & food":       "The user wants a café with real food alongside their coffee — not just drinks.",

        // Drinks sub-flow — Dessert
        "Ice cream":           "The user wants ice cream or gelato — the best scoop spot.",
        "Cookies & baked":     "The user wants freshly baked cookies or pastries.",
        "Cake & fancy":        "The user wants a patisserie or plated dessert experience.",
        "Boba & sweet drinks": "The user wants boba or sweet drinks.",

        // Drinks sub-flow — Drinks
        "Cocktail bar":        "The user wants a craft cocktail bar — aesthetic, creative drinks, worth the trip.",
        "Wine bar":            "The user wants a wine bar — relaxed, grazing-friendly, good natural wine.",
        "Rooftop":             "The user wants a rooftop bar with views and outdoor atmosphere.",
        "Low key bar":         "The user wants a no-frills, cheap, unpretentious bar."
    ]

    static let vibePrompts: [String: String] = [
        "🔥 Trending":  "Prioritize spots with real buzz right now — viral on TikTok, talked about on Reddit and Yelp, with recent media attention. Long lines and a wait are expected and fine.",
        "⭐ Best rated": "Prioritize the highest-rated spots — high review count on Google and Yelp, consistent 4.5+ stars, and well-regarded by local food media.",
        "🌟 Hidden gem": "Prioritize lesser-known spots that locals love — strong reviews but low hype, not on every tourist list.",
        "📸 Aesthetic":  "The setting and vibe matter as much as the food — somewhere visually impressive and worth posting.",
        "😌 Low-key":    "Somewhere relaxed and unpretentious — good food without the fuss or fanfare.",
        // No Rush occasion sub-picker
        "🍽 Best food":         "Find the best food available — quality and reputation first.",
        "⚡ Date night":        "This is a date night. The setting and atmosphere must feel special.",
        "🎉 Special occasion":  "This is a special occasion — it needs to feel memorable and impressive.",
    ]

    static let foodFeelingPrompts: [String: String] = [
        // New food category grid keys
        "Handheld":              "The user wants something hand-held — burgers, tacos, wraps, sandwiches, or shawarma.",
        "Asian noodles & broth": "The user wants Asian noodles or a broth bowl — ramen, pho, udon, or laksa.",
        "Italian & pizza":       "The user wants Italian — pasta, pizza, or risotto.",
        "Meaty":                 "The user wants a meat-forward meal — steak, BBQ, fried chicken, or kebabs.",
        "Bowls & stews":         "The user wants something saucy and warming — curries, stews, or grain bowls.",
        // Brunch-specific categories
        "Eggy & savory":         "The user wants an egg-forward brunch — eggs benedict, shakshuka, omelette, or savory egg dishes.",
        "Doughy & warm":         "The user wants something warm and doughy for brunch — pancakes, french toast, or waffles.",
        "Sweet & flaky":         "The user wants pastries and baked goods — croissants, danishes, or pastries. Patisserie or bakery-café style.",
        // Sub-option drilldowns (specific picks within a category)
        "Burger":        "The user specifically wants a burger — smash, gourmet, classic, or smashed patty.",
        "Taco":          "The user specifically wants tacos — street tacos, birria, fish tacos, or al pastor.",
        "Shawarma":      "The user specifically wants shawarma — Lebanese, Turkish, or Israeli style, hand-carved if possible.",
        "Sandwich":      "The user specifically wants a sandwich — Italian beef, banh mi, deli sub, or a great independent sandwich shop.",
        "Ramen":         "The user specifically wants ramen — serious broth program, tonkotsu, shoyu, miso, or spicy.",
        "Pho":           "The user specifically wants pho — long-simmered house broth, fresh garnishes, proper quality.",
        "Udon":          "The user specifically wants udon — thick hand-cut noodles, great dashi, hot or cold.",
        "Laksa":         "The user specifically wants laksa — rich coconut curry broth, proper Southeast Asian style.",
        "Pizza":         "The user specifically wants pizza — Neapolitan, NY-style, Detroit, or wood-fired. No chains.",
        "Pasta":         "The user specifically wants pasta — fresh handmade pasta preferred, Italian-owned and chef-driven.",
        "Risotto":       "The user specifically wants risotto — properly made, creamy, seasonal ingredients.",
        "Italian":       "The user wants Italian — trattoria, osteria, or fine Italian with real depth.",
        "Steak":         "The user specifically wants steak — dry-aged, wood-fired, or prime cuts.",
        "BBQ":           "The user specifically wants BBQ — smoker-first, real regional BBQ. Brisket, ribs, or pulled pork with actual smoke.",
        "Korean BBQ":    "The user specifically wants Korean BBQ — high-quality meat program, great banchan, proper tabletop grill.",
        "Kebab":         "The user specifically wants kebab — döner, kofta, shish, or Middle Eastern style, not fast-food.",
        "Curry":         "The user specifically wants curry — Indian, Thai, Japanese, or Trinidadian. Deep flavour and proper spicing.",
        "Ethiopian":     "The user specifically wants Ethiopian food — house-made injera, rich stews, generous spread.",
        "Tagine":        "The user specifically wants tagine — slow-cooked, aromatic, proper clay-pot style. Moroccan or North African.",
        "Bibimbap":      "The user specifically wants bibimbap — stone bowl, fresh toppings. Korean restaurant with a standout version.",
        "Sushi":         "The user specifically wants sushi — omakase, traditional nigiri, or a great sushi counter. Quality fish only.",
        "Poke":          "The user specifically wants poke — fresh fish, well-seasoned, not overly sauced or premade.",
        "Ceviche":       "The user specifically wants ceviche — Peruvian or Latin seafood, serious ceviche program.",
        "Vietnamese":    "The user specifically wants Vietnamese food — fresh herbs, regional recipes, real broth quality.",
        "Eggs benny":    "The user specifically wants eggs benedict — proper hollandaise, quality protein.",
        "Shakshuka":     "The user specifically wants shakshuka — rich tomato-pepper sauce, perfectly set eggs. Middle Eastern or brunch spot.",
        "Omelette":      "The user specifically wants an omelette — French-style or loaded. Cafe or brunch spot.",
        "Avo toast":     "The user specifically wants avocado toast — good bread, quality avo, interesting toppings.",
        "Pancakes":      "The user specifically wants pancakes — serious, fluffy, and memorable.",
        "French toast":  "The user specifically wants french toast — thick-cut, brioche-based, or creative.",
        "Waffles":       "The user specifically wants waffles — Belgian, fried-chicken-and-waffle, or classic buttermilk.",
        "Brioche":       "The user specifically wants brioche — fresh, buttery. Patisserie or cafe.",
        "Croissant":     "The user specifically wants a croissant — laminated, buttery, properly made. Bakery or patisserie.",
        "Pastry":        "The user specifically wants pastry — viennoiserie, tarts, or layered pastries. Patisserie with a serious program.",
        "Danish":        "The user specifically wants a danish — laminated dough, fruit or custard filling. Scandinavian bakery or cafe.",
        "Donut":         "The user specifically wants a donut — brioche, yeasted, or cake donuts with creative glazes. Artisan spot.",
        // Legacy food feeling keys
        "Fresh & crisp": "The user wants food that feels clean, light, and energizing — not heavy or rich. Think fresh ingredients, bright flavors, acid-forward dishes. Any cuisine works as long as it leaves you feeling good, not weighed down. Avoid anything fried, heavy, or sauce-drenched.",
        "Doughy & loaded": "The user wants something substantial and hands-on — carb-forward, generously loaded, built for satisfying hunger. Think anything with bread, dough, or a stuffed/stacked quality: burgers, sandwiches, pizza, tacos, shawarma, burritos, and beyond. The vibe is salt, fat, and acid in balance.",
        "Soupy & warming": "The user wants something brothy, cozy, and deeply comforting. Any cuisine with a great bowl or pot — noodle soups, stews, broths, dumplings in soup. The warmth and depth of the liquid is the main signal.",
        "Crispy & crunchy": "The user wants texture — the satisfying crunch of well-fried or well-roasted food. Any cuisine that delivers real crispiness counts: fried chicken, tempura, crispy tacos, spring rolls, schnitzel, katsu, chicharrón. The crunch is the point, not the cuisine type.",
        "Spicy & bold": "The user wants heat — food with a real spicy kick. Any cuisine that delivers genuine spice: spicy noodles, hot chicken, spicy curries, chile-forward dishes, fiery Korean, bold Thai, spicy Mexican.",
        "Rich & indulgent": "The user wants to treat themselves — something decadent, fatty, and deeply satisfying. Any cuisine with richness: buttery, creamy, heavily sauced, or luxurious. This is the meal where calories don't count.",
        "Stew-y & saucy": "The user wants something saucy and slow-cooked — food where the sauce or stew is the star. Any cuisine built around a rich, flavourful sauce or braise: curries, tagines, ragu, stews, slow-cooked meats. The food should feel like it's been building flavor for hours.",
        "Smoky & charred": "The user wants fire and smoke — food cooked over real heat with char and smokiness as a feature. Any cuisine that delivers this: BBQ, grilled meats, charcoal chicken, kebabs, yakitori, wood-fired anything. The smoke and char should be unmistakable.",
        "Surprise me": "The user has no cuisine preference — find the single best, most soul-satisfying, culturally interesting restaurant right now. This is your chance to make the pick they wouldn't have thought of themselves. Choose based purely on quality, local legend status, and current buzz. Don't default to generic American — be bold and specific."
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
