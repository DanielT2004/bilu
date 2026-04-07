import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { GoogleGenAI } from "npm:@google/genai@1.46.0";
import type { Recommendation, GroundingPlace } from "../_shared/places.ts";

/** Gemini 3 Flash (preview) — see https://ai.google.dev/gemini-api/docs */
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
}

// ─── Gemini call ──────────────────────────────────────────────────────────────

async function callGemini(
  prompt: string,
  geminiApiKey: string
): Promise<{ recommendations: Recommendation[]; groundingPlaces: GroundingPlace[] }> {
  const ai = new GoogleGenAI({ apiKey: geminiApiKey });

  const response = await ai.models.generateContent({
    model: GEMINI_MODEL,
    systemInstruction: "You are a local discovery assistant. You MUST strictly adhere to the user's distance constraints of 2 miles radius. If a result is outside the specified radius, you are forbidden from suggesting it, even if it is highly rated.",
    contents: prompt,
    config: {
      temperature: 0.1,
      thinkingConfig: { thinkingBudget: 0 },
      tools: [{ googleMaps: {} }],
      toolConfig: {
        retrievalConfig: {
          latLng: { latitude: 34.0224, longitude: -118.2851 },
        },
      },
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

  console.log("[recommendations] Grounding chunks extracted:", groundingPlaces.length, "places");

  return { recommendations: (parsed?.recommendations ?? []) as Recommendation[], groundingPlaces };
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

    const { recommendations, groundingPlaces } = await callGemini(body.prompt, geminiApiKey);
    console.log("[recommendations] Gemini returned", recommendations.length, "recommendations");

    return new Response(JSON.stringify({ recommendations, groundingPlaces }), {
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
