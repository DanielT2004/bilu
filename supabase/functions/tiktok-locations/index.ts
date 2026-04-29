import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { GoogleGenAI } from "npm:@google/genai@1.46.0";
import { resolvePlaceIdByTextSearch } from "../_shared/places.ts";

/** Lightweight Gemini model for location extraction — see https://ai.google.dev/gemini-api/docs */
const GEMINI_MODEL = "gemini-2.5-flash-lite";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

interface PlaceHit {
  name: string;
  city: string | null;
}

interface ExtractedLocation {
  videoId: string;
  places: PlaceHit[];
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
      // Numeric cue identifiers (lines that are just a number)
      if (/^\d+$/.test(trimmed)) continue;
      // Timestamp-only lines that may slip through
      if (/^\d{2}:\d{2}:\d{2}/.test(trimmed)) continue;
      textLines.push(trimmed);
    }

    const combined = textLines.join(" ").replace(/\s+/g, " ").trim();
    return combined.slice(0, 3000);
  } catch {
    return "";
  }
}

// ── Gemini: batched caption + transcript → places[] ──────────────────────────

async function extractPlacesFromDescriptions(
  videos: VideoInput[],
  transcripts: string[],
  searchQuery: string,
  geminiApiKey: string
): Promise<ExtractedLocation[]> {
  const ai = new GoogleGenAI({ apiKey: geminiApiKey });

  const systemInstruction = `You extract restaurant, cafe, or venue names from TikTok video captions and voiceover transcripts.

For each video return { videoId, places: [{ name, city }, ...] }:
  - TRANSCRIPT is the creator's spoken voiceover (auto-generated captions). When present, it is the PRIMARY source of venue names — captions are secondary context.
  - For roundup / "top N" / list-style videos, extract EVERY named venue the creator describes visiting. A single video can yield 5-10 places.
  - For single-venue videos, return a one-element array.
  - Only extract venues the creator actually VISITED. If it's a recipe, copycat, DIY, homemade, cooking tutorial, "how to make", "at home", etc. — return [].
  - If the search query contains a city, only extract venues located in that city. If the transcript/caption clearly places the venue in a different city, skip it.
  - When unsure, prefer empty places array over guessing. A smaller, accurate result is better than a scattered one.
  - Set city on each place based on transcript/caption/query context; null if not determinable.`;

  const payload = videos.map((v, i) => ({
    videoId: v.videoId,
    caption: v.desc.slice(0, 500),
    transcript: transcripts[i] || "",
  }));

  const prompt = `User search query: "${searchQuery}"

Extract named restaurants / cafes / venues from each video below. Return one result per video using its exact videoId, with a places array (empty if nothing extractable).

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

  const emptyFallback = (): ExtractedLocation[] =>
    videos.map((v) => ({ videoId: v.videoId, places: [] }));

  const response = await ai.models.generateContent({
    model: GEMINI_MODEL,
    systemInstruction,
    contents: prompt,
    config: {
      temperature: 0.1,
      responseMimeType: "application/json",
      responseSchema: {
        type: "array" as const,
        items: {
          type: "object" as const,
          properties: {
            videoId: { type: "string" as const, description: "The videoId from the input" },
            places: {
              type: "array" as const,
              description: "Every named venue the creator describes visiting. Empty array if none.",
              items: {
                type: "object" as const,
                properties: {
                  name: { type: "string" as const, description: "Venue name as spoken/written" },
                  city: { type: "string" as const, description: "City or neighborhood", nullable: true },
                },
                required: ["name", "city"],
              },
            },
          },
          required: ["videoId", "places"],
        },
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
    const parsed = JSON.parse(cleaned) as ExtractedLocation[];
    if (!Array.isArray(parsed)) throw new Error("Response is not an array");
    console.log("[tiktok-locations] Parsed results:");
    for (const p of parsed) {
      const summary = p.places?.length
        ? p.places.map((pl) => `${pl.name} (${pl.city ?? "?"})`).join("; ")
        : "[]";
      console.log(`  [${p.videoId?.slice(0, 10)}] places: ${summary}`);
    }
    return parsed;
  } catch (e) {
    console.error("[tiktok-locations] Gemini JSON parse failed:", e, "snippet:", cleaned.slice(0, 400));
    return emptyFallback();
  }
}

// ── Google Places: geocode place name to { placeId, lat, lng, address } ──────

interface GeocodedPlace {
  placeId: string;
  placeName: string;
  address: string;
  lat: number;
  lng: number;
}

async function geocodePlace(
  placeName: string,
  city: string | null,
  placesApiKey: string,
  bias: { latitude?: number; longitude?: number }
): Promise<GeocodedPlace | null> {
  const searchArea = city ?? "";
  const placeId = await resolvePlaceIdByTextSearch(placeName, placesApiKey, "tiktok-locations", searchArea);
  if (!placeId) return null;

  const url = `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`;
  const res = await fetch(url, {
    headers: {
      "X-Goog-Api-Key": placesApiKey,
      "X-Goog-FieldMask": "displayName,location,formattedAddress",
    },
  });

  if (!res.ok) return null;

  let data: {
    displayName?: { text?: string };
    location?: { latitude?: number; longitude?: number };
    formattedAddress?: string;
  };
  try {
    data = await res.json();
  } catch {
    return null;
  }

  const lat = data.location?.latitude;
  const lng = data.location?.longitude;
  if (lat === undefined || lng === undefined) return null;

  return {
    placeId,
    placeName: data.displayName?.text ?? placeName,
    address: data.formattedAddress ?? "",
    lat,
    lng,
  };
}

// ── Dedupe + rank ────────────────────────────────────────────────────────────

function dedupeAndRank(
  videos: VideoInput[],
  extracted: ExtractedLocation[],
  geocoded: Map<string, GeocodedPlace>
): { locations: LocationOutput[]; unresolved: string[] } {
  const byPlaceId = new Map<string, { place: GeocodedPlace; videoIds: Set<string>; totalViews: number }>();
  const unresolved: string[] = [];

  for (const v of videos) {
    const ext = extracted.find((e) => e.videoId === v.videoId);
    const placesOnVideo = ext?.places ?? [];
    const geosForVideo: GeocodedPlace[] = [];

    for (const p of placesOnVideo) {
      if (!p.name?.trim()) continue;
      const key = `${p.name}|${p.city ?? ""}`.toLowerCase();
      const geo = geocoded.get(key);
      if (geo) geosForVideo.push(geo);
    }

    if (geosForVideo.length === 0) {
      unresolved.push(v.videoId);
      continue;
    }

    // A roundup video contributes its views to every place it surfaces.
    // Use Set to avoid double-counting views if Gemini lists the same venue twice.
    const seenPlaceIds = new Set<string>();
    for (const geo of geosForVideo) {
      if (seenPlaceIds.has(geo.placeId)) continue;
      seenPlaceIds.add(geo.placeId);

      const existing = byPlaceId.get(geo.placeId);
      if (existing) {
        existing.videoIds.add(v.videoId);
        existing.totalViews += v.viewCount;
      } else {
        byPlaceId.set(geo.placeId, {
          place: geo,
          videoIds: new Set([v.videoId]),
          totalViews: v.viewCount,
        });
      }
    }
  }

  const locations: LocationOutput[] = Array.from(byPlaceId.values())
    .sort((a, b) => b.totalViews - a.totalViews)
    .map((entry, i) => ({
      placeId: entry.place.placeId,
      placeName: entry.place.placeName,
      address: entry.place.address,
      lat: entry.place.lat,
      lng: entry.place.lng,
      rank: i,
      totalViews: entry.totalViews,
      videoIds: Array.from(entry.videoIds),
    }));

  return { locations, unresolved };
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

    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("[tiktok-locations] INCOMING REQUEST");
    console.log(`  videos:     ${body.videos.length}`);
    console.log(`  searchQuery: "${body.searchQuery}"`);
    console.log(`  coords:     ${body.latitude ?? "?"}, ${body.longitude ?? "?"}`);

    // Per-video signals log: caption, anchors, transcript availability
    console.log("[tiktok-locations] ── PER-VIDEO SIGNALS ──");
    for (const v of body.videos) {
      const id = v.videoId.slice(0, 10);
      const descPreview = v.desc.slice(0, 70).replace(/\n/g, " ");
      const anchors = v.anchors ?? [];
      const anchorSummary = anchors.length === 0
        ? "none"
        : anchors.map((a) => {
            const cat = a.poiClassName ?? a.categoryName ?? "?";
            const coord = a.lat !== undefined && a.lng !== undefined
              ? ` @${a.lat.toFixed(3)},${a.lng.toFixed(3)}`
              : "";
            return `"${a.keyword}"[${cat}]${coord}`;
          }).join(", ");
      const transcriptStr = v.transcriptUrl ? "available" : "missing";
      console.log(`  [${id}] desc="${descPreview}"`);
      console.log(`           anchors: ${anchorSummary} | transcript: ${transcriptStr}`);
    }
    console.log("[tiktok-locations] ── END SIGNALS ──");

    // 1. Fetch transcripts in parallel (missing / failed → "")
    const transcriptStart = Date.now();
    const transcripts = await Promise.all(
      body.videos.map((v) => (v.transcriptUrl ? fetchTranscript(v.transcriptUrl) : Promise.resolve("")))
    );
    const transcriptMs = Date.now() - transcriptStart;
    const withTranscript = transcripts.filter((t) => t.length > 0).length;
    console.log(`[tiktok-locations] Fetched transcripts: ${withTranscript}/${body.videos.length} in ${transcriptMs}ms`);

    // 2. Extract places from caption + transcript (single Gemini batch call)
    const extracted = await extractPlacesFromDescriptions(
      body.videos,
      transcripts,
      body.searchQuery ?? "",
      geminiApiKey
    );
    const totalPlaces = extracted.reduce((sum, e) => sum + (e.places?.length ?? 0), 0);
    const videosWithAtLeastOne = extracted.filter((e) => (e.places?.length ?? 0) > 0).length;
    console.log(`[tiktok-locations] Gemini resolved ${totalPlaces} places across ${videosWithAtLeastOne}/${body.videos.length} videos`);

    // 3. Geocode unique (name, city) pairs in parallel
    const uniqueKeys = new Map<string, { name: string; city: string | null }>();
    for (const e of extracted) {
      for (const p of e.places ?? []) {
        if (!p.name?.trim()) continue;
        const key = `${p.name}|${p.city ?? ""}`.toLowerCase();
        if (!uniqueKeys.has(key)) uniqueKeys.set(key, { name: p.name, city: p.city });
      }
    }

    const geocodeResults = await Promise.all(
      Array.from(uniqueKeys.entries()).map(async ([key, { name, city }]) => {
        const geo = await geocodePlace(name, city, placesApiKey, {
          latitude: body.latitude,
          longitude: body.longitude,
        });
        return { key, geo };
      })
    );

    const geocoded = new Map<string, GeocodedPlace>();
    for (const { key, geo } of geocodeResults) {
      if (geo) geocoded.set(key, geo);
    }
    console.log(`[tiktok-locations] Geocoded ${geocoded.size}/${uniqueKeys.size} unique places`);

    // 3. Dedupe by placeId, rank by total views
    const { locations, unresolved } = dedupeAndRank(body.videos, extracted, geocoded);
    console.log(`[tiktok-locations] Final: ${locations.length} locations, ${unresolved.length} unresolved`);
    locations.forEach((l) => console.log(`  #${l.rank + 1}. ${l.placeName} — ${l.totalViews} views, ${l.videoIds.length} videos`));
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    return new Response(JSON.stringify({ locations, unresolved }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[tiktok-locations] 500:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
