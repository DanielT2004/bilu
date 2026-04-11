import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { enrichRecommendation } from "../_shared/places.ts";
import type { Recommendation, GroundingPlace } from "../_shared/places.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface EnrichRequest {
  recommendations: Recommendation[];
  groundingPlaces: GroundingPlace[];
  location?: string;
  latitude?: number;
  longitude?: number;
}

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
    const placesApiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");

    if (!placesApiKey) {
      return new Response(JSON.stringify({ error: "GOOGLE_PLACES_API_KEY not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body: EnrichRequest = await req.json();

    if (!body.recommendations?.length) {
      return new Response(JSON.stringify({ error: "recommendations array is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const searchArea = body.location?.trim()
      || (body.latitude != null && body.longitude != null
          ? `${body.latitude.toFixed(4)}, ${body.longitude.toFixed(4)}`
          : "");
    const groundingPlaces: GroundingPlace[] = body.groundingPlaces ?? [];

    console.log("[enrich] Enriching", body.recommendations.length, "recommendations for", searchArea);

    const results = await Promise.all(
      body.recommendations.map((rec, i) =>
        enrichRecommendation(rec, placesApiKey, i, searchArea, groundingPlaces)
      )
    );

    const recommendations = results.map((r) => r.rec);
    const errors = results.map((r) => r.error).filter(Boolean);
    if (errors.length > 0) {
      console.warn("[enrich] Enrichment errors:", errors);
    }

    return new Response(JSON.stringify({ recommendations }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[enrich] 500:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
