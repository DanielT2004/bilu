import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { GoogleGenAI } from "npm:@google/genai@1.46.0";
import {
  resolvePlaceIdByTextSearch,
  geocodeCityToCoord,
  getCachedPlaceIdByName,
  upsertPlaceNameCache,
  getCachedPlace,
  upsertCachedPlace,
  fetchPlaceDetails,
  type LocationBias,
} from "../_shared/places.ts";
import {
  consumePaidAPIQuota,
  paidAPIAccessErrorResponse,
  quotaHeaders,
  quotaPolicy,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";

/** Lightweight Gemini model for location extraction — see https://ai.google.dev/gemini-api/docs */
const GEMINI_MODEL = "gemini-3.5-flash-lite";

/** Top N venues actually returned to the client. */
const TOP_N = 12;
/** Buffer geocoded above TOP_N to absorb dedupe collapses + geocode failures. */
const GEOCODE_LIMIT = TOP_N + 5;
/** Radius around the queryCity used as locationBias on every venue textSearch. */
const CITY_BIAS_RADIUS_METERS = 40_000;
/** Max places a single video can contribute IF those places aren't corroborated by other videos.
 *  Corroborated places (mentioned in ≥2 videos) bypass this cap — overlap is our strongest quality signal. */
const PER_VIDEO_SOLO_CAP = 4;
const MAX_INPUT_VIDEOS = 25;
const PAID_API_QUOTA = quotaPolicy("tiktok_locations", "TIKTOK_LOCATIONS", 10, 40, 1_000);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Expose-Headers": "retry-after, x-ratelimit-remaining, x-daily-budget-remaining, x-global-daily-budget-remaining",
};

interface VideoAnchor {
  keyword: string;
  categoryName?: string;
  poiClassName?: string;
  lat?: number;
  lng?: number;
}

interface VideoInput {
  videoId: string;
  desc: string;
  viewCount: number;
  shareUrl: string;
  transcriptUrl?: string;
  anchors?: VideoAnchor[];
}

interface RequestBody {
  videos: VideoInput[];
  searchQuery: string;
  latitude?: number;
  longitude?: number;
}

type Confidence = "high" | "medium" | "low";

interface PlaceHit {
  name: string;
  area: string | null;
  confidence: Confidence;
}

interface ExtractedVideo {
  videoId: string;
  places: PlaceHit[];
}

interface GeminiResponse {
  queryCity: string | null;
  videos: ExtractedVideo[];
}

interface LocationOutput {
  placeId: string;
  placeName: string;
  address: string;
  lat: number;
  lng: number;
  rank: number;
  totalViews: number;
  videoIds: string[];
  videoCount: number;
  rating: number | null;
  isOpen: boolean | null;
  neighborhood: string | null;
  score: number;
}

// ── Transcript fetching + parsing ─────────────────────────────────────────────

/**
 * Fetch a TikTok WebVTT auto-caption URL and return the spoken text only.
 * Strips timing cues and WEBVTT header, collapses to a single paragraph, caps at 3000 chars.
 * Returns "" on any failure — missing transcript must not break the pipeline.
 */
async function fetchTranscript(url: string): Promise<string> {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return "";
    const raw = await res.text();

    const textLines: string[] = [];
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      if (trimmed === "WEBVTT" || trimmed.startsWith("WEBVTT")) continue;
      if (trimmed.includes("-->")) continue;
      if (/^\d+$/.test(trimmed)) continue;
      if (/^\d{2}:\d{2}:\d{2}/.test(trimmed)) continue;
      textLines.push(trimmed);
    }

    const combined = textLines.join(" ").replace(/\s+/g, " ").trim();
    return combined.slice(0, 3000);
  } catch {
    return "";
  }
}

// ── Gemini: caption + transcript → { queryCity, videos: [{ videoId, places }] } ─

