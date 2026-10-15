// POST /tiktok-resolve — turns one TikTok link the user shared into Bilu
// (through the biluShare extension) into the restaurant(s) it is about.
//
// Cost: TikTok's public oEmbed endpoint (free) for the caption, then the
// shared place pipeline (one Gemini Flash Lite call + Places lookups through
// the 30-day cache). No Apify call, so no transcript: the caption is the only
// text source. That keeps each resolve cheap; see the plan for adding
// transcripts later.
import {
  type AuthenticatedUser,
  consumePaidAPIQuota,
  paidAPIAccessErrorResponse,
  type PaidAPIQuotaPolicy,
  quotaHeaders,
  quotaPolicy,
  type QuotaResult,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";
import {
  locatePlaces,
  type LocatePlacesInput,
  type LocatePlacesResult,
} from "../_shared/tiktok_places.ts";

const PAID_API_QUOTA = quotaPolicy(
  "tiktok_resolve",
  "TIKTOK_RESOLVE",
  5,
  30,
  2_000,
);

/** Hosts a shared link may start on. Short links redirect to www.tiktok.com. */
const TIKTOK_HOSTS = new Set([
  "tiktok.com",
  "www.tiktok.com",
  "m.tiktok.com",
  "vm.tiktok.com",
  "vt.tiktok.com",
]);
const SHORT_LINK_HOSTS = new Set(["vm.tiktok.com", "vt.tiktok.com"]);
const MAX_REDIRECTS = 3;
const OEMBED_URL = "https://www.tiktok.com/oembed";
const MAX_CAPTION_CHARS = 2_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Expose-Headers":
    "retry-after, x-ratelimit-remaining, x-daily-budget-remaining, x-global-daily-budget-remaining",
};

interface RequestBody {
  shareUrl?: unknown;
  /** The user's city (the app already resolves it for TikTok search). */
  city?: unknown;
  latitude?: unknown;
  longitude?: unknown;
}

export interface SharedVideo {
  videoId: string;
  caption: string;
  canonicalUrl: string;
  authorName: string | null;
  thumbnailUrl: string | null;
}

export interface ResolveDependencies {
  authenticate(req: Request): Promise<AuthenticatedUser>;
  consumeQuota(
    userId: string,
    policy: PaidAPIQuotaPolicy,
  ): Promise<QuotaResult>;
  fetch: typeof fetch;
  locate(
    input: LocatePlacesInput,
    geminiApiKey: string,
    placesApiKey: string,
  ): Promise<LocatePlacesResult>;
  env(name: string): string | undefined;
}

export const resolveDependencies: ResolveDependencies = {
  authenticate: requireAuthenticatedUser,
  consumeQuota: (userId, policy) => consumePaidAPIQuota(userId, policy),
  fetch: (input, init) => fetch(input, init),
  locate: locatePlaces,
  env: (name) => Deno.env.get(name),
};

function json(
  status: number,
  body: unknown,
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, ...extra, "Content-Type": "application/json" },
  });
}

/** Parses and checks that a link points at TikTok over HTTPS. Returns null for
 * anything else, so the function never fetches an arbitrary URL. */
export function parseTikTokURL(value: unknown): URL | null {
  if (typeof value !== "string" || value.length > 2_048) return null;
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "https:") return null;
  if (url.username || url.password || url.port) return null;
  if (!TIKTOK_HOSTS.has(url.hostname.toLowerCase())) return null;
  return url;
}

/** The numeric video id from a canonical link (/@user/video/123…). */
export function videoIdFromURL(url: URL): string | null {
  const match = url.pathname.match(/\/video\/(\d{6,25})(?:\/|$)/);
  return match ? match[1] : null;
}

/** Follows vm./vt. short links to the canonical www.tiktok.com URL without
 * ever leaving TikTok's hosts. */
export async function expandShortLink(
  url: URL,
  fetcher: typeof fetch,
): Promise<URL | null> {
  let current = url;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (!SHORT_LINK_HOSTS.has(current.hostname.toLowerCase())) return current;
    if (hop === MAX_REDIRECTS) return null;
    const response = await fetcher(current.toString(), {
      method: "GET",
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
    });
    await response.body?.cancel();
    const location = response.headers.get("location");
    if (response.status < 300 || response.status >= 400 || !location) {
      return null;
    }
    const next = parseTikTokURL(new URL(location, current).toString());
    if (!next) return null;
    current = next;
  }
  return null;
}

