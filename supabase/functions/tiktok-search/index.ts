import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RequestBody {
  query: string;
  maxResults?: number;
  sortType?: number;
  region?: string;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const apifyKey = Deno.env.get("APIFY_API_KEY");
  if (!apifyKey) {
    return new Response(
      JSON.stringify({ error: "APIFY_API_KEY not configured" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const query = body.query?.trim();
  if (!query) {
    return new Response(
      JSON.stringify({ error: "Missing 'query'" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const apifyUrl = `https://api.apify.com/v2/acts/scraptik~tiktok-api/run-sync-get-dataset-items?token=${apifyKey}`;
  const apifyBody = {
    searchPosts_count: body.maxResults ?? 10,
    searchPosts_keyword: query,
    searchPosts_sortType: body.sortType ?? 0,
    searchSounds_useFilters: false,
    searchPosts_region: body.region ?? "US",
  };

  try {
    const apifyResp = await fetch(apifyUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(apifyBody),
    });

    const text = await apifyResp.text();
    return new Response(text, {
      status: apifyResp.status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ error: `Apify request failed: ${(err as Error).message}` }),
      { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
