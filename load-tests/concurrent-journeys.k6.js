import http from "k6/http";
import { check, sleep } from "k6";
import encoding from "k6/encoding";
import { Counter, Rate, Trend } from "k6/metrics";

const apiBaseUrl = (__ENV.API_BASE_URL ?? "").replace(/\/$/, "");
const projectKey = __ENV.SUPABASE_ANON_KEY;
const concurrentUsers = integerEnv("CONCURRENT_USERS", 2);
const journeysPerUser = integerEnv("JOURNEYS_PER_USER", 1);
const thinkTimeSeconds = numberEnv("THINK_TIME_SECONDS", 0);
const maximumJourneys = integerEnv("MAX_JOURNEYS", 500);
const recommendationP95Ms = integerEnv("RECOMMENDATION_P95_MS", 15_000);
const completeJourneyP95Ms = integerEnv("COMPLETE_JOURNEY_P95_MS", 23_000);
const tokens = (__ENV.USER_ACCESS_TOKENS ?? "")
  .split(",")
  .map((token) => token.trim())
  .filter(Boolean);
const totalJourneys = concurrentUsers * journeysPerUser;

validateConfiguration();

const usableJourney = new Rate("usable_journey");
const enrichedJourney = new Rate("enriched_journey");
const capacityFailure = new Rate("capacity_failure");
const timeoutFailure = new Rate("timeout_failure");
const serverFailure = new Rate("server_failure");
const userLimitFailure = new Rate("user_limit_failure");
const recommendationLatency = new Trend("recommendation_latency", true);
const enrichmentLatency = new Trend("enrichment_latency", true);
const completeJourneyLatency = new Trend("complete_journey_latency", true);
const recommendationRequests = new Counter("recommendation_requests");
const enrichmentRequests = new Counter("enrichment_requests");
const geminiCalls = new Counter("gemini_calls");
const unmeteredGeminiCalls = new Counter("unmetered_gemini_calls");
const groundingQueries = new Counter("grounding_queries");
const geminiInputTokens = new Counter("gemini_input_tokens");
const geminiOutputTokens = new Counter("gemini_output_tokens");
const placesEnrichmentUnits = new Counter("places_enrichment_units");

export const options = {
  discardResponseBodies: false,
  summaryTrendStats: ["min", "med", "p(50)", "p(95)", "max"],
  scenarios: {
    concurrent_user_journeys: {
      executor: "per-vu-iterations",
      vus: concurrentUsers,
      iterations: journeysPerUser,
      maxDuration: __ENV.MAX_DURATION ?? "15m",
    },
  },
  thresholds: {
    usable_journey: ["rate>=0.95"],
    enriched_journey: ["rate>=0.90"],
    capacity_failure: ["rate<0.01"],
    timeout_failure: ["rate<0.01"],
    server_failure: ["rate<0.01"],
    user_limit_failure: ["rate==0"],
    recommendation_latency: [`p(95)<${recommendationP95Ms}`],
    complete_journey_latency: [`p(95)<${completeJourneyP95Ms}`],
  },
};

const testCases = [
  {
    occasion: "Dinner",
    vibe: ["Lively", "Casual"],
    hunger: ["Very hungry"],
    location: "Los Angeles, CA",
    prompt:
      "Find lively casual dinner restaurants in Los Angeles with a signature dish and concise parking guidance.",
  },
  {
    occasion: "Lunch",
    vibe: ["Low-key"],
    hunger: ["A little hungry"],
    location: "Pasadena, CA",
    prompt:
      "Find low-key lunch spots in Pasadena with a signature dish and concise parking guidance.",
  },
  {
    occasion: "Date night",
    vibe: ["Romantic"],
    hunger: ["Very hungry"],
    location: "Santa Monica, CA",
    prompt:
      "Find romantic date-night restaurants in Santa Monica with a signature dish and concise parking guidance.",
  },
  {
    occasion: "Brunch",
    vibe: ["Outdoor", "Relaxed"],
    hunger: ["Very hungry"],
    location: "Long Beach, CA",
    prompt:
      "Find relaxed outdoor brunch spots in Long Beach with a signature dish and concise parking guidance.",
  },
];

