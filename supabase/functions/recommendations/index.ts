import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { GoogleGenAI } from "npm:@google/genai@1.46.0";

/** Gemini 3 Flash (preview) — see https://ai.google.dev/gemini-api/docs */
const GEMINI_MODEL = "gemini-3-flash-preview";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ─── Types ───────────────────────────────────────────────────────────────────

interface RequestBody {
  prompt: string;
  occasion?: string;
  vibe?: string[];
  hunger?: string[];
  /** User-entered area (optional; primary location is inside `prompt`) */
  location?: string;
  googleSearch?: boolean;
  thinkingLevel?: string;
}

interface Recommendation {
  name: string;
  dish: string;
  image: string;
  explanation: string;
  mapsUrl: string;
}

/** Filterable in Supabase → Edge Functions → Logs */
function logPlaces(...args: unknown[]) {
  console.log("[places]", ...args);
}

function logPlacesWarn(...args: unknown[]) {
  console.warn("[places]", ...args);
}

// ─── Google Places helpers ────────────────────────────────────────────────────

function parsePlaceIdFromMapsUrl(mapsUrl: string, logTag: string): string | null {
  if (!mapsUrl) {
    logPlaces(logTag, "parsePlaceId: empty mapsUrl");
    return null;
  }
  let decoded: string;
  try {
    decoded = decodeURIComponent(mapsUrl);
  } catch {
    decoded = mapsUrl;
  }

  logPlaces(logTag, "parsePlaceId: raw mapsUrl (truncated)", mapsUrl.slice(0, 200));

  const queryMatch = decoded.match(/(?:query_place_id|place_id)=([A-Za-z0-9_-]{27,})/);
  if (queryMatch) {
    logPlaces(logTag, "parsePlaceId: matched query_place_id / place_id", queryMatch[1]);
    return queryMatch[1];
  }

  const chijMatch = decoded.match(/ChIJ[A-Za-z0-9_-]{20,}/);
  if (chijMatch) {
    logPlaces(logTag, "parsePlaceId: matched ChIJ token", chijMatch[0]);
    return chijMatch[0];
  }

  logPlaces(logTag, "parsePlaceId: no place id pattern found in URL");
  return null;
}

async function resolvePlaceIdByTextSearch(
  placeName: string,
  apiKey: string,
  logTag: string,
  searchArea = "Los Angeles, CA"
): Promise<string | null> {
  const textQuery = `${placeName} ${searchArea}`;
  logPlaces(logTag, "textSearch: request", { textQuery });

  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "places.id",
    },
    body: JSON.stringify({ textQuery }),
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "textSearch: HTTP error", {
      status: res.status,
      bodySnippet: bodyText.slice(0, 500),
    });
    return null;
  }

  let data: { places?: Array<{ id?: string }> };
  try {
    data = JSON.parse(bodyText);
  } catch (e) {
    logPlacesWarn(logTag, "textSearch: invalid JSON", bodyText.slice(0, 300));
    return null;
  }

  const rawId: string | undefined = data?.places?.[0]?.id;
  if (!rawId) {
    logPlacesWarn(logTag, "textSearch: no places[0].id in response", {
      placesLength: data?.places?.length ?? 0,
    });
    return null;
  }

  const placeId = rawId.startsWith("places/") ? rawId.slice(7) : rawId;
  logPlaces(logTag, "textSearch: resolved place id", { rawId, placeId });
  return placeId;
}

async function fetchPlaceDetails(placeId: string, apiKey: string, logTag: string): Promise<string | null> {
  const encoded = encodeURIComponent(placeId);
  const url = `https://places.googleapis.com/v1/places/${encoded}`;
  logPlaces(logTag, "placeDetails: GET", url);

  const res = await fetch(url, {
    headers: {
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": "photos",
    },
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "placeDetails: HTTP error", {
      status: res.status,
      placeId,
      bodySnippet: bodyText.slice(0, 500),
    });
    return null;
  }

  let data: { photos?: Array<{ name?: string }> };
  try {
    data = JSON.parse(bodyText);
  } catch (e) {
    logPlacesWarn(logTag, "placeDetails: invalid JSON", bodyText.slice(0, 300));
    return null;
  }

  const photoName = data?.photos?.[0]?.name ?? null;
  if (!photoName) {
    logPlacesWarn(logTag, "placeDetails: no photos[0].name (place may have no photos)", {
      photosCount: data?.photos?.length ?? 0,
    });
    return null;
  }

  logPlaces(logTag, "placeDetails: first photo resource name", photoName);
  return photoName;
}

