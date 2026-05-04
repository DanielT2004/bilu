# bilu — Design Doc

This document explains how bilu actually works under the hood. It is written for an entry-level engineer joining the project. If you have read the README and looked at a few files but feel lost about *why* the code is shaped the way it is, start here.

For visual/UI rules (colors, spacing, animations), see [CLAUDE.md](CLAUDE.md). This doc is about systems and data flow.

---

## 1. What bilu is

bilu is a SwiftUI iOS app for discovering restaurants. It has two completely different ways to find a place to eat:

1. **Vibe Search (Home tab)** — A short survey ("what's the occasion?", "what are you craving?") that turns into an AI-generated list of restaurants.
2. **TikTok Search (Search tab)** — A free-text search ("matcha in San Diego") that pulls real TikTok videos, extracts the restaurants people are actually talking about, and ranks them.

Both flows end on a Google-Places-enriched card with photos, ratings, hours, and a map pin. Tapping a card opens a detail sheet with TikToks of that specific restaurant.

There is also a **share extension** (`biluShare`) that lets users send a TikTok URL into bilu directly from the TikTok app.

---

## 2. High-level architecture

```
┌────────────────────── iOS App (SwiftUI, MVVM) ─────────────────────┐
│                                                                     │
│  HomeView ──► HomeViewModel ──┐                                     │
│  SearchView ──► SearchViewModel ──┐                                 │
│                                   │                                 │
│  Services: GeminiService, TikTokService,                            │
│            LocationExtractionService, LocationService               │
│                                   │                                 │
└───────────────────────────────────┼─────────────────────────────────┘
                                    │ HTTPS
┌───────────────────────────────────┼─────────────────────────────────┐
│                Supabase Edge Functions (Deno + TS)                  │
│                                                                     │
│   /recommendations  ── Gemini 2.5 Flash, 3-layer retry              │
│   /enrich           ── Google Places lookup + photos                │
│   /tiktok-search    ── Apify ScrapTik scraper                       │
│   /tiktok-locations ── Gemini Flash Lite + Places + ranking         │
│   /photos           ── Photo gallery for a place                    │
│                                                                     │
│   _shared/places.ts ── place_id resolution + 30-day cache           │
└─────────────────────────────────────────────────────────────────────┘
                │                │                  │
        Google Gemini    Google Places API    Apify (TikTok)
```

Rules of thumb:

- **ViewModels own logic, Views own layout.** No `URLSession` calls inside a `View`.
- **The iOS app holds no API keys** for Gemini, Places, or Apify. Those keys live in edge function environment variables. The app only knows the Supabase anon key.
- **The shared file [_shared/places.ts](supabase/functions/_shared/places.ts) is the single source of truth** for everything Google Places. Both `/enrich` and `/tiktok-locations` call into it, which is why caching and place_id resolution are consistent across both flows.

---

## 3. The Vibe Search (Home tab)

This is the survey-driven flow. The user answers a few structured questions, and we ask Gemini for restaurant suggestions.

### 3.1 The survey state machine

[HomeViewModel.swift](bilu/ViewModels/HomeViewModel.swift) owns a `Step` enum that drives the screen:

```
occasion → keyQuestion → foodFeeling → drinksSubFlow → location → loading → reveal
```

