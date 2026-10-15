import {
  type DiscoveryExecution,
  requireMeteredDiscovery,
} from "../_shared/discovery_execution.ts";
import {
  consumePaidAPIQuota,
  paidAPIAccessErrorResponse,
  quotaHeaders,
  quotaPolicy,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";
import {
  locatePlaces,
  MAX_INPUT_VIDEOS,
  type VideoInput,
} from "../_shared/tiktok_places.ts";

export { isTrustedTranscriptURL } from "../_shared/tiktok_places.ts";

const PAID_API_QUOTA = quotaPolicy(
  "tiktok_locations",
  "TIKTOK_LOCATIONS",
  10,
  40,
  1_000,
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Expose-Headers":
    "retry-after, x-ratelimit-remaining, x-daily-budget-remaining, x-global-daily-budget-remaining",
};

interface RequestBody {
  videos: VideoInput[];
  searchQuery: string;
  latitude?: number;
  longitude?: number;
}

export async function handleTikTokLocations(
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
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    const placesApiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");

    if (!geminiApiKey || !placesApiKey) {
      return new Response(
        JSON.stringify({
          error: "GEMINI_API_KEY or GOOGLE_PLACES_API_KEY not configured",
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
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
      return new Response(
        JSON.stringify({
          error: `at most ${MAX_INPUT_VIDEOS} videos are allowed`,
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
      1 + Math.ceil(body.videos.length / 5),
    );

    console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    console.log("[tiktok-locations] INCOMING REQUEST");
    console.log(`  videos:     ${body.videos.length}`);
    // Owner decision 4: lengths and booleans only, never the query or coords.
    console.log(`  searchQuery length: ${body.searchQuery?.length ?? 0}`);
    console.log(
      `  hasCoords:  ${body.latitude != null && body.longitude != null}`,
    );

    // Pass fields explicitly: the city always comes from the user's search
    // here, so a client can't supply the `queryCity` override.
    const result = await locatePlaces(
      {
        videos: body.videos,
        searchQuery: body.searchQuery,
        latitude: body.latitude,
        longitude: body.longitude,
      },
      geminiApiKey,
      placesApiKey,
    );
    if (result.kind === "missing_city") {
      return new Response(
        JSON.stringify({
          error: "missing_city",
          message: "Please include a city in your search.",
          suggestedCities: [
            "Los Angeles",
            "New York",
            "San Francisco",
            "Chicago",
          ],
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }
    const { locations, unresolved, queryCity } = result;

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
}