async function extractPlacesAndCity(
  videos: VideoInput[],
  transcripts: string[],
  searchQuery: string,
  geminiApiKey: string
): Promise<GeminiResponse> {
  const ai = new GoogleGenAI({ apiKey: geminiApiKey });

  const systemInstruction = `You extract a city and venue names from a user's TikTok food search.

OUTPUT
{
  "queryCity": string | null,
  "videos": [{ "videoId": string, "places": [{ "name": string, "area": string|null, "confidence": "high"|"medium"|"low" }] }]
}

queryCity:
  - Extract the city or metro area the USER is searching in from their query string.
  - Normalize to canonical metro names: "LA"→"Los Angeles", "NYC"/"NY"→"New York", "SF"→"San Francisco", "DC"→"Washington", "K-Town"/"Koreatown"→"Los Angeles".
  - For neighborhoods, return the parent metro (e.g. "Brooklyn"→"New York", "Santa Monica"→"Los Angeles").
  - If the query has no city/location word, return null.

places (per video):
  - TRANSCRIPT (the creator's spoken voiceover) is the PRIMARY source of venue names. Captions are secondary context.
  - For roundup / "top N" / list-style videos, extract EVERY named venue the creator describes visiting.
  - Only extract venues the creator actually VISITED. Skip recipes, copycats, DIY, "how to make at home" — return empty places array for those.
  - DO NOT include city/neighborhood in the venue name (we'll add city ourselves at geocode time). Just the venue name as the creator says it.

area (per place):
  - Set ONLY if the CAPTION (NOT the transcript) explicitly states a neighborhood/sub-area for this venue.
  - Strong signals: pin emoji "📍 Place, Neighborhood"; "@Place in Neighborhood"; "located in X"; "Place — Neighborhood, City"; clear neighborhood hashtags adjacent to the venue mention (e.g. "#weho #ggiata" → "West Hollywood").
  - DO NOT extract area from the TRANSCRIPT field — auto-generated captions misspell neighborhoods (e.g. "K-Town" mistranscribed as "Katy Town"). Transcripts are NOT a trustworthy source of neighborhood names.
  - When in doubt, set area to null. A null area is always safe; a wrong area sends users to the wrong place.
  - Use the canonical neighborhood name when possible (e.g. "WeHo" → "West Hollywood", "DTLA" → "Downtown Los Angeles", "K-Town" → "Koreatown").

confidence:
  - "high": creator explicitly visited and recommended this venue (e.g. "I love X", "this is the best Y at Z")
  - "medium": named in a list with positive context but not a clear recommendation
  - "low": briefly listed, mentioned in passing, unclear whether visited

Quality bar: When in doubt, return fewer places. A smaller, accurate list is better than a scattered one.`;

  const payload = videos.map((v, i) => ({
    videoId: v.videoId,
    caption: v.desc.slice(0, 500),
    transcript: transcripts[i] || "",
  }));

  const prompt = `User search query: "${searchQuery}"

Extract queryCity from the search query above, and the list of named venues from each video below.

${JSON.stringify(payload, null, 2)}`;

  console.log("[tiktok-locations] ── GEMINI CALL ──");
  console.log("[tiktok-locations] Model:", GEMINI_MODEL);
  console.log("[tiktok-locations] Videos:", videos.length);
  console.log("[tiktok-locations] Query:", searchQuery);
  console.log("[tiktok-locations] Prompt size:", prompt.length, "chars");
  for (let i = 0; i < videos.length; i++) {
    const v = videos[i];
    const t = transcripts[i] || "";
    const transcriptPreview = t ? `"${t.slice(0, 120)}${t.length > 120 ? "..." : ""}"` : "MISSING";
    console.log(`  [${v.videoId.slice(0, 12)}] desc(${v.desc.length}) transcript(${t.length})`);
    console.log(`           desc: "${v.desc.slice(0, 80).replace(/\n/g, " ")}"`);
    console.log(`           transcript: ${transcriptPreview}`);
  }

  const emptyFallback = (): GeminiResponse => ({
    queryCity: null,
    videos: videos.map((v) => ({ videoId: v.videoId, places: [] })),
  });

  const response = await ai.models.generateContent({
    model: GEMINI_MODEL,
    contents: prompt,
    config: {
      systemInstruction,
      temperature: 0.1,
      responseMimeType: "application/json",
      responseSchema: {
        type: "object" as const,
        properties: {
          queryCity: {
            type: "string" as const,
            description: "Canonical metro extracted from the user's query, or null if absent.",
            nullable: true,
          },
          videos: {
            type: "array" as const,
            items: {
              type: "object" as const,
              properties: {
                videoId: { type: "string" as const },
                places: {
                  type: "array" as const,
                  items: {
                    type: "object" as const,
                    properties: {
                      name: { type: "string" as const, description: "Venue name only — no city/neighborhood appended." },
                      area: {
                        type: "string" as const,
                        description: "Neighborhood/area, ONLY when explicitly typed in the caption. Null otherwise.",
                        nullable: true,
                      },
                      confidence: {
                        type: "string" as const,
                        enum: ["high", "medium", "low"],
                      },
                    },
                    required: ["name", "area", "confidence"],
                  },
                },
              },
              required: ["videoId", "places"],
            },
          },
        },
        required: ["queryCity", "videos"],
      },
    },
  });

  const rawText = response.text ?? "";
  console.log("[tiktok-locations] ── GEMINI RAW RESPONSE ──");
  console.log("[tiktok-locations] Raw text length:", rawText.length);
  console.log("[tiktok-locations] Raw text:", rawText.slice(0, 3000));

  if (!rawText.trim()) {
    console.warn("[tiktok-locations] Gemini returned empty text");
    return emptyFallback();
  }

  const cleaned = rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  try {
    const parsed = JSON.parse(cleaned) as GeminiResponse;
    if (!parsed || !Array.isArray(parsed.videos)) throw new Error("Response missing 'videos' array");
    console.log(`[tiktok-locations] queryCity: ${parsed.queryCity ?? "null"}`);
    for (const v of parsed.videos) {
      const summary = v.places?.length
        ? v.places.map((p) => `${p.name}${p.area ? ` (${p.area})` : ""}[${p.confidence}]`).join("; ")
        : "[]";
      console.log(`  [${v.videoId?.slice(0, 10)}] places: ${summary}`);
    }
    return parsed;
  } catch (e) {
    console.error("[tiktok-locations] Gemini JSON parse failed:", e, "snippet:", cleaned.slice(0, 400));
    return emptyFallback();
  }
}

