import {
  type DiscoveryExecution,
  requireMeteredDiscovery,
} from "../_shared/discovery_execution.ts";
import { GoogleGenAI, ThinkingLevel } from "npm:@google/genai@1.46.0";
import type { GroundingPlace, Recommendation } from "../_shared/places.ts";
import { MAX_RECOMMENDATIONS } from "../_shared/recommendation_limits.ts";
import {
  consumeDiscoveryAccess,
  refundDiscoveryAccess,
} from "../_shared/discovery_access.ts";
import {
  consumePaidAPIQuota,
  paidAPIAccessErrorResponse,
  quotaHeaders,
  quotaPolicy,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";

/** Gemini model — see https://ai.google.dev/gemini-api/docs */
const GEMINI_MODEL = "gemini-3.6-flash";
// Maps-grounded generations regularly need more than eight seconds. Keep the
// whole search below the 20-second SLO while allowing the first attempt enough
// time to complete; fast malformed/empty responses can still use the fallback.
const GEMINI_ATTEMPT_TIMEOUT_MS = 18_000;
// The iOS client waits 30 s (GeminiService.recommendationTimeout) so this
// deadline, which refunds the reserved discovery, always fires first.
const RECOMMENDATIONS_DEADLINE_MS = 19_000;
const CAPACITY_COOLDOWN_MS = 60_000;
let capacityUnavailableUntil = 0;
const PAID_API_QUOTA = quotaPolicy(
  "recommendations",
  "RECOMMENDATIONS",
  5,
  30,
  1_000,
);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-rewarded-access-token",
  "Access-Control-Expose-Headers":
    "retry-after, server-timing, x-request-id, x-gemini-calls, x-grounding-queries, x-gemini-input-tokens, x-gemini-output-tokens, x-gemini-total-tokens, x-ratelimit-remaining, x-daily-budget-remaining, x-global-daily-budget-remaining",
};

interface CapacityMetrics {
  geminiCalls: number;
  groundingQueries: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  geminiDurationMs: number;
}

class UpstreamCapacityError extends Error {
  constructor() {
    super("Gemini capacity is temporarily unavailable");
    this.name = "UpstreamCapacityError";
  }
}

class UpstreamTimeoutError extends Error {
  constructor() {
    super("Gemini exceeded the recommendation latency budget");
    this.name = "UpstreamTimeoutError";
  }
}

function isUpstreamTimeoutError(error: unknown): boolean {
  const candidate = error as { name?: unknown; message?: unknown };
  const name = String(candidate?.name ?? "").toLowerCase();
  const message = String(candidate?.message ?? error).toLowerCase();
  return name.includes("abort") || name.includes("timeout") ||
    message.includes("aborted") || message.includes("timeout") ||
    message.includes("timed out");
}

function isUpstreamCapacityError(error: unknown): boolean {
  const candidate = error as {
    status?: unknown;
    code?: unknown;
    message?: unknown;
  };
  const status = Number(candidate?.status ?? candidate?.code);
  const message = String(candidate?.message ?? error).toLowerCase();
  return status === 429 ||
    message.includes("resource_exhausted") ||
    message.includes("quota") ||
    message.includes("rate limit") ||
    message.includes("spending cap") ||
    message.includes("spending limit");
}

function upstreamStatus(error: unknown): number | undefined {
  const candidate = error as { status?: unknown; code?: unknown };
  const status = Number(candidate?.status ?? candidate?.code);
  return Number.isFinite(status) ? status : undefined;
}

function logGenerationFailure(layer: string, error: unknown) {
  console.warn(JSON.stringify({
    event: "recommendations_generation_failed",
    layer,
    upstreamStatus: upstreamStatus(error),
  }));
}

function instrumentedHeaders(requestId: string, metrics: CapacityMetrics) {
  return {
    ...corsHeaders,
    "Content-Type": "application/json",
    "Server-Timing": `gemini;dur=${metrics.geminiDurationMs.toFixed(1)}`,
    "X-Request-Id": requestId,
    "X-Gemini-Calls": String(metrics.geminiCalls),
    "X-Grounding-Queries": String(metrics.groundingQueries),
    "X-Gemini-Input-Tokens": String(metrics.inputTokens),
    "X-Gemini-Output-Tokens": String(metrics.outputTokens),
    "X-Gemini-Total-Tokens": String(metrics.totalTokens),
  };
}

