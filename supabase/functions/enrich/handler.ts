import {
  type DiscoveryExecution,
  requireMeteredDiscovery,
} from "../_shared/discovery_execution.ts";
import { enrichRecommendation } from "../_shared/places.ts";
import type { GroundingPlace, Recommendation } from "../_shared/places.ts";
import { MAX_RECOMMENDATIONS } from "../_shared/recommendation_limits.ts";
import {
  consumePaidAPIQuota,
  paidAPIAccessErrorResponse,
  quotaHeaders,
  quotaPolicy,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";

const PAID_API_QUOTA = quotaPolicy(
  "places_enrich",
  "PLACES_ENRICH",
  25,
  150,
  5_000,
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Expose-Headers":
    "retry-after, x-ratelimit-remaining, x-daily-budget-remaining, x-global-daily-budget-remaining",
};

interface EnrichRequest {
  recommendations: Recommendation[];
  groundingPlaces: GroundingPlace[];
  location?: string;
  latitude?: number;
  longitude?: number;
}

export async function handleEnrichment(
  req: Request,
  execution?: DiscoveryExecution,
): Promise<Response> {
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
      return new Response(
        JSON.stringify({ error: "GOOGLE_PLACES_API_KEY not configured" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const body: EnrichRequest = await req.json();

    if (!body.recommendations?.length) {
      return new Response(
        JSON.stringify({ error: "recommendations array is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    if (body.recommendations.length > MAX_RECOMMENDATIONS) {
      return new Response(
        JSON.stringify({
          error: `at most ${MAX_RECOMMENDATIONS} recommendations are allowed`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    requireMeteredDiscovery(execution);
    const user = execution?.user ?? await requireAuthenticatedUser(req);
    const quota = await consumePaidAPIQuota(
      user.id,
      PAID_API_QUOTA,
      body.recommendations.length,
    );

    const searchArea = body.location?.trim() ||
      (body.latitude != null && body.longitude != null
        ? `${body.latitude.toFixed(4)}, ${body.longitude.toFixed(4)}`
        : "");
    const groundingPlaces: GroundingPlace[] = body.groundingPlaces ?? [];

    console.log(
      "[enrich] Enriching",
      body.recommendations.length,
      "recommendations for",
      searchArea,
    );

    const results = await Promise.all(
      body.recommendations.map((rec, i) =>
        enrichRecommendation(rec, placesApiKey, i, searchArea, groundingPlaces)
      ),
    );

    // Only an explicit live Places confirmation makes a restaurant feed-eligible.
    // Closed and unknown statuses intentionally fail closed.
    const recommendations = results
      .map((r) => r.rec)
      .filter((rec) => rec.isOpen === true);
    const excludedCount = results.length - recommendations.length;
    if (excludedCount > 0) {
      console.log(
        "[enrich] Excluded",
        excludedCount,
        "closed or unverified recommendations",
      );
    }
    const errors = results.map((r) => r.error).filter(Boolean);
    if (errors.length > 0) {
      console.warn("[enrich] Enrichment errors:", errors);
    }
    // Places could not confirm these (lookup failed or no live status). The
    // app uses this to tell "couldn't load details" apart from "all closed".
    const unverifiedCount = results.filter((r) => r.rec.isOpen === undefined)
      .length;

    return new Response(JSON.stringify({ recommendations, unverifiedCount }), {
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
    console.error("[enrich] 500:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}