// ── geocode + cache ───────────────────────────────────────────────────────────

interface GeocodedPlace {
  placeId: string;
  placeName: string;
  address: string;
  lat: number;
  lng: number;
  rating: number | null;
  isOpen: boolean | null;
  neighborhood: string | null;
}

/**
 * Resolve a venue name to a fully enriched place via two-layer cache:
 *   1. (name|city) → placeId  via place_name_cache  (skip textSearch on hit)
 *   2. placeId → metadata     via places_cache       (skip Place Details on hit)
 *
 * Steady state for popular venues: zero Places API calls.
 */
async function geocodePlace(
  placeName: string,
  area: string | null,
  queryCity: string,
  cityBias: LocationBias,
  placesApiKey: string
): Promise<GeocodedPlace | null> {
  // Cache key includes area so a query WITH neighborhood doesn't reuse a stale placeId
  // resolved without one (which is how we got Fairplex for "Fairgrounds LA").
  const nameKey = `${placeName}|${area ?? ""}|${queryCity}`.toLowerCase().trim();

  // 1. Resolve placeId — name cache or textSearch
  let placeId = await getCachedPlaceIdByName(nameKey);
  if (placeId) {
    console.log(`[cache] hit name_key="${nameKey}" → ${placeId}`);
  } else {
    const searchArea = area ? `${area} ${queryCity}` : queryCity;
    placeId = await resolvePlaceIdByTextSearch(
      placeName,
      placesApiKey,
      "tiktok-locations",
      searchArea,
      cityBias
    );
    if (!placeId) return null;
    await upsertPlaceNameCache(nameKey, placeId);
  }

  // 2. Resolve metadata — places_cache or Place Details
  const cached = await getCachedPlace(placeId);
  if (cached) {
    console.log(`[cache] hit place_id=${placeId}`);
    if (cached.latitude == null || cached.longitude == null) return null;
    return {
      placeId,
      placeName: placeName, // displayName not stored in places_cache; use input. Future: store displayName.
      address: cached.address ?? "",
      lat: cached.latitude,
      lng: cached.longitude,
      rating: cached.rating,
      isOpen: cached.is_open,
      neighborhood: cached.neighborhood,
    };
  }

  // Cache miss: fetch full details, persist, return
  const details = await fetchPlaceDetails(placeId, placesApiKey, "tiktok-locations");
  if (details.latitude === undefined || details.longitude === undefined) return null;

  await upsertCachedPlace({
    place_id: placeId,
    photo_refs: details.photoNames,
    rating: details.rating ?? null,
    review_count: details.reviewCount ?? null,
    is_open: details.isOpen ?? null,
    address: details.address ?? null,
    phone: details.phone ?? null,
    website: details.website ?? null,
    reviews: details.reviews ?? null,
    latitude: details.latitude,
    longitude: details.longitude,
    neighborhood: details.neighborhood ?? null,
  });

  return {
    placeId,
    placeName: details.displayName ?? placeName,
    address: details.address ?? "",
    lat: details.latitude,
    lng: details.longitude,
    rating: details.rating ?? null,
    isOpen: details.isOpen ?? null,
    neighborhood: details.neighborhood ?? null,
  };
}