export default function () {
  const journeyStartedAt = Date.now();
  const token = tokens[__VU - 1];
  const payload = testCases[((__VU - 1) + __ITER) % testCases.length];
  const requestOptions = {
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
      "apikey": projectKey,
    },
    timeout: __ENV.REQUEST_TIMEOUT ?? "25s",
  };

  recommendationRequests.add(1);
  const recommendationResponse = http.post(
    `${apiBaseUrl}/recommendations`,
    JSON.stringify(payload),
    { ...requestOptions, tags: { endpoint: "recommendations" } },
  );
  recommendationLatency.add(recommendationResponse.timings.duration);
  recordFailure(recommendationResponse);
  recordGeminiUsage(recommendationResponse);

  const recommendationBody = jsonBody(recommendationResponse);
  const recommendations = recommendationBody?.recommendations ?? [];
  const hasUsableResults = recommendationResponse.status === 200 &&
    Array.isArray(recommendations) && recommendations.length > 0;
  usableJourney.add(hasUsableResults);

  check(recommendationResponse, {
    "recommendations returned usable JSON": () => hasUsableResults,
    "recommendation request is traceable": (response) =>
      Boolean(response.headers["X-Request-Id"]),
    "recommendation usage is instrumented": (response) =>
      Boolean(response.headers["X-Gemini-Calls"]) &&
      Boolean(response.headers["X-Grounding-Queries"]),
  });

  if (!hasUsableResults) {
    enrichedJourney.add(false);
    completeJourneyLatency.add(Date.now() - journeyStartedAt);
    paceUser();
    return;
  }

  enrichmentRequests.add(1);
  placesEnrichmentUnits.add(recommendations.length);
  const enrichmentResponse = http.post(
    `${apiBaseUrl}/enrich`,
    JSON.stringify({
      recommendations,
      groundingPlaces: recommendationBody.groundingPlaces ?? [],
      location: payload.location,
    }),
    { ...requestOptions, tags: { endpoint: "enrich" } },
  );
  enrichmentLatency.add(enrichmentResponse.timings.duration);
  recordFailure(enrichmentResponse);

  const enrichmentBody = jsonBody(enrichmentResponse);
  const enrichedRecommendations = enrichmentBody?.recommendations ?? [];
  const enriched = enrichmentResponse.status === 200 &&
    Array.isArray(enrichedRecommendations) &&
    enrichedRecommendations.length > 0;
  enrichedJourney.add(enriched);
  completeJourneyLatency.add(Date.now() - journeyStartedAt);

  check(enrichmentResponse, {
    "enrichment returned usable JSON": () => enriched,
    "enrichment reports remaining quota": (response) =>
      Boolean(response.headers["X-Daily-Budget-Remaining"]) &&
      Boolean(response.headers["X-Global-Daily-Budget-Remaining"]),
  });
  paceUser();
}

export function handleSummary(data) {
  const calls = counterValue(data, "gemini_calls");
  const unmeteredCalls = counterValue(data, "unmetered_gemini_calls");
  const queries = counterValue(data, "grounding_queries");
  const inputTokens = counterValue(data, "gemini_input_tokens");
  const outputTokens = counterValue(data, "gemini_output_tokens");
  const placesUnits = counterValue(data, "places_enrichment_units");
  const inputRate = numberEnv("INPUT_USD_PER_MILLION_TOKENS", 0);
  const outputRate = numberEnv("OUTPUT_USD_PER_MILLION_TOKENS", 0);
  const groundingRate = numberEnv("GROUNDING_QUERY_USD", 0);
  const placesRate = numberEnv("PLACES_ENRICHMENT_UNIT_USD", 0);
  const estimatedCost = inputTokens / 1_000_000 * inputRate +
    outputTokens / 1_000_000 * outputRate +
    queries * groundingRate +
    placesUnits * placesRate;
  const report = {
    configuration: {
      apiBaseUrl,
      concurrentUsers,
      journeysPerUser,
      totalJourneys,
      recommendationP95Ms,
      completeJourneyP95Ms,
    },
    results: {
      usableJourneyRate: rateValue(data, "usable_journey"),
      enrichedJourneyRate: rateValue(data, "enriched_journey"),
      capacityFailureRate: rateValue(data, "capacity_failure"),
      timeoutFailureRate: rateValue(data, "timeout_failure"),
      serverFailureRate: rateValue(data, "server_failure"),
      userLimitFailureRate: rateValue(data, "user_limit_failure"),
      recommendationP50Ms: trendValue(data, "recommendation_latency", "p(50)"),
      recommendationP95Ms: trendValue(data, "recommendation_latency", "p(95)"),
      enrichmentP95Ms: trendValue(data, "enrichment_latency", "p(95)"),
      completeJourneyP95Ms: trendValue(
        data,
        "complete_journey_latency",
        "p(95)",
      ),
      recommendationRequests: counterValue(data, "recommendation_requests"),
      enrichmentRequests: counterValue(data, "enrichment_requests"),
      geminiCalls: calls,
      unmeteredGeminiCalls: unmeteredCalls,
      groundingQueries: queries,
      geminiInputTokens: inputTokens,
      geminiOutputTokens: outputTokens,
      placesEnrichmentUnits: placesUnits,
      estimatedCostLowerBoundUsd: estimatedCost,
      costEstimateComplete: unmeteredCalls === 0 &&
        (placesUnits === 0 || placesRate > 0),
      costRatesConfigured: {
        geminiInput: inputRate > 0,
        geminiOutput: outputRate > 0,
        mapsGrounding: groundingRate > 0,
        placesEnrichment: placesRate > 0,
      },
    },
  };

  const outputs = { stdout: `${JSON.stringify(report, null, 2)}\n` };
  if (__ENV.SUMMARY_PATH) {
    outputs[__ENV.SUMMARY_PATH] = JSON.stringify(report, null, 2);
  }
  return outputs;
}