async function fetchPhotoUri(photoName: string, apiKey: string, logTag: string): Promise<string | null> {
  const resource = photoName.endsWith("/media") ? photoName : `${photoName}/media`;
  const mediaUrl =
    `https://places.googleapis.com/v1/${resource}?maxWidthPx=800&skipHttpRedirect=true`;
  logPlaces(logTag, "photoMedia: GET (truncated)", mediaUrl.slice(0, 180) + (mediaUrl.length > 180 ? "…" : ""));

  const res = await fetch(mediaUrl, {
    headers: { "X-Goog-Api-Key": apiKey },
  });

  const bodyText = await res.text();
  if (!res.ok) {
    logPlacesWarn(logTag, "photoMedia: HTTP error", {
      status: res.status,
      bodySnippet: bodyText.slice(0, 500),
    });
    return null;
  }

  let data: { photoUri?: string };
  try {
    data = JSON.parse(bodyText);
  } catch (e) {
    logPlacesWarn(logTag, "photoMedia: invalid JSON", bodyText.slice(0, 300));
    return null;
  }

  const photoUri = (data?.photoUri as string) ?? null;
  if (!photoUri) {
    logPlacesWarn(logTag, "photoMedia: missing photoUri in JSON", data);
    return null;
  }

  logPlaces(logTag, "photoMedia: got photoUri (truncated)", photoUri.slice(0, 120) + "…");
  return photoUri;
}

async function enrichRecommendation(
  rec: Recommendation,
  placesApiKey: string,
  index: number,
  searchArea: string
): Promise<{ rec: Recommendation; error: string | null }> {
  const logTag = `[#${index} "${rec.name}"]`;

  logPlaces(logTag, "── enrich start ──", {
    mapsUrlLen: rec.mapsUrl?.length ?? 0,
    imageBeforeTruncated: (rec.image ?? "").slice(0, 100),
    searchArea,
  });

  let placeId = parsePlaceIdFromMapsUrl(rec.mapsUrl, logTag);

  if (!placeId) {
    placeId = await resolvePlaceIdByTextSearch(rec.name, placesApiKey, logTag, searchArea);
  }

  if (!placeId) {
    const msg = `${logTag} ENRICHMENT_FAILED: no placeId from URL or text search`;
    logPlacesWarn(msg);
    return { rec, error: msg };
  }

  const photoName = await fetchPlaceDetails(placeId, placesApiKey, logTag);
  if (!photoName) {
    const msg = `${logTag} ENRICHMENT_FAILED: Place Details returned no photo name (placeId=${placeId})`;
    logPlacesWarn(msg);
    return { rec, error: msg };
  }

  const photoUri = await fetchPhotoUri(photoName, placesApiKey, logTag);
  if (!photoUri) {
    const msg = `${logTag} ENRICHMENT_FAILED: photo media URL failed (placeId=${placeId})`;
    logPlacesWarn(msg);
    return { rec, error: msg };
  }

  logPlaces(logTag, "ENRICHMENT_OK: replaced image with Places photo URL");
  return { rec: { ...rec, image: photoUri }, error: null };
}

// ─── Gemini call (@google/genai — same API as docs, works in Deno via npm:) ───

async function callGemini(prompt: string, geminiApiKey: string): Promise<Recommendation[]> {
  const ai = new GoogleGenAI({ apiKey: geminiApiKey });

  const response = await ai.models.generateContent({
    model: GEMINI_MODEL,
    contents: prompt,
    config: {
      temperature: 1,
      responseMimeType: "application/json",
    },
  });

  const rawText = response.text ?? "";
  if (!rawText.trim()) {
    throw new Error("Gemini returned empty text (blocked, wrong model, or API error)");
  }

  const cleaned = rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  let parsed: { recommendations?: Recommendation[] };
  try {
    parsed = JSON.parse(cleaned) as { recommendations?: Recommendation[] };
  } catch (e) {
    throw new Error(
      `Gemini JSON parse failed: ${e instanceof Error ? e.message : String(e)}. Snippet: ${cleaned.slice(0, 400)}`
    );
  }

  return (parsed?.recommendations ?? []) as Recommendation[];
}

// ─── Handler ─────────────────────────────────────────────────────────────────

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

    if (!geminiApiKey) {
      return new Response(JSON.stringify({ error: "GEMINI_API_KEY not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body: RequestBody = await req.json();

    if (!body.prompt) {
      return new Response(JSON.stringify({ error: "prompt is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const searchArea = body.location?.trim() || "Los Angeles, CA";
    logPlaces("User area for Places text search:", searchArea);

    // 1. Get recommendations from Gemini
    const recommendations = await callGemini(body.prompt, geminiApiKey);
    logPlaces("Gemini returned", recommendations.length, "recommendations");

    // 2. Enrich with Google Places photos (if key is available)
    let enriched: Recommendation[] = recommendations;
    if (!placesApiKey) {
      logPlacesWarn(
        "GOOGLE_PLACES_API_KEY not set — skipping photo enrichment entirely (every card keeps Gemini/stock image)",
      );
    } else {
      logPlaces("Starting Places enrichment for", recommendations.length, "items");
      const results = await Promise.all(
        recommendations.map((rec, i) =>
          enrichRecommendation(rec, placesApiKey, i, searchArea)
        )
      );
      enriched = results.map((r) => r.rec);
      const enrichmentErrors = results.map((r) => r.error).filter(Boolean);
      if (enrichmentErrors.length > 0) {
        logPlacesWarn("Enrichment errors summary:", enrichmentErrors);
      }
    }

    return new Response(JSON.stringify({ recommendations: enriched }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    // Shows in Dashboard → Edge Functions → Logs (Invocations alone won’t print response bodies)
    console.error("[recommendations] 500:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