// ── Tally + rank ──────────────────────────────────────────────────────────────

/** Per-name aggregate before geocoding. Same name across videos → same entry. */
interface NameTally {
  name: string;             // canonical version (first-seen casing)
  areaVotes: Map<string, { count: number; bestConfidence: Confidence }>;
  area: string | null;      // resolved after voting in finalize step
  totalViews: number;
  videoIds: Set<string>;    // distinct videos that mentioned this name
  preScore: number;         // log(views+1) × (1 + 0.3 × videoCount)
  bestConfidence: Confidence; // highest confidence seen across all mentions — tiebreaker when capping solos
}

function confidenceRank(c: Confidence): number {
  return c === "high" ? 3 : c === "medium" ? 2 : 1;
}

function resolveArea(votes: Map<string, { count: number; bestConfidence: Confidence }>): string | null {
  if (votes.size === 0) return null;
  let bestKey: string | null = null;
  let bestCount = 0;
  let bestConf: Confidence = "low";
  for (const [key, v] of votes) {
    if (
      v.count > bestCount ||
      (v.count === bestCount && confidenceRank(v.bestConfidence) > confidenceRank(bestConf))
    ) {
      bestKey = key;
      bestCount = v.count;
      bestConf = v.bestConfidence;
    }
  }
  return bestKey;
}

function buildNameTallies(videos: VideoInput[], extracted: ExtractedVideo[]): NameTally[] {
  const byName = new Map<string, NameTally>();

  for (const v of videos) {
    const ext = extracted.find((e) => e.videoId === v.videoId);
    if (!ext) continue;

    // Don't double-count the same name within one video.
    const seenInVideo = new Set<string>();
    for (const p of ext.places) {
      if (p.confidence === "low") continue;
      const trimmed = p.name?.trim();
      if (!trimmed) continue;

      const key = trimmed.toLowerCase();
      if (seenInVideo.has(key)) continue;
      seenInVideo.add(key);

      let tally = byName.get(key);
      if (!tally) {
        tally = {
          name: trimmed,
          areaVotes: new Map(),
          area: null,
          totalViews: 0,
          videoIds: new Set(),
          preScore: 0,
          bestConfidence: "low", // placeholder; overwritten below since "low" is filtered
        };
        byName.set(key, tally);
      }
      tally.videoIds.add(v.videoId);
      tally.totalViews += v.viewCount;
      if (confidenceRank(p.confidence) > confidenceRank(tally.bestConfidence)) {
        tally.bestConfidence = p.confidence;
      }

      if (p.area && p.area.trim()) {
        const areaKey = p.area.trim();
        const existing = tally.areaVotes.get(areaKey);
        if (existing) {
          existing.count += 1;
          if (confidenceRank(p.confidence) > confidenceRank(existing.bestConfidence)) {
            existing.bestConfidence = p.confidence;
          }
        } else {
          tally.areaVotes.set(areaKey, { count: 1, bestConfidence: p.confidence });
        }
      }
    }
  }

  // Resolve area + compute pre-score (no rating yet).
  for (const t of byName.values()) {
    t.area = resolveArea(t.areaVotes);
    t.preScore = Math.log(t.totalViews + 1) * (1 + 0.3 * t.videoIds.size);
  }

  return Array.from(byName.values()).sort((a, b) => b.preScore - a.preScore);
}

/**
 * Per-video diversity cap. Each video can contribute at most PER_VIDEO_SOLO_CAP
 * places that are exclusive to it (videoIds.size === 1). Places mentioned in
 * ≥2 videos are corroborated and bypass the cap entirely — that overlap is the
 * strongest quality signal we have, and we never want to throw it away.
 *
 * Within a video's solos, all share the same totalViews and videoCount, so
 * preScore is identical; bestConfidence is the meaningful tiebreaker.
 */
