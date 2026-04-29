import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { fetchPhotoUri } from "../_shared/places.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CACHE_TABLE_URL = `${SUPABASE_URL}/rest/v1/places_cache`;

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

    const { placeId }: { placeId?: string } = await req.json();
    if (!placeId) {
      return new Response(JSON.stringify({ error: "placeId is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const logTag = `[photos/${placeId.slice(0, 12)}]`;
    console.log(logTag, "Fetching gallery photos");

    // Look up photo_refs from cache (skip index 0 — that's the hero)
    const res = await fetch(
      `${CACHE_TABLE_URL}?place_id=eq.${encodeURIComponent(placeId)}&select=photo_refs&limit=1`,
      {
        headers: {
          "apikey": SUPABASE_SERVICE_ROLE_KEY,
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        },
      }
    );

    if (!res.ok) {
      console.warn(logTag, "Cache lookup failed", res.status);
      return new Response(JSON.stringify({ photos: [] }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const rows: Array<{ photo_refs: string[] }> = await res.json();
    if (!rows.length || !rows[0].photo_refs.length) {
      console.log(logTag, "No photo_refs found in cache");
      return new Response(JSON.stringify({ photos: [] }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Refs[0] is the hero (already resolved during enrich) — resolve the rest at 800px
    const galleryRefs = rows[0].photo_refs.slice(1);
    if (!galleryRefs.length) {
      return new Response(JSON.stringify({ photos: [] }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    console.log(logTag, "Resolving", galleryRefs.length, "gallery refs at 800px");

    const photos = (
      await Promise.all(galleryRefs.map((ref) => fetchPhotoUri(ref, placesApiKey, logTag, 800)))
    ).filter((u): u is string => !!u);

    console.log(logTag, "Resolved", photos.length, "gallery photos");

    return new Response(JSON.stringify({ photos }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[photos] 500:", message);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