Every selection writes into a single struct, [VibeSelection](bilu/Models/VibeSelection.swift). When the user hits "Submit", `submitSurvey()` ([HomeViewModel.swift:466](bilu/ViewModels/HomeViewModel.swift#L466)) takes over.

### 3.2 Building the prompt

The natural-language prompt is built by [PromptBuilder.swift](bilu/Services/PromptBuilder.swift), which reads the `VibeSelection` and stitches together strings from [PromptConstants.swift](bilu/Models/PromptConstants.swift).

Each UI choice maps to a sentence. For example, picking the "🔥 Trending" vibe inserts:

> Prioritize spots with real buzz right now — viral on TikTok, talked about on Reddit and Yelp, with recent media attention. Long lines and a wait are expected and fine.

The final prompt has four parts:

1. **Opening line** — "Find 5 exceptional spots for *[occasion]* in *[location]*" (or "within *N* miles" if the user used the radius map widget).
2. **Mission lines** — occasion + key question + food feelings + vibe.
3. **Constraints** — only added if the user opened the fine-tune sheet (price, party size, open now, parking, accessibility).
4. **Task block** — "Return up to 5 results as JSON: …".

The prompt is intentionally small and human-readable. We do **not** send a JSON schema in the user prompt; we lean on Gemini's `responseMimeType: application/json` plus a tight system instruction.

### 3.3 The three-layer retry / temperature ladder

This is the most important non-obvious part of the Vibe flow. The edge function [recommendations/index.ts](supabase/functions/recommendations/index.ts) does **not** just call Gemini once. It tries up to three times with progressively looser parameters:

| Layer | Temperature | Prompt | What triggers fallback to next layer |
|-------|-------------|--------|--------------------------------------|
| **1. Strict**       | 0.1 | The full PromptBuilder prompt | Empty array, JSON parse failure, prose response, network error |
| **2. Exploratory**  | 0.7 | Same prompt | Same conditions as Layer 1 |
| **3. Relaxed**      | 0.4 | A *different*, shorter prompt that drops constraints | This layer is the floor — we always return its result |

The `relaxed: true` flag travels back up to the iOS client. If Layer 3 was used, the UI shows a soft banner: *"We loosened your filters to find these."* The banner is implemented via `lastSearchWasRelaxed` on `HomeViewModel`.

**Why three layers?** Empirically:

- Temperature 0.1 is great when Gemini knows the area well. When it doesn't, it sometimes returns `{"recommendations": []}` rather than guess — which is technically correct but useless to the user.
- Temperature 0.7 reshuffles which grounding chunks Gemini reaches for. About 5–10% of strict-empty calls succeed at this layer.
- Temperature 0.4 + a relaxed prompt is the safety net. We strip the user's vibe/occasion constraints and ask for "5 popular, highly-rated spots". Almost nothing fails here.

The retry ladder is loosening *creativity* (temperature) at Layer 2 and loosening *the prompt itself* at Layer 3. They are different knobs.

### 3.4 Two-phase result reveal

Gemini gives us names and explanations, but no photos, ratings, hours, or coordinates. We could fetch all of that before showing anything, but that would mean the user stares at a spinner for 5–7 seconds.

Instead, we split the response into two phases:

- **Phase 1 — `/recommendations` (≈2s):** Returns 5 cards with name, dish, explanation, and a `mapsUrl`. The UI flips to the `.reveal` step the moment this returns.
- **Phase 2 — `/enrich` (≈3–5s, in parallel):** [GeminiService.swift](bilu/Services/GeminiService.swift) kicks off a second request that hits [enrich/index.ts](supabase/functions/enrich/index.ts), which fans out to Google Places. As enrichment completes, photos and ratings stream into the cards.

This is the same pattern airlines use: show the flight list first, fill in seat counts second. The user never waits longer than they have to.

---

## 4. The TikTok Search (Search tab)

This is the more interesting system. The user types something like "matcha in San Diego", and we return a ranked list of real restaurants extracted from real TikToks.

### 4.1 Pipeline overview

```
query  ──►  /tiktok-search   ──►  10 TikTok videos (Apify)
       │                                │
       │                                ▼
       └────►  /tiktok-locations  ──►  fetch transcripts (WebVTT)
                                  ──►  Gemini extracts places per video
                                  ──►  tally views + dedup + rank
                                  ──►  geocode top N via Google Places
                                  ──►  return top 12
```

### 4.2 Fetching the videos

[TikTokService.swift](bilu/Services/TikTokService.swift) calls the [tiktok-search](supabase/functions/tiktok-search/index.ts) edge function, which proxies to **Apify's ScrapTik actor**. We do not talk to TikTok directly — they have no public search API for our use case, so we lean on a third-party scraper.

Apify gives us up to 10 videos per query with: video id, description (caption), author, view count, share URL, and a transcript URL (WebVTT format).

The client also runs a **city-hint regex** before sending the request ([SearchViewModel.swift](bilu/ViewModels/SearchViewModel.swift) `hasCityHint`). If the query doesn't contain "in *[city]*" or a known city name, we don't even bother calling the backend — we ask the user to pick a city first. This saves money and produces better results.

### 4.3 Caption vs. transcript — the most important rule in this codebase

Every TikTok we fetch has two text signals:

- **Caption** (a.k.a. `desc`): the text the creator typed into the post.
- **Transcript**: TikTok's auto-generated voiceover transcript.

We use them for **completely different purposes**, and getting this wrong is the easiest way to break the ranking quality.

> **Rule (from the system instruction in [tiktok-locations/index.ts:128](supabase/functions/tiktok-locations/index.ts#L128)):**
>
> *"TRANSCRIPT (the creator's spoken voiceover) is the PRIMARY source of venue names. Captions are secondary context. Set `area` ONLY if the CAPTION (NOT the transcript) explicitly states a neighborhood/sub-area for this venue. DO NOT extract area from the TRANSCRIPT field — auto-generated captions misspell neighborhoods (e.g., "K-Town" mistranscribed as "Katy Town"). Transcripts are NOT a trustworthy source of neighborhood names."*

Why:

- **Humans pronounce restaurant names clearly out loud.** "Cote", "Sushi Kaneyoshi", "Goji" — the transcript is the cleanest source we have for the actual venue name.
- **Auto-captions butcher proper nouns for neighborhoods.** "K-Town" comes out as "Katy Town", "WeHo" as "we ho", "SoHo" as "so ho". Text the creator *typed* (the caption) is the safe place to read neighborhoods from.

So the payload to Gemini is asymmetric: the transcript is sent in full (capped at 3000 chars), but only the first 500 chars of the caption are sent.

### 4.4 Extracting places with Gemini

The model is **gemini-2.5-flash-lite** ([tiktok-locations/index.ts:15](supabase/functions/tiktok-locations/index.ts#L15)) — a smaller, cheaper, faster sibling of the model used by Vibe Search. We don't need creative reasoning here; we need fast structured extraction.

Temperature is **0.1**, response is a strict JSON schema:

```json
{
  "queryCity": "Los Angeles" | null,
  "videos": [{
    "videoId": "...",
    "places": [{
      "name": "Cote",
      "area": "K-Town" | null,
      "confidence": "high" | "medium" | "low"
    }]
  }]
}
```

`queryCity` is extracted from the *user's search query*, not the videos. The system instruction normalizes ("LA" → "Los Angeles", "Brooklyn" → "New York", "Santa Monica" → "Los Angeles") so that downstream geocoding has a clean city to bias against.

If `queryCity` is null, the edge function returns `HTTP 400 { error: "missing_city", suggestedCities: [...] }` and the iOS UI renders city chips for the user to pick from.

### 4.5 The ranking formula — view tally + video count + rating

After extraction, we have a list of `(videoId, place_name, confidence, area)` rows. We want to turn that into a ranked list of restaurants.

The math lives in [tiktok-locations/index.ts:366-461](supabase/functions/tiktok-locations/index.ts#L366-L461). Three steps:

**Step 1 — Tally per name.** For each unique place name (case-insensitive):

- Drop any row where `confidence == "low"`. We'd rather show fewer high-quality results than pad with noise.
- Sum `viewCount` across all videos that mention it.
- Track the set of distinct video IDs that mention it.
- Vote on `area` (caption-extracted neighborhoods only) — plurality wins, ties broken by confidence rank.

**Step 2 — Pre-score (no rating yet):**

```
preScore = log(totalViews + 1) × (1 + 0.3 × videoCount)
```

Two design choices to call out:

1. **`log(totalViews + 1)` instead of raw views.** One mega-viral video shouldn't drown out the rest of the list. Log scaling means going from 100k to 1M views is worth about as much as going from 10k to 100k — it rewards reach without flattening the long tail.
2. **30% bonus per additional video.** A place mentioned in 3 separate TikToks is a stronger signal than a place mentioned in 1 viral one. The multiplier is `1 + 0.3 × videoCount`: 1 video = 1.0×, 2 videos = 1.3×, 3 videos = 1.6×.

**Worked example:**

| Place | totalViews | videoCount | preScore |
|-------|-----------:|-----------:|---------:|
| A     | 200,000    | 1          | log(200,001) × 1.0 = **12.21** |
| B     | 100,000    | 2          | log(100,001) × 1.3 = **14.97** |

Place B wins, even though it has half the views. Two creators independently mentioning it is a stronger endorsement than one creator going viral.

**Step 3 — Geocode top 17 names, then full score with rating:**

We only geocode the top `TOP_N + 5 = 17` (saves Places API calls), then compute:

```
fullScore = preScore × max(0.5, rating / 4.0)
```

A 5-star place gets a 1.25× boost. A 2-star place is halved. Missing rating means 1.0× (no penalty). The `max(0.5, …)` clamp prevents a single 1-star outlier from collapsing the score to zero — we still want to show it if the TikTok signal is strong.

### 4.6 Per-video diversity cap

The ranking formula above tells us *which venues* are best, but it has a blind spot: when one mega-viral roundup video lists 8 places, all 8 inherit that video's massive `totalViews` and end up dominating the result page. The user's map fills with pins that all play the same video when tapped — bad discovery UX, and it hides the contributions of the other 9 videos we fetched.

**The fix:** each video can contribute at most **`PER_VIDEO_SOLO_CAP = 4` places that are exclusive to it**. Places mentioned by ≥2 different videos (corroborated) bypass the cap entirely.

The corroboration exemption is the heart of the design. If five different creators all independently call out "Bavel," that's exactly the cross-creator agreement we want to surface — we'd never want to drop one of those five. The cap only fights the failure mode it was built for: a single creator's exclusive picks crowding out everyone else.

This step lives in [tiktok-locations/index.ts](supabase/functions/tiktok-locations/index.ts) (`applyPerVideoSoloCap`), inserted between `buildNameTallies` and the geocoding slice:

1. **Split tallies in two buckets:**
   - **Corroborated** (`videoIds.size ≥ 2`) → free pass, kept as-is.
   - **Solo** (`videoIds.size == 1`) → grouped by their single video.

2. **Within each video's solos, sort by `bestConfidence` (then `preScore`).** All solos from one video share the same `totalViews` and `videoCount = 1`, so their `preScore` is identical — confidence is the only meaningful tiebreaker. Gemini already labels every place `high` or `medium` (`low` is filtered earlier in `buildNameTallies`), so we just preserve and use that signal.

3. **Keep the top 4 solos per video, drop the rest.** Re-merge with the corroborated tallies, sort by `preScore` descending, hand off to the existing `slice(0, GEOCODE_LIMIT)`.

**Worked example:**

A search returns:

| Video | Views | Solos (exclusive picks) | Corroborated picks (also in other videos) |
|-------|------:|---|---|
| A     | 1.5M  | 8 places (none seen elsewhere) | 0 |
| B     | 200k  | 1 place | 2 places (each also mentioned by 2 other videos) |
| C     | 150k  | 0 | 1 place (also mentioned by D and E) |
| D, E  | 100k each | a few each | (overlapping with B and C above) |

Without the cap, all 8 of A's solos would rank above most of B/C/D/E's contributions because A's view count dominates. The map ends up showing 8 pins from A, plus a couple of stragglers — and tapping different pins keeps replaying A's video.

With `PER_VIDEO_SOLO_CAP = 4`:

- A keeps its top 4 solos by confidence (the four where Gemini said "high"). Drops 4.
- B keeps 1 solo + 2 corroborated. Total: 3.
- C keeps 0 solos + 1 corroborated. Total: 1.
- D, E keep their share.

Final geocoded list: ~10–12 unique venues, sourced from 4–5 different videos. Tapping different pins now plays different creators.

**Design choices to call out:**

1. **Solos only, never corroborated.** A 5-way agreement across creators is the highest-quality signal in the system. Capping that would actively destroy useful information.
2. **Confidence > preScore as tiebreaker.** Within one video's solos, preScore is constant. Gemini's `high`/`medium` confidence is the only differentiating signal — and it's free, since we already extract it.
3. **No "skip cap when <4 videos" guard.** If only 2 videos contributed, you still get up to 8 (4×2) solos plus any corroborated — better than today's behavior of letting one video swamp.

**Tuning:** the only knob is `PER_VIDEO_SOLO_CAP` at the top of [tiktok-locations/index.ts](supabase/functions/tiktok-locations/index.ts). Lower it (3) for tighter diversity, raise it (5–6) if niche queries return suspiciously thin maps.

### 4.7 Dedup by place_id with `max`, not `sum`

Different creators say the same restaurant differently: "Fairgrounds", "Fairgrounds LA", "The Fairgrounds Coffee". After geocoding, all three resolve to the same Google `place_id`. We merge them into a single entry, but with a subtle rule:

- `totalViews` → **sum** across name variants (additional reach is real reach).
- `videoIds` → **union** (3 videos is 3 videos regardless of name spelling).
- `preScore` → **max**, not sum.

Why `max` for preScore? The preScore already encodes the per-video bonus. Summing would double-count: imagine "Fairgrounds" got `preScore = 10` from 1 video and "Fairgrounds LA" got `preScore = 12` from 2 videos. Those are the same 1+2=3 videos. Summing would give 22; that's wrong because the same videos are being counted twice. Taking the max (12) gives us the strongest signal we observed for that placeId.

Top 12 results are returned to the client, sorted by `fullScore` descending.

---

## 5. Google Places integration (shared by both flows)

Everything Places-related lives in [_shared/places.ts](supabase/functions/_shared/places.ts).

### 5.1 Resolving a name to a place_id

Three approaches, in order. We stop at the first one that works.

1. **Parse the `mapsUrl` Gemini gave us.** Regex looks for `query_place_id=ChIJ...` or a bare `ChIJ...` token. Gemini's grounding usually produces valid URLs; this is the cheapest path.
2. **Look in the response's grounding chunks.** Gemini's `groundingMetadata.groundingChunks[].maps.placeId` is matched fuzzily against the recommendation name.
3. **Text search fallback.** POST `https://places.googleapis.com/v1/places:searchText` with `[name] [searchArea]`. Location-biased to the user's city (40km radius for TikTok search, 1 mile for radius-mode Vibe search).

Field mask is always `places.id` only — we do **not** ask for details here, just the id. Details come next.

### 5.2 Two-layer cache (30-day TTL)

| Table | Key | Value | Saves |
|-------|-----|-------|-------|
| `place_name_cache` | `lower("{name}|{area}|{city}")` | place_id | A `places:searchText` call (~$0.04) |
| `places_cache`     | place_id | rating, reviews, hours, address, phone, website, lat/lng, neighborhood, photo refs | A `places/{id}` details call (~$0.04) and lets us skip rebuilding metadata |

**Photos are stored as references, not URIs.** Google's photo URIs are short-lived signed URLs that expire. We cache the photo *resource name* (e.g., `places/X/photos/Y`) and re-fetch the URI on demand at 400px wide for the hero, full-size for the gallery.

### 5.3 City normalization for TikTok search

Cities are messy. The system instruction normalizes them before geocoding:

- "LA" / "Los Angeles" / "Santa Monica" / "Venice" → `Los Angeles`
- "NYC" / "New York" / "Brooklyn" / "Queens" → `New York`
- "K-Town" → `Koreatown` (sub-area, retained for `area` field but Place bias uses parent city)

This avoids the problem of "Brooklyn" geocoding to a tiny park in Iowa.

### 5.4 Place Details billing tier — we run on Pro

Google's Places API (New) bills `places/{id}` details by **field mask tier**. The single most expensive field in the mask sets the SKU for the *entire* call.

| Tier | Approx cost | Includes |
|---|---|---|
| **Essentials** | ~$5 / 1k | `displayName`, `location`, `formattedAddress`, `addressComponents`, `photos` (refs), `types`, `googleMapsUri`, `plusCode` |
| **Pro** | ~$20 / 1k | Everything in Essentials, plus `rating`, `userRatingCount`, `regularOpeningHours` (`openNow`), `nationalPhoneNumber`, `websiteUri`, `priceLevel`, `businessStatus` |
| **Enterprise** | ~$25+ / 1k | Reviews text, ambience flags (outdoor seating, dineIn, takeout), EV/parking, `editorialSummary` |

bilu's field mask in [_shared/places.ts](supabase/functions/_shared/places.ts) (`fetchPlaceDetails`) is:

```
displayName, photos, location, rating, userRatingCount,
regularOpeningHours, formattedAddress, nationalPhoneNumber,
websiteUri, addressComponents
```

`rating`, `userRatingCount`, `regularOpeningHours`, `nationalPhoneNumber`, and `websiteUri` are all Pro fields, so every cache-miss details call lands in the Pro SKU at ~$0.02.

**Why we accept the cost (instead of dropping to Essentials):**

1. **`rating` is mixed into the ranking formula** at [tiktok-locations/index.ts](supabase/functions/tiktok-locations/index.ts) — `fullScore = preScore × max(0.5, rating/4.0)`. Without it, a viral-but-mediocre venue can outrank a 4.8★ spot with fewer videos. See §4.5.
2. **`regularOpeningHours.openNow`** powers the "Open Now" filter chip on the Search results map.
3. **`nationalPhoneNumber` + `websiteUri`** drive the call/website buttons in the restaurant detail sheet.

The two-layer cache (§5.2) absorbs most of this: once a venue is cached, tier doesn't matter — repeat queries pay $0. The Pro-vs-Essentials gap only shows up on cold venues.

#### How to downgrade to Essentials (~4× cheaper per cold venue)

Two routes, neither free in product terms:

**Route A — drop rating from the ranking, keep the UI signals on detail-sheet only.**

1. Remove `rating`, `userRatingCount`, `regularOpeningHours`, `nationalPhoneNumber`, `websiteUri` from `fetchPlaceDetails`'s field mask in [_shared/places.ts](supabase/functions/_shared/places.ts) — list/map enrichment becomes Essentials.
2. Update the score formula in [tiktok-locations/index.ts](supabase/functions/tiktok-locations/index.ts) (`computeFullScore`) to use only `preScore` (i.e. drop the `ratingMultiplier`). Ranking becomes pure `log(views) × videoCount`.
3. Remove the "Open Now" filter from `SearchViewModel` and `SearchView`.
4. On detail-sheet open, fire a *second* Place Details call at the Pro field mask just for that one venue, cached separately if you want. Phone, website, hours, rating render only in the detail sheet.

**Route B — keep current UX, drop only `rating`-based ranking.**

Simpler but smaller savings. Keep the field mask as-is; just change the score formula to ignore rating. You're still paying Pro tier for the data — you've only removed the ranking dependency on it. This is one line of code: in `computeFullScore`, return `preScore` directly. Useful as a stepping stone toward Route A.

**When to revisit:** Pro tier only matters at cold-venue scale. If your Place Details bill is ever a real number, that almost certainly means a lot of users hit a lot of new venues — at which point caching ROI is also at its highest, so Route A's value is largest.

---

## 6. The share extension (biluShare)

[biluShare/](biluShare/) is a separate iOS extension target. It appears in the iOS share sheet so users can send a TikTok URL into bilu without copy-pasting.

- [ShareViewController.swift](biluShare/ShareViewController.swift) reads the `NSExtensionItem`. It tries `UTType.url` first, then falls back to plain text (TikTok sometimes shares text-with-URL instead of a real URL).
- [ShareRootView.swift](biluShare/ShareRootView.swift) renders a SwiftUI sheet with drag-to-dismiss (per the gesture-first principle in CLAUDE.md).
- The main app and extension share an **App Group**: `group.com.bilu.shared`. Configured in [bilu.entitlements](bilu/bilu.entitlements) and `biluShare/biluShare.entitlements`. This lets the extension write to a shared container the main app can read on next launch.

---

## 7. Error handling philosophy

**Never block the user. Degrade gracefully.** Every system has a defined "what shows up if this fails" answer.

| Failure | What we do |
|---------|------------|
| Gemini returns `{recommendations: []}` | Retry with higher temp (Layer 2), then with relaxed prompt (Layer 3). |
| Gemini returns prose instead of JSON | Treated as a parse failure; retry ladder kicks in. |
| Network error to `/recommendations` | `SearchFailure.transportError` → user sees "Something went wrong". |
| TikTok video has no transcript URL | Treat transcript as empty string; Gemini still extracts from caption. |
| Gemini extracts no city | HTTP 400 with `suggestedCities`. UI shows city chips. |
| Place text-search returns no place_id | That venue is dropped from results, not surfaced as an error. |
| Place details fetch fails | Card renders with name + explanation but no photo/rating. |
| Photo URI fetch fails | Card uses the original `mapsUrl` as a fallback link; image slot empty. |
| Cache write fails | Swallowed silently. Cache is a perf optimization, not a correctness boundary. |

The key insight: **a partial result is almost always better than no result.** A card with a name and explanation but no photo is still useful. An error screen never is.

---

## 8. API costs (per search)

These are rough estimates. Confirm with current Google / Apify pricing before making business decisions.

### 8.1 Vibe Search (Home tab)

| Component | Calls | Unit cost | Cost |
|-----------|------:|----------:|-----:|
| Gemini 2.5 Flash (Layer 1) | 1 | ~$0.0001 | ~$0.0001 |
| Gemini retries (5–10% of requests) | 0–2 | ~$0.0001 | ~$0.0001 amortized |
| Places `searchText` (only when `mapsUrl` parse fails) | 0–1 | $0.04 | $0–$0.04 |
| Places `places/{id}` details × 5 (cache miss) | 5 | $0.04 | $0.20 |
| Places photo media × 5 (hero only) | 5 | $0.007 | $0.035 |

- **First search, full cache miss:** ~**$0.025 – $0.04** per user search.
- **Cached repeat search:** ~**$0.005 – $0.010**.
- **Average at ~70% cache hit:** ~**$0.015 – $0.025**.

### 8.2 TikTok Search (Search tab)

| Component | Calls | Unit cost | Cost |
|-----------|------:|----------:|-----:|
| Apify ScrapTik | 1 (10 videos) | ~$0.002 | ~$0.002 |
| Gemini 2.5 Flash Lite (extraction) | 1 | ~$0.0001 | ~$0.0001 |
| Places `searchText` × ~15–20 (geocoding top names) | 15–20 | $0.04 | $0.60 – $0.80 |
| Places details × ~8 (final results) | 8 | $0.04 | $0.32 |
| Places photo media × ~8 | 8 | $0.007 | $0.056 |

- **First search, cold cache:** ~**$0.92 – $1.14** per user search.
- **Cached repeat search:** drops dramatically — most cost is in `searchText` calls, which are cached by `(name, area, city)` for 30 days.

### 8.3 Cost takeaways

- **Google Places dominates both flows.** Gemini is rounding-error cheap; the real spend is in `searchText` and `details` calls.
- **TikTok Search is ~30× more expensive than Vibe Search**, primarily because we have to geocode 15+ name variants per query.
- The **two-layer Places cache** is a cost system, not just a perf system. Without it, repeat searches in popular cities would cost the same as cold searches.
- Reducing TikTok Search from 10 videos → 5 videos cuts cost roughly in half. We currently default to 10 because the ranking quality drops noticeably below that (the per-video bonus and dedup logic both need ≥2 videos to do anything useful).

---

## 9. File index — where to look

| Concept | File | Notable lines |
|---------|------|---------------|
| App entry point, tabs | [bilu/biluApp.swift](bilu/biluApp.swift), [bilu/ContentView.swift](bilu/ContentView.swift) | — |
| Vibe survey state machine | [bilu/ViewModels/HomeViewModel.swift](bilu/ViewModels/HomeViewModel.swift) | `submitSurvey()` ~466 |
| Vibe prompt construction | [bilu/Services/PromptBuilder.swift](bilu/Services/PromptBuilder.swift) + [bilu/Models/PromptConstants.swift](bilu/Models/PromptConstants.swift) | — |
| Vibe edge function + 3-layer retry | [supabase/functions/recommendations/index.ts](supabase/functions/recommendations/index.ts) | retry ladder ~119–163 |
| Two-phase Vibe client | [bilu/Services/GeminiService.swift](bilu/Services/GeminiService.swift) | — |
| Places enrichment edge function | [supabase/functions/enrich/index.ts](supabase/functions/enrich/index.ts) | — |
| TikTok search edge function | [supabase/functions/tiktok-search/index.ts](supabase/functions/tiktok-search/index.ts) | — |
| TikTok client | [bilu/Services/TikTokService.swift](bilu/Services/TikTokService.swift) | — |
| TikTok Search VM (city hint check) | [bilu/ViewModels/SearchViewModel.swift](bilu/ViewModels/SearchViewModel.swift) | `hasCityHint` ~184 |
| Location extraction client | [bilu/Services/LocationExtractionService.swift](bilu/Services/LocationExtractionService.swift) | — |
| Caption-vs-transcript rule (system instruction) | [supabase/functions/tiktok-locations/index.ts](supabase/functions/tiktok-locations/index.ts) | ~128–160 |
| View-tally + scoring formula | [supabase/functions/tiktok-locations/index.ts](supabase/functions/tiktok-locations/index.ts) | ~366–461 |
| Dedup-by-place_id logic | [supabase/functions/tiktok-locations/index.ts](supabase/functions/tiktok-locations/index.ts) | ~565–588 |
| Place_id resolution + Places cache | [supabase/functions/_shared/places.ts](supabase/functions/_shared/places.ts) | — |
| Photo gallery edge function | [supabase/functions/photos/index.ts](supabase/functions/photos/index.ts) | — |
| Models | [bilu/Models/](bilu/Models/) — `Recommendation`, `TikTokVideo`, `SearchLocation`, `VibeSelection`, `PromptConstants` | — |
| Design tokens (colors, fonts) | [bilu/Helpers/AppTheme.swift](bilu/Helpers/AppTheme.swift) | — |
| Share extension | [biluShare/ShareViewController.swift](biluShare/ShareViewController.swift), [biluShare/ShareRootView.swift](biluShare/ShareRootView.swift) | — |

---

## 10. Things to remember when working in this codebase

- **Don't add a 4th retry layer.** If Layer 3 fails consistently, the prompt itself is wrong, not the temperature.
- **Don't read `area` from the transcript.** This will silently introduce neighborhood mistranscriptions ("Katy Town"). Caption only.
- **Don't sum preScores when deduping by place_id.** Same videos counted twice. Use `max`.
- **Don't cache photo URIs.** They expire. Cache the resource name, fetch on demand.
- **Don't add API keys to the iOS app.** All secrets live in Supabase edge function env vars.
- **Don't block the UI on enrichment.** Cards reveal first, photos and ratings stream in.