function applyPerVideoSoloCap(tallies: NameTally[]): NameTally[] {
  const corroborated: NameTally[] = [];
  const soloByVideo = new Map<string, NameTally[]>();

  for (const t of tallies) {
    if (t.videoIds.size >= 2) {
      corroborated.push(t);
    } else {
      const videoId = t.videoIds.values().next().value as string;
      const arr = soloByVideo.get(videoId);
      if (arr) arr.push(t);
      else soloByVideo.set(videoId, [t]);
    }
  }

  const keptSolos: NameTally[] = [];
  for (const [videoId, solos] of soloByVideo) {
    solos.sort((a, b) => {
      const cmp = confidenceRank(b.bestConfidence) - confidenceRank(a.bestConfidence);
      return cmp !== 0 ? cmp : b.preScore - a.preScore;
    });
    const kept = Math.min(solos.length, PER_VIDEO_SOLO_CAP);
    if (solos.length > PER_VIDEO_SOLO_CAP) {
      console.log(
        `[tiktok-locations] cap: video=${videoId.slice(0, 12)} solos=${solos.length} kept=${kept} dropped=${solos.length - kept}`
      );
    }
    keptSolos.push(...solos.slice(0, kept));
  }

  return [...corroborated, ...keptSolos].sort((a, b) => b.preScore - a.preScore);
}

/** Final composite score with rating mixed in. */
function computeFullScore(preScore: number, rating: number | null): number {
  const ratingMultiplier = rating != null ? Math.max(0.5, rating / 4.0) : 1.0;
  return preScore * ratingMultiplier;
}

