import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { GoogleGenAI } from "npm:@google/genai@1.46.0";
import type { Recommendation, GroundingPlace } from "../_shared/places.ts";

/** Gemini model — see https://ai.google.dev/gemini-api/docs */
const GEMINI_MODEL = "gemini-2.5-flash";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RequestBody {
  prompt: string;
  occasion?: string;
  vibe?: string[];
  hunger?: string[];
  location?: string;
  googleSearch?: boolean;
  thinkingLevel?: string;
  latitude?: number;
  longitude?: number;
  radiusMiles?: number;
}

// ─── Gemini call ──────────────────────────────────────────────────────────────

interface GeminiCallResult {
  recommendations: Recommendation[];
  groundingPlaces: GroundingPlace[];
}

// Single grounded Gemini call. Throws on parse failure / empty / prose refusal
// so the caller can decide whether to retry or fall back.
async function generateOnce(
  ai: GoogleGenAI,
  systemInstruction: string,
  prompt: string,
  temperature: number,
  locationConfig: Record<string, unknown>
): Promise<GeminiCallResult> {
  const response = await ai.models.generateContent({
    model: GEMINI_MODEL,
    systemInstruction,
    contents: prompt,
    config: {
      temperature,
      thinkingConfig: { thinkingBudget: 0 },
      tools: [{ googleMaps: {} }],
      ...locationConfig,
    },
  });

  const rawText = response.text ?? "";
  if (!rawText.trim()) {
    throw new Error("Gemini returned empty text (blocked, wrong model, or API error)");
  }

  const cleaned = rawText.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  if (!cleaned.startsWith("{")) {
    throw new Error(`Gemini returned non-JSON prose. Snippet: ${cleaned.slice(0, 400)}`);
  }

  let parsed: { recommendations?: Recommendation[] };
  try {
    parsed = JSON.parse(cleaned) as { recommendations?: Recommendation[] };
  } catch (e) {
    throw new Error(
      `Gemini JSON parse failed: ${e instanceof Error ? e.message : String(e)}. Snippet: ${cleaned.slice(0, 400)}`
    );
  }

  const groundingPlaces: GroundingPlace[] = (
    (response.candidates?.[0]?.groundingMetadata as any)?.groundingChunks ?? []
  )
    .map((chunk: any) => chunk.maps)
    .filter((m: any) => m?.placeId)
    .map((m: any) => ({
      placeId: m.placeId.startsWith("places/") ? m.placeId.slice(7) : m.placeId,
      title: m.title ?? "",
      uri: m.uri ?? "",
    }));

  return {
    recommendations: (parsed?.recommendations ?? []) as Recommendation[],
    groundingPlaces,
  };
}