function logCapacity(
  requestId: string,
  status: number,
  startedAt: number,
  metrics: CapacityMetrics,
) {
  console.log(JSON.stringify({
    event: "recommendations_capacity",
    requestId,
    status,
    durationMs: Math.round(performance.now() - startedAt),
    ...metrics,
  }));
}

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
  locationConfig: Record<string, unknown>,
  metrics: CapacityMetrics,
  abortSignal: AbortSignal,
): Promise<GeminiCallResult> {
  metrics.geminiCalls += 1;
  const startedAt = performance.now();
  let response: Awaited<ReturnType<typeof ai.models.generateContent>>;
  try {
    response = await ai.models.generateContent({
      model: GEMINI_MODEL,
      contents: prompt,
      config: {
        systemInstruction,
        temperature,
        thinkingConfig: { thinkingLevel: ThinkingLevel.MINIMAL },
        maxOutputTokens: 2_048,
        abortSignal,
        httpOptions: {
          timeout: GEMINI_ATTEMPT_TIMEOUT_MS,
          retryOptions: { attempts: 1 },
        },
        // Gemini 3.6 supports the named MINIMAL level. Its legacy numeric
        // thinkingBudget rejects zero, so do not substitute that older setting.
        tools: [{ googleMaps: {} }],
        ...locationConfig,
      },
    });
  } finally {
    metrics.geminiDurationMs += performance.now() - startedAt;
  }

  const usage = response.usageMetadata;
  const inputTokens = usage?.promptTokenCount ?? 0;
  const totalTokens = usage?.totalTokenCount ?? 0;
  metrics.inputTokens += inputTokens;
  // Includes candidate and thinking tokens when the model reports them.
  metrics.outputTokens += Math.max(
    usage?.candidatesTokenCount ?? 0,
    totalTokens - inputTokens,
  );
  metrics.totalTokens += totalTokens;
  metrics.groundingQueries += (response.candidates ?? []).reduce(
    (count, candidate) =>
      count + (candidate.groundingMetadata?.webSearchQueries?.length ?? 0),
    0,
  );

  const rawText = response.text ?? "";
  if (!rawText.trim()) {
    throw new Error(
      "Gemini returned empty text (blocked, wrong model, or API error)",
    );
  }

  const cleaned = rawText.replace(/^```(?:json)?\s*/i, "").replace(
    /\s*```$/i,
    "",
  ).trim();
  if (!cleaned.startsWith("{")) {
    throw new Error("Gemini returned non-JSON prose");
  }

  let parsed: { recommendations?: Recommendation[] };
  try {
    parsed = JSON.parse(cleaned) as { recommendations?: Recommendation[] };
  } catch (e) {
    throw new Error(
      `Gemini JSON parse failed: ${e instanceof Error ? e.name : "unknown"}`,
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

  const recommendations = (parsed?.recommendations ?? []).slice(
    0,
    MAX_RECOMMENDATIONS,
  ).map((rec) => ({
    ...rec,
    parking: typeof rec.parking === "string" && rec.parking.trim()
      ? rec.parking.trim()
      : "Not confirmed",
  }));

  return {
    recommendations,
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
  occasion: string | undefined,
  metrics: CapacityMetrics,
): Promise<GeminiCallResult & { relaxed: boolean }> {
  const ai = new GoogleGenAI({ apiKey: geminiApiKey });
  const abortSignal = AbortSignal.timeout(RECOMMENDATIONS_DEADLINE_MS);
  const hasRadius = lat !== undefined && lng !== undefined &&
    radiusMiles !== undefined;

  // Soft contract — model must always return JSON, never refuse.
  const radiusClause = hasRadius
    ? ` Only suggest places within ${
      radiusMiles!.toFixed(1)
    } miles of the coordinates in the prompt.`
    : ` Find the best spots in the city or area specified in the prompt.`;
  const systemInstruction =
    `You are a local food discovery assistant.${radiusClause} ` +
    `Always respond with JSON only — never refuse, apologize, or write prose. ` +
    `Aim for ${MAX_RECOMMENDATIONS} distinct matching spots when available; return fewer when there aren't enough suitable places. Never invent places or repeat a restaurant to fill the list. If truly nothing fits, return { "recommendations": [] }. ` +
    `Every result must include concise parking guidance. Use "Not confirmed" when it cannot be verified; never guess.`;

  // Only anchor the Google Maps grounding to specific coordinates in radius mode.
  // In city-wide mode the grounding tool relies on the location string in the prompt.
  const locationConfig = (lat !== undefined && lng !== undefined)
    ? {
      toolConfig: {
        retrievalConfig: { latLng: { latitude: lat, longitude: lng } },
      },
    }
    : {};

  // ─── Layer 1: normal call at low temperature ────────────────────────────
  try {
    const result = await generateOnce(
      ai,
      systemInstruction,
      prompt,
      0.1,
      locationConfig,
      metrics,
      abortSignal,
    );
    if (result.recommendations.length > 0) {
      console.log("[recommendations] resolved at: layer1");
      console.log(
        "[recommendations] Grounding chunks extracted:",
        result.groundingPlaces.length,
        "places",
      );
      return { ...result, relaxed: false };
    }
    console.warn(
      "[recommendations] layer1 returned empty array — retrying with temp ladder",
    );
  } catch (e) {
    if (abortSignal.aborted || isUpstreamTimeoutError(e)) {
      throw new UpstreamTimeoutError();
    }
    if (isUpstreamCapacityError(e)) throw new UpstreamCapacityError();
    logGenerationFailure("layer1", e);
  }

  // ─── Layer 2: retry with temperature ladder to reshuffle grounding ──────
  try {
    const result = await generateOnce(
      ai,
      systemInstruction,
      prompt,
      0.7,
      locationConfig,
      metrics,
      abortSignal,
    );
    if (result.recommendations.length > 0) {
      console.log("[recommendations] resolved at: layer2");
      console.log(
        "[recommendations] Grounding chunks extracted:",
        result.groundingPlaces.length,
        "places",
      );
      return { ...result, relaxed: false };
    }
    console.warn(
      "[recommendations] layer2 returned empty array — falling back to relaxed prompt",
    );
  } catch (e) {
    if (abortSignal.aborted || isUpstreamTimeoutError(e)) {
      throw new UpstreamTimeoutError();
    }
    if (isUpstreamCapacityError(e)) throw new UpstreamCapacityError();
    logGenerationFailure("layer2", e);
  }

  // ─── Layer 3: relaxed fallback — drops chain/quality filters entirely ───
  // Ask for popular spots when the stricter search finds no matches.
  // Tagged `relaxed: true` so the UI can show a
  // soft "we loosened your filters" banner.
  const relaxedLocation = location?.trim() || "the area in the prompt";
  const relaxedOccasion = occasion?.trim() || "a meal out";
  const relaxedPrompt =
    `Find up to ${MAX_RECOMMENDATIONS} popular, highly-rated spots for ${relaxedOccasion} near ${relaxedLocation}. ` +
    `Return JSON only: { "recommendations": [{ "name": "", "dish": "", "explanation": "", "mapsUrl": "", "parking": "" }] }. ` +
    `For parking, use verified concise guidance or "Not confirmed"; never guess. ` +
    `Each explanation: one short sentence on what the spot is known for.`;
  const relaxedSystem =
    `You are a local food discovery assistant. Always respond with JSON only — never refuse. ` +
    `Aim for ${MAX_RECOMMENDATIONS} distinct popular spots when available, even if filters are unspecified. Return fewer when there aren't enough suitable places; never invent places or repeat a restaurant to fill the list.`;

  let result: GeminiCallResult;
  try {
    result = await generateOnce(
      ai,
      relaxedSystem,
      relaxedPrompt,
      0.4,
      locationConfig,
      metrics,
      abortSignal,
    );
  } catch (e) {
    if (abortSignal.aborted || isUpstreamTimeoutError(e)) {
      throw new UpstreamTimeoutError();
    }
    if (isUpstreamCapacityError(e)) throw new UpstreamCapacityError();
    throw e;
  }
  console.log("[recommendations] resolved at: layer3 (relaxed)");
  console.log(
    "[recommendations] Grounding chunks extracted:",
    result.groundingPlaces.length,
    "places",
  );
  return { ...result, relaxed: true };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

export async function handleRecommendations(
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

  const requestId = crypto.randomUUID();
  const startedAt = performance.now();
  const metrics: CapacityMetrics = {
    geminiCalls: 0,
    groundingQueries: 0,
    inputTokens: 0,
    outputTokens: 0,
    totalTokens: 0,
    geminiDurationMs: 0,
  };
  let reservedAccess: {
    userId: string;
    source: "free" | "rewarded";
    rewardToken: string | null;
  } | null = null;

  try {
    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

    if (!geminiApiKey) {
      const status = 500;
      logCapacity(requestId, status, startedAt, metrics);
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
        {
          status,
          headers: instrumentedHeaders(requestId, metrics),
        },
      );
    }

    const body: RequestBody = await req.json();

    if (!body.prompt) {
      const status = 400;
      logCapacity(requestId, status, startedAt, metrics);
      return new Response(JSON.stringify({ error: "prompt is required" }), {
        status,
        headers: instrumentedHeaders(requestId, metrics),
      });
    }

    requireMeteredDiscovery(execution);
    const user = execution?.user ?? await requireAuthenticatedUser(req);

    // A warm Edge Function instance remembers a recent provider quota failure.
    // This is intentionally a best-effort circuit breaker; it prevents a burst
    // from repeatedly calling Gemini while the provider is already rejecting us.
    const cooldownRemainingMs = capacityUnavailableUntil - Date.now();
    if (cooldownRemainingMs > 0) {
      const status = 503;
      const retryAfter = Math.max(1, Math.ceil(cooldownRemainingMs / 1000));
      logCapacity(requestId, status, startedAt, metrics);
      return new Response(
        JSON.stringify({
          error:
            "Search capacity is temporarily unavailable. Please try again shortly.",
          code: "UPSTREAM_CAPACITY",
          requestId,
        }),
        {
          status,
          headers: {
            ...instrumentedHeaders(requestId, metrics),
            "Retry-After": String(retryAfter),
          },
        },
      );
    }

    const suppliedRewardToken = req.headers.get("x-rewarded-access-token");
    const rewardToken = suppliedRewardToken &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
          .test(
            suppliedRewardToken,
          )
      ? suppliedRewardToken
      : null;
    if (!execution) {
      const accessSource = await consumeDiscoveryAccess(user.id, rewardToken);
      reservedAccess = { userId: user.id, source: accessSource, rewardToken };
    }
    // Only bill the paid-API quota after access is reserved. A request rejected
    // for needing an ad must never consume the user's API allowance.
    const quota = await consumePaidAPIQuota(user.id, PAID_API_QUOTA);

    // Only use radius mode when ALL THREE fields are explicitly provided by the client.
    // If any are missing the request is treated as city-wide — no coordinate constraint.
    const hasRadius = body.latitude !== undefined &&
      body.longitude !== undefined &&
      body.radiusMiles !== undefined;

    const lat = hasRadius ? body.latitude : undefined;
    const lng = hasRadius ? body.longitude : undefined;
    const radiusMiles = hasRadius ? body.radiusMiles : undefined;

    // Log only non-identifying request metadata. Never retain user-entered
    // prompts, place names, occasions, or precise coordinates.
    console.log(JSON.stringify({
      event: "recommendations_request",
      requestId,
      mode: hasRadius ? "radius" : "city-wide",
      hasLocation: Boolean(body.location?.trim()),
      hasOccasion: Boolean(body.occasion?.trim()),
    }));

    const { recommendations, groundingPlaces, relaxed } = await callGemini(
      body.prompt,
      geminiApiKey,
      lat,
      lng,
      radiusMiles,
      body.location,
      body.occasion,
      metrics,
    );
    console.log(JSON.stringify({
      event: "recommendations_result",
      requestId,
      recommendationCount: recommendations.length,
      relaxed,
      groundingPlaceCount: groundingPlaces.length,
    }));

    const status = 200;
    logCapacity(requestId, status, startedAt, metrics);
    return new Response(
      JSON.stringify({ recommendations, groundingPlaces, relaxed }),
      {
        status,
        headers: {
          ...instrumentedHeaders(requestId, metrics),
          ...quotaHeaders(quota),
        },
      },
    );
  } catch (err) {
    if (reservedAccess) {
      await refundDiscoveryAccess(
        reservedAccess.userId,
        reservedAccess.source,
        reservedAccess.rewardToken,
      );
    }
    const accessResponse = paidAPIAccessErrorResponse(
      err,
      corsHeaders,
      instrumentedHeaders(requestId, metrics),
    );
    if (accessResponse) {
      logCapacity(requestId, accessResponse.status, startedAt, metrics);
      return accessResponse;
    }
    if (err instanceof UpstreamCapacityError) {
      const status = 503;
      capacityUnavailableUntil = Date.now() + CAPACITY_COOLDOWN_MS;
      console.warn(
        `[recommendations] ${requestId} upstream capacity unavailable`,
      );
      logCapacity(requestId, status, startedAt, metrics);
      return new Response(
        JSON.stringify({
          error:
            "Search capacity is temporarily unavailable. Please try again shortly.",
          code: "UPSTREAM_CAPACITY",
          requestId,
        }),
        {
          status,
          headers: {
            ...instrumentedHeaders(requestId, metrics),
            "Retry-After": "60",
          },
        },
      );
    }
    if (err instanceof UpstreamTimeoutError) {
      const status = 504;
      console.warn(
        `[recommendations] ${requestId} upstream latency budget exceeded`,
      );
      logCapacity(requestId, status, startedAt, metrics);
      return new Response(
        JSON.stringify({
          error: "Search took too long. Please try again.",
          code: "UPSTREAM_TIMEOUT",
          requestId,
        }),
        {
          status,
          headers: instrumentedHeaders(requestId, metrics),
        },
      );
    }
    console.error(JSON.stringify({
      event: "recommendations_error",
      requestId,
      upstreamStatus: upstreamStatus(err),
    }));
    logCapacity(requestId, 500, startedAt, metrics);
    return new Response(
      JSON.stringify({
        error: "Something went wrong while generating recommendations.",
        requestId,
      }),
      {
        status: 500,
        headers: instrumentedHeaders(requestId, metrics),
      },
    );
  }
}