// ── Handler ───────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    const placesApiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");

    if (!geminiApiKey || !placesApiKey) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY or GOOGLE_PLACES_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const body: RequestBody = await req.json();
    if (!Array.isArray(body.videos) || body.videos.length === 0) {
      return new Response(JSON.stringify({ error: "videos array required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (body.videos.length > MAX_INPUT_VIDEOS) {
      return new Response(JSON.stringify({ error: `at most ${MAX_INPUT_VIDEOS} videos are allowed` }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const user = await requireAuthenticatedUser(req);
    const quota = await consumePaidAPIQuota(
      user.id,
      PAID_API_QUOTA,
      1 + Math.ceil(body.videos.length / 5),
    );

    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("[tiktok-locations] INCOMING REQUEST");
    console.log(`  videos:     ${body.videos.length}`);
    console.log(`  searchQuery: "${body.searchQuery}"`);
    console.log(`  coords:     ${body.latitude ?? "?"}, ${body.longitude ?? "?"}`);

    // 1. Fetch transcripts in parallel
    const transcriptStart = Date.now();
    const transcripts = await Promise.all(
      body.videos.map((v) => (v.transcriptUrl ? fetchTranscript(v.transcriptUrl) : Promise.resolve("")))
    );
    const transcriptMs = Date.now() - transcriptStart;
    const withTranscript = transcripts.filter((t) => t.length > 0).length;
    console.log(`[tiktok-locations] Fetched transcripts: ${withTranscript}/${body.videos.length} in ${transcriptMs}ms`);

    // 2. Single Gemini call: queryCity + per-video places with confidence
    const gemini = await extractPlacesAndCity(body.videos, transcripts, body.searchQuery ?? "", geminiApiKey);

    // 3. CITY GUARD — reject if no city in query
    if (!gemini.queryCity || !gemini.queryCity.trim()) {
      console.log("[tiktok-locations] queryCity missing — returning 400 missing_city");
      return new Response(
        JSON.stringify({
          error: "missing_city",
          message: "Please include a city in your search.",
          suggestedCities: ["Los Angeles", "New York", "San Francisco", "Chicago"],
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const queryCity = gemini.queryCity.trim();

    // 4. Geocode the query city once → use as locationBias for every venue lookup
    const cityCoord = await geocodeCityToCoord(queryCity, placesApiKey, "tiktok-locations");
    if (!cityCoord) {
      console.warn(`[tiktok-locations] Could not geocode queryCity="${queryCity}", proceeding without bias`);
    }
    const cityBias: LocationBias = {
      lat: cityCoord?.lat ?? 0,
      lng: cityCoord?.lng ?? 0,
      radiusMeters: CITY_BIAS_RADIUS_METERS,
    };

    // 5. Tally per-name aggregates (drops low-confidence), apply per-video solo cap, pre-score, take top GEOCODE_LIMIT
    const tallies = buildNameTallies(body.videos, gemini.videos);
    const totalRaw = tallies.length;
    const capped = applyPerVideoSoloCap(tallies);
    const toGeocode = capped.slice(0, GEOCODE_LIMIT);
    console.log(`[tiktok-locations] Tally: ${totalRaw} unique names; after per-video cap: ${capped.length}; geocoding top ${toGeocode.length}`);
    for (const t of toGeocode) {
      const voteSummary = t.areaVotes.size === 0
        ? ""
        : ` votes={${Array.from(t.areaVotes.entries()).map(([k, v]) => `${k}:${v.count}`).join(",")}}`;
      console.log(`  → "${t.name}"${t.area ? ` (${t.area})` : ""}${voteSummary} preScore=${t.preScore.toFixed(2)} views=${t.totalViews} videos=${t.videoIds.size}`);
    }

    // 6. Geocode in parallel through the two-layer cache
    const geocodeStart = Date.now();
    const geocoded = await Promise.all(
      toGeocode.map(async (t) => {
        const geo = cityCoord
          ? await geocodePlace(t.name, t.area, queryCity, cityBias, placesApiKey)
          : null;
        return { tally: t, geo };
      })
    );
    const geocodeMs = Date.now() - geocodeStart;
    const resolvedCount = geocoded.filter((g) => g.geo).length;
    console.log(`[tiktok-locations] Geocoded ${resolvedCount}/${toGeocode.length} in ${geocodeMs}ms`);

    // 7. Dedupe by placeId, sum across name variants that resolved to the same place
    const byPlaceId = new Map<string, {
      place: GeocodedPlace;
      videoIds: Set<string>;
      totalViews: number;
      preScore: number; // max of contributing tallies' preScore
    }>();

    for (const { tally, geo } of geocoded) {
      if (!geo) continue;
      const existing = byPlaceId.get(geo.placeId);
      if (existing) {
        for (const id of tally.videoIds) existing.videoIds.add(id);
        existing.totalViews += tally.totalViews;
        existing.preScore = Math.max(existing.preScore, tally.preScore);
      } else {
        byPlaceId.set(geo.placeId, {
          place: geo,
          videoIds: new Set(tally.videoIds),
          totalViews: tally.totalViews,
          preScore: tally.preScore,
        });
      }
    }

    // 8. Full score with rating, sort, take top TOP_N
    const ranked = Array.from(byPlaceId.values())
      .map((entry) => ({
        ...entry,
        score: computeFullScore(entry.preScore, entry.place.rating),
      }))
      .sort((a, b) => b.score - a.score)
      .slice(0, TOP_N);

    const locations: LocationOutput[] = ranked.map((entry, i) => ({
      placeId: entry.place.placeId,
      placeName: entry.place.placeName,
      address: entry.place.address,
      lat: entry.place.lat,
      lng: entry.place.lng,
      rank: i,
      totalViews: entry.totalViews,
      videoIds: Array.from(entry.videoIds),
      videoCount: entry.videoIds.size,
      rating: entry.place.rating,
      isOpen: entry.place.isOpen,
      neighborhood: entry.place.neighborhood,
      score: Number(entry.score.toFixed(2)),
    }));

    // 9. unresolved = videos that contributed zero places to the final list
    const finalVideoIds = new Set(locations.flatMap((l) => l.videoIds));
    const unresolved = body.videos
      .map((v) => v.videoId)
      .filter((id) => !finalVideoIds.has(id));

    console.log(`[tiktok-locations] Final top ${locations.length} (of ${byPlaceId.size} unique placeIds, ${unresolved.length} videos unresolved):`);
    for (const l of locations) {
      console.log(`  #${l.rank + 1}. ${l.placeName} | views=${l.totalViews} videos=${l.videoCount} rating=${l.rating ?? "?"} score=${l.score} | ${l.neighborhood ?? "(no nbhd)"}`);
    }
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    return new Response(JSON.stringify({ locations, unresolved, queryCity }), {
      status: 200,
      headers: {
        ...corsHeaders,
        ...quotaHeaders(quota),
        "Content-Type": "application/json",
      },
    });
  } catch (err) {
    const accessResponse = paidAPIAccessErrorResponse(err, corsHeaders);
    if (accessResponse) return accessResponse;
    const message = err instanceof Error ? err.message : String(err);
    console.error("[tiktok-locations] 500:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