async function callGemini(
  prompt: string,
  geminiApiKey: string,
  lat: number | undefined,
  lng: number | undefined,
  radiusMiles: number | undefined,
  location: string | undefined,
  occasion: string | undefined
): Promise<GeminiCallResult & { relaxed: boolean }> {
  const ai = new GoogleGenAI({ apiKey: geminiApiKey });
  const hasRadius = lat !== undefined && lng !== undefined && radiusMiles !== undefined;

  // Soft contract — model must always return JSON, never refuse.
  const radiusClause = hasRadius
    ? ` Only suggest places within ${radiusMiles!.toFixed(1)} miles of the coordinates in the prompt.`
    : ` Find the best spots in the city or area specified in the prompt.`;
  const systemInstruction =
    `You are a local food discovery assistant.${radiusClause} ` +
    `Always respond with JSON only — never refuse, apologize, or write prose. ` +
    `Return up to 5 results; fewer is fine. If truly nothing fits, return { "recommendations": [] }.`;

  // Only anchor the Google Maps grounding to specific coordinates in radius mode.
  // In city-wide mode the grounding tool relies on the location string in the prompt.
  const locationConfig = (lat !== undefined && lng !== undefined)
    ? { toolConfig: { retrievalConfig: { latLng: { latitude: lat, longitude: lng } } } }
    : {};

  console.log(`[callGemini] mode: ${hasRadius ? `radius (${radiusMiles} mi @ ${lat},${lng})` : "city-wide"}`);

  // ─── Layer 1: normal call at low temperature ────────────────────────────
  try {
    const result = await generateOnce(ai, systemInstruction, prompt, 0.1, locationConfig);
    if (result.recommendations.length > 0) {
      console.log("[recommendations] resolved at: layer1");
      console.log("[recommendations] Grounding chunks extracted:", result.groundingPlaces.length, "places");
      return { ...result, relaxed: false };
    }
    console.warn("[recommendations] layer1 returned empty array — retrying with temp ladder");
  } catch (e) {
    console.warn("[recommendations] layer1 failed:", e instanceof Error ? e.message : String(e));
  }

  // ─── Layer 2: retry with temperature ladder to reshuffle grounding ──────
  try {
    const result = await generateOnce(ai, systemInstruction, prompt, 0.7, locationConfig);
    if (result.recommendations.length > 0) {
      console.log("[recommendations] resolved at: layer2");
      console.log("[recommendations] Grounding chunks extracted:", result.groundingPlaces.length, "places");
      return { ...result, relaxed: false };
    }
    console.warn("[recommendations] layer2 returned empty array — falling back to relaxed prompt");
  } catch (e) {
    console.warn("[recommendations] layer2 failed:", e instanceof Error ? e.message : String(e));
  }

  // ─── Layer 3: relaxed fallback — drops chain/quality filters entirely ───
  // Guaranteed to find something because Gemini can almost always name 5
  // popular spots in a city. Tagged `relaxed: true` so the UI can show a
  // soft "we loosened your filters" banner.
  const relaxedLocation = location?.trim() || "the area in the prompt";
  const relaxedOccasion = occasion?.trim() || "a meal out";
  const relaxedPrompt =
    `Find 5 popular, highly-rated spots for ${relaxedOccasion} near ${relaxedLocation}. ` +
    `Return JSON only: { "recommendations": [{ "name": "", "dish": "", "explanation": "", "mapsUrl": "" }] }. ` +
    `Each explanation: one short sentence on what the spot is known for.`;
  const relaxedSystem =
    `You are a local food discovery assistant. Always respond with JSON only — never refuse. ` +
    `Return 5 popular spots, even if filters are unspecified.`;

  const result = await generateOnce(ai, relaxedSystem, relaxedPrompt, 0.4, locationConfig);
  console.log("[recommendations] resolved at: layer3 (relaxed)");
  console.log("[recommendations] Grounding chunks extracted:", result.groundingPlaces.length, "places");
  return { ...result, relaxed: true };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

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

    // Only use radius mode when ALL THREE fields are explicitly provided by the client.
    // If any are missing the request is treated as city-wide — no coordinate constraint.
    const hasRadius = body.latitude !== undefined
      && body.longitude !== undefined
      && body.radiusMiles !== undefined;

    const lat         = hasRadius ? body.latitude   : undefined;
    const lng         = hasRadius ? body.longitude  : undefined;
    const radiusMiles = hasRadius ? body.radiusMiles : undefined;

    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("[recommendations] INCOMING REQUEST");
    console.log(`  mode:        ${hasRadius ? `radius (${radiusMiles} mi)` : "city-wide"}`);
    console.log(`  lat:         ${lat ?? "(not set)"}`);
    console.log(`  lng:         ${lng ?? "(not set)"}`);
    console.log(`  location:    ${body.location ?? "(not set)"}`);
    console.log(`  occasion:    ${body.occasion ?? "(not set)"}`);
    console.log("[recommendations] FULL PROMPT:");
    console.log(body.prompt);
    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    const { recommendations, groundingPlaces, relaxed } = await callGemini(
      body.prompt, geminiApiKey, lat, lng, radiusMiles, body.location, body.occasion
    );
    console.log("[recommendations] Gemini returned", recommendations.length, "recommendations", relaxed ? "(relaxed)" : "");
    recommendations.forEach((r, i) => console.log(`  ${i + 1}. ${r.name} — ${r.mapsUrl ?? "no url"}`));

    return new Response(JSON.stringify({ recommendations, groundingPlaces, relaxed }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[recommendations] 500:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
