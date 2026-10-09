import http from "k6/http";
import { check } from "k6";
import { Counter, Rate, Trend } from "k6/metrics";

const targetUrl = __ENV.TARGET_URL;
const projectKey = __ENV.SUPABASE_ANON_KEY;
const vus = integerEnv("VUS", 2);
const totalRequests = integerEnv("TOTAL_REQUESTS", 10);
const maxRequests = integerEnv("MAX_REQUESTS", 500);
const p95TargetMs = integerEnv("P95_TARGET_MS", 20_000);
const userAccessTokens = (__ENV.USER_ACCESS_TOKENS ?? "")
  .split(",")
  .map((token) => token.trim())
  .filter(Boolean);

if (__ENV.CONFIRM_PAID_TEST !== "yes") {
  throw new Error(
    "Set CONFIRM_PAID_TEST=yes to acknowledge that this test makes paid upstream calls.",
  );
}
if (!targetUrl) throw new Error("TARGET_URL is required.");
if (!projectKey) throw new Error("SUPABASE_ANON_KEY is required.");
if (userAccessTokens.length < vus) {
  throw new Error(
    "USER_ACCESS_TOKENS must contain at least one signed-in test-user token per VU.",
  );
}
if (totalRequests > maxRequests) {
  throw new Error(
    `TOTAL_REQUESTS (${totalRequests}) exceeds MAX_REQUESTS (${maxRequests}).`,
  );
}
if (vus > totalRequests) throw new Error("VUS cannot exceed TOTAL_REQUESTS.");
if (totalRequests % vus !== 0) {
  throw new Error("TOTAL_REQUESTS must be evenly divisible by VUS.");
}

const successfulSearch = new Rate("successful_search");
const capacityExhausted = new Rate("capacity_exhausted");
const upstreamTimeout = new Rate("upstream_timeout");
const authRejected = new Counter("auth_rejected");
const userQuotaRejected = new Counter("user_quota_rejected");
const unexpectedFailures = new Counter("unexpected_failures");
const endToEndLatency = new Trend("recommendations_latency", true);
const geminiCalls = new Counter("gemini_calls");
const unmeteredGeminiCalls = new Counter("unmetered_gemini_calls");
const groundingQueries = new Counter("grounding_queries");
const geminiInputTokens = new Counter("gemini_input_tokens");
const geminiOutputTokens = new Counter("gemini_output_tokens");
const geminiTotalTokens = new Counter("gemini_total_tokens");

export const options = {
  discardResponseBodies: false,
  scenarios: {
    bounded_concurrency: {
      executor: "per-vu-iterations",
      vus,
      iterations: totalRequests / vus,
      maxDuration: __ENV.MAX_DURATION ?? "10m",
    },
  },
  thresholds: {
    checks: ["rate>=0.95"],
    successful_search: ["rate>=0.95"],
    capacity_exhausted: ["rate<0.01"],
    upstream_timeout: ["rate<0.01"],
    recommendations_latency: [`p(95)<${p95TargetMs}`],
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
];

export default function () {
  const payload = testCases[__ITER % testCases.length];
  const userAccessToken = userAccessTokens[__VU - 1];
  const response = http.post(targetUrl, JSON.stringify(payload), {
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${userAccessToken}`,
      "apikey": projectKey,
    },
    tags: { endpoint: "recommendations" },
    timeout: __ENV.REQUEST_TIMEOUT ?? "60s",
  });

  let errorCode = "";
  try {
    errorCode = response.json("code") ?? "";
  } catch {
    // A malformed body is caught by the checks below.
  }

  const succeeded = response.status === 200;
  const exhausted =
    (response.status === 503 && errorCode === "UPSTREAM_CAPACITY") ||
    (response.status === 429 && errorCode === "GLOBAL_BUDGET_EXCEEDED");
  const timedOut = response.status === 504 && errorCode === "UPSTREAM_TIMEOUT";
  if (!succeeded) {
    if (response.status === 401) authRejected.add(1);
    else if (response.status === 429 && errorCode === "USAGE_LIMIT_EXCEEDED") {
      userQuotaRejected.add(1);
    } else if (!exhausted && !timedOut) unexpectedFailures.add(1);
  }
  successfulSearch.add(succeeded);
  capacityExhausted.add(exhausted);
  upstreamTimeout.add(timedOut);
  endToEndLatency.add(response.timings.duration);
  const calls = numberHeader(response, "X-Gemini-Calls");
  const totalTokens = numberHeader(response, "X-Gemini-Total-Tokens");
  geminiCalls.add(calls);
  if (calls > 0 && totalTokens === 0) unmeteredGeminiCalls.add(calls);
  groundingQueries.add(numberHeader(response, "X-Grounding-Queries"));
  geminiInputTokens.add(numberHeader(response, "X-Gemini-Input-Tokens"));
  geminiOutputTokens.add(numberHeader(response, "X-Gemini-Output-Tokens"));
  geminiTotalTokens.add(totalTokens);

  check(response, {
    "search returned 200": () => succeeded,
    "response is JSON": (res) =>
      (res.headers["Content-Type"] ?? "").includes("application/json"),
    "request is traceable": (res) => Boolean(res.headers["X-Request-Id"]),
    "usage is instrumented": (res) =>
      Boolean(res.headers["X-Gemini-Calls"]) &&
      Boolean(res.headers["X-Grounding-Queries"]),
  });
}

export function handleSummary(data) {
  const calls = counterValue(data, "gemini_calls");
  const unmeteredCalls = counterValue(data, "unmetered_gemini_calls");
  const queries = counterValue(data, "grounding_queries");
  const inputTokens = counterValue(data, "gemini_input_tokens");
  const outputTokens = counterValue(data, "gemini_output_tokens");
  const inputRate = numberEnv("INPUT_USD_PER_MILLION_TOKENS", 0);
  const outputRate = numberEnv("OUTPUT_USD_PER_MILLION_TOKENS", 0);
  const perQueryRate = numberEnv("GROUNDING_QUERY_USD", 0);
  const estimatedCost = inputTokens / 1_000_000 * inputRate +
    outputTokens / 1_000_000 * outputRate +
    queries * perQueryRate;

  const report = {
    configuration: { targetUrl, vus, totalRequests, p95TargetMs },
    results: {
      successRate: rateValue(data, "successful_search"),
      capacityExhaustionRate: rateValue(data, "capacity_exhausted"),
      upstreamTimeoutRate: rateValue(data, "upstream_timeout"),
      authRejected: counterValue(data, "auth_rejected"),
      userQuotaRejected: counterValue(data, "user_quota_rejected"),
      unexpectedFailures: counterValue(data, "unexpected_failures"),
      p95LatencyMs: trendValue(data, "recommendations_latency", "p(95)"),
      geminiCalls: calls,
      groundingQueries: queries,
      geminiInputTokens: inputTokens,
      geminiOutputTokens: outputTokens,
      geminiTotalTokens: counterValue(data, "gemini_total_tokens"),
      unmeteredGeminiCalls: unmeteredCalls,
      estimatedCostLowerBoundUsd: estimatedCost,
      costEstimateComplete: unmeteredCalls === 0,
      costRatesConfigured: inputRate > 0 || outputRate > 0 || perQueryRate > 0,
    },
  };

  const outputs = { stdout: `${JSON.stringify(report, null, 2)}\n` };
  if (__ENV.SUMMARY_PATH) {
    outputs[__ENV.SUMMARY_PATH] = JSON.stringify(report, null, 2);
  }
  return outputs;
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