/** Reads the caption and video id through TikTok's public oEmbed endpoint. */
export async function fetchSharedVideo(
  url: URL,
  fetcher: typeof fetch,
): Promise<SharedVideo | null> {
  const endpoint = `${OEMBED_URL}?url=${encodeURIComponent(url.toString())}`;
  const response = await fetcher(endpoint, {
    method: "GET",
    signal: AbortSignal.timeout(8_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    return null;
  }
  let data: Record<string, unknown>;
  try {
    data = await response.json();
  } catch {
    return null;
  }
  const html = typeof data.html === "string" ? data.html : "";
  const fromHtml = html.match(/data-video-id="(\d{6,25})"/)?.[1] ?? null;
  const videoId = fromHtml ?? videoIdFromURL(url);
  if (!videoId) return null;
  const cite = html.match(/cite="([^"]+)"/)?.[1];
  const canonical = (cite && parseTikTokURL(cite)) || url;
  return {
    videoId,
    caption: typeof data.title === "string"
      ? data.title.slice(0, MAX_CAPTION_CHARS)
      : "",
    canonicalUrl: canonical.toString(),
    authorName: typeof data.author_name === "string" ? data.author_name : null,
    thumbnailUrl: typeof data.thumbnail_url === "string"
      ? data.thumbnail_url
      : null,
  };
}

function finiteNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value)
    ? value
    : undefined;
}

export async function handleTikTokResolve(
  req: Request,
  deps: ResolveDependencies = resolveDependencies,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  const geminiApiKey = deps.env("GEMINI_API_KEY");
  const placesApiKey = deps.env("GOOGLE_PLACES_API_KEY");
  if (!geminiApiKey || !placesApiKey) {
    return json(500, {
      error: "GEMINI_API_KEY or GOOGLE_PLACES_API_KEY not configured",
      charged: false,
    });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "Invalid JSON body" });
  }

  const shareUrl = parseTikTokURL(body.shareUrl);
  if (!shareUrl) {
    return json(400, {
      error: "invalid_share_url",
      message: "That link isn't a TikTok video.",
    });
  }
  const city = typeof body.city === "string"
    ? body.city.trim().slice(0, 80)
    : "";

  let charged = false;
  try {
    // Free steps first, so a dead or private link never spends the user's
    // quota: authenticate, expand the short link, read the caption.
    const user = await deps.authenticate(req);

    const canonical = await expandShortLink(shareUrl, deps.fetch);
    if (!canonical) {
      return json(422, {
        error: "unresolvable_link",
        message: "We couldn't open that TikTok link.",
      });
    }

    const video = await fetchSharedVideo(canonical, deps.fetch);
    if (!video) {
      return json(422, {
        error: "video_unavailable",
        message: "That video is private, deleted, or not available.",
      });
    }

    // The pipeline can only place a video once it knows the city, and it
    // learns that from the city we pass. Without one, answer before any paid
    // call instead of spending quota and a Gemini call on a certain miss.
    if (!city) {
      return json(400, {
        error: "missing_city",
        message: "Turn on location or pick a city to match this video.",
        video,
      });
    }

    const quota = await deps.consumeQuota(user.id, PAID_API_QUOTA);
    // From here on the user's quota unit is spent. paid_api_guard has no
    // refund for paid-API quota (only the discovery allowance has one), so a
    // failure below can't be undone; it is reported as `charged: true` so the
    // app never retries it automatically.
    charged = true;

    const result = await deps.locate(
      {
        videos: [{
          videoId: video.videoId,
          desc: video.caption,
          viewCount: 0,
          shareUrl: video.canonicalUrl,
        }],
        searchQuery: `food in ${city}`,
        // The user's own city is authoritative for a shared link, so the
        // pipeline never answers missing_city for a request that sent one.
        queryCity: city,
        latitude: finiteNumber(body.latitude),
        longitude: finiteNumber(body.longitude),
      },
      geminiApiKey,
      placesApiKey,
    );

    // With a supplied city the pipeline shouldn't report missing_city; if it
    // does, the honest answer is "no place found", never "choose a city".
    return json(200, {
      video,
      places: result.kind === "ok" ? result.locations : [],
      queryCity: result.kind === "ok" ? result.queryCity : city,
    }, quotaHeaders(quota));
  } catch (err) {
    const accessResponse = paidAPIAccessErrorResponse(err, corsHeaders);
    if (accessResponse) return accessResponse;
    // Error kind only: exception messages can quote upstream bodies.
    console.error(JSON.stringify({
      event: "tiktok_resolve_failed",
      charged,
      errorName: safeErrorName(err),
    }));
    return charged
      ? json(502, {
        error: "place_lookup_failed",
        charged: true,
        message: "We couldn't match this video right now.",
      })
      : json(500, { error: "resolve_failed", charged: false });
  }
}

/** A loggable error class name ("TypeError", "TimeoutError"), never a message. */
function safeErrorName(err: unknown): string {
  const name = err instanceof Error ? err.name : typeof err;
  return /^[A-Za-z]{1,40}$/.test(name) ? name : "Unknown";
}