function validateConfiguration() {
  if (__ENV.CONFIRM_PAID_TEST !== "yes") {
    throw new Error(
      "Set CONFIRM_PAID_TEST=yes to acknowledge that this test invokes paid providers.",
    );
  }
  if (!apiBaseUrl) throw new Error("API_BASE_URL is required.");
  if (!projectKey) throw new Error("SUPABASE_ANON_KEY is required.");
  if (totalJourneys > maximumJourneys) {
    throw new Error(
      `The requested ${totalJourneys} journeys exceed MAX_JOURNEYS (${maximumJourneys}).`,
    );
  }
  if (journeysPerUser > 30) {
    throw new Error(
      "JOURNEYS_PER_USER exceeds the default per-user daily recommendation quota (30).",
    );
  }
  if (tokens.length < concurrentUsers) {
    throw new Error(
      "USER_ACCESS_TOKENS must contain one dedicated signed-in user token per concurrent user.",
    );
  }

  const subjects = new Set();
  for (const token of tokens.slice(0, concurrentUsers)) {
    const claims = jwtClaims(token);
    if (!claims.sub) {
      throw new Error("Every test token must contain a subject claim.");
    }
    if (claims.exp && claims.exp <= Date.now() / 1000) {
      throw new Error(`The test token for ${claims.sub} has expired.`);
    }
    subjects.add(claims.sub);
  }
  if (subjects.size !== concurrentUsers) {
    throw new Error(
      "Each concurrent user must have a distinct authenticated identity.",
    );
  }
}

function jwtClaims(token) {
  const segment = token.split(".")[1];
  if (!segment) throw new Error("USER_ACCESS_TOKENS contains an invalid JWT.");
  try {
    return JSON.parse(encoding.b64decode(segment, "rawurl", "s"));
  } catch {
    throw new Error("USER_ACCESS_TOKENS contains a JWT with invalid claims.");
  }
}

function recordFailure(response) {
  const body = jsonBody(response);
  const code = body?.code ?? "";
  capacityFailure.add(
    code === "UPSTREAM_CAPACITY" || code === "GLOBAL_BUDGET_EXCEEDED",
  );
  timeoutFailure.add(code === "UPSTREAM_TIMEOUT");
  userLimitFailure.add(code === "USAGE_LIMIT_EXCEEDED");
  serverFailure.add(
    response.status >= 500 && code !== "UPSTREAM_CAPACITY" &&
      code !== "UPSTREAM_TIMEOUT",
  );
}

function recordGeminiUsage(response) {
  const calls = numberHeader(response, "X-Gemini-Calls");
  const totalTokens = numberHeader(response, "X-Gemini-Total-Tokens");
  geminiCalls.add(calls);
  if (calls > 0 && totalTokens === 0) unmeteredGeminiCalls.add(calls);
  groundingQueries.add(numberHeader(response, "X-Grounding-Queries"));
  geminiInputTokens.add(numberHeader(response, "X-Gemini-Input-Tokens"));
  geminiOutputTokens.add(numberHeader(response, "X-Gemini-Output-Tokens"));
}

function jsonBody(response) {
  try {
    return response.json();
  } catch {
    return null;
  }
}

function paceUser() {
  if (thinkTimeSeconds > 0 && __ITER + 1 < journeysPerUser) {
    sleep(thinkTimeSeconds);
  }
}

function integerEnv(name, fallback) {
  const value = Number(__ENV[name] ?? fallback);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer.`);
  }
  return value;
}

function numberEnv(name, fallback) {
  const value = Number(__ENV[name] ?? fallback);
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${name} must be a non-negative number.`);
  }
  return value;
}

function numberHeader(response, name) {
  const value = Number(response.headers[name] ?? 0);
  return Number.isFinite(value) ? value : 0;
}

function counterValue(data, name) {
  return data.metrics[name]?.values?.count ?? 0;
}

function rateValue(data, name) {
  return data.metrics[name]?.values?.rate ?? 0;
}

function trendValue(data, name, key) {
  return data.metrics[name]?.values?.[key] ?? null;
}
