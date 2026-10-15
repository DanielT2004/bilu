import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handleRecommendations,
  RECOMMENDATIONS_BUDGET,
  RECOMMENDATIONS_TOTAL_BUDGET_MS,
  recommendationsDependencies,
} from "./handler.ts";

/** GeminiService.recommendationTimeout in the iOS app. */
const CLIENT_TIMEOUT_MS = 30_000;
/** Each pre-check fetch (auth, discovery access, paid quota) times out at 5 s. */
const PRECHECK_FETCH_TIMEOUT_MS = 5_000;
const PRECHECK_COUNT = 3;

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Millisecond-scale budget so the slow-path tests run quickly. */
const testBudget = {
  generationDeadlineMs: 300,
  minimumGenerationMs: 60,
  refundTimeoutMs: 100,
};

interface Ledger {
  consumed: number;
  refunds: number;
  refundTimeouts: (number | undefined)[];
  generationStarts: number[];
  generationAborted: boolean;
}

function fakes(options: {
  precheckDelayMs?: number;
  generationMs?: number;
  ignoreAbort?: boolean;
}) {
  const ledger: Ledger = {
    consumed: 0,
    refunds: 0,
    refundTimeouts: [],
    generationStarts: [],
    generationAborted: false,
  };
  const precheck = options.precheckDelayMs ?? 0;
  const dependencies: typeof recommendationsDependencies = {
    ...recommendationsDependencies,
    budget: testBudget,
    authenticate: async () => {
      await delay(precheck);
      return { id: "user-1", isAnonymous: true };
    },
    consumeAccess: async () => {
      await delay(precheck);
      ledger.consumed += 1;
      return "free" as const;
    },
    consumeQuota: async () => {
      await delay(precheck);
      return {
        allowed: true,
        retryAfterSeconds: 0,
        minuteRemaining: 4,
        dailyRemaining: 29,
        globalDailyRemaining: 999,
      };
    },
    refundAccess: (_user, _source, _token, timeoutMs) => {
      ledger.refunds += 1;
      ledger.refundTimeouts.push(timeoutMs);
      return Promise.resolve(true);
    },
    generate: (
      _prompt,
      _key,
      _lat,
      _lng,
      _radius,
      _location,
      _occasion,
      _metrics,
      abortSignal,
    ) => {
      const startedAt = performance.now();
      ledger.generationStarts.push(startedAt);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          resolve({
            recommendations: [{
              name: "Tartine",
              image: "",
              dish: "Croissant",
              explanation: "Flaky",
              mapsUrl: "",
              parking: "Not confirmed",
            }],
            groundingPlaces: [],
            relaxed: false,
          });
        }, options.generationMs ?? 0);
        if (!options.ignoreAbort) {
          abortSignal.addEventListener("abort", () => {
            ledger.generationAborted = true;
            clearTimeout(timer);
            reject(abortSignal.reason);
          });
        }
      });
    },
  };
  return { ledger, dependencies };
}

async function run(dependencies: typeof recommendationsDependencies) {
  const previous = Deno.env.get("GEMINI_API_KEY");
  const previousCommerce = Deno.env.get("BILU_COMMERCE_ENABLED");
  Deno.env.set("GEMINI_API_KEY", "local-test-no-provider-call");
  Deno.env.delete("BILU_COMMERCE_ENABLED");
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () =>
    Promise.reject(new Error("External calls are forbidden by this test"));
  const startedAt = performance.now();
  try {
    const response = await handleRecommendations(
      new Request("https://local.invalid/recommendations", {
        method: "POST",
        headers: { Authorization: "Bearer test" },
        body: JSON.stringify({ prompt: "Dinner in LA" }),
      }),
      undefined,
      dependencies,
    );
    const body = await response.json();
    return {
      response,
      body,
      elapsedMs: performance.now() - startedAt,
      startedAt,
    };
  } finally {
    globalThis.fetch = originalFetch;
    if (previous === undefined) Deno.env.delete("GEMINI_API_KEY");
    else Deno.env.set("GEMINI_API_KEY", previous);
    if (previousCommerce !== undefined) {
      Deno.env.set("BILU_COMMERCE_ENABLED", previousCommerce);
    }
  }
}

Deno.test("worst-case server time stays well inside the client timeout", () => {
  const worstPrechecks = PRECHECK_COUNT * PRECHECK_FETCH_TIMEOUT_MS;
  // Gemini ends at the generation deadline no matter how long checks took.
  assert(worstPrechecks < RECOMMENDATIONS_BUDGET.generationDeadlineMs);
  assertEquals(RECOMMENDATIONS_TOTAL_BUDGET_MS, 24_000);
  // Leave at least 5 s for cold start, TLS and the gateway, which the
  // handler's own clock cannot see.
  assert(CLIENT_TIMEOUT_MS - RECOMMENDATIONS_TOTAL_BUDGET_MS >= 5_000);
  // Even with the worst checks, a started Gemini call gets a real window.
  assert(
    RECOMMENDATIONS_BUDGET.generationDeadlineMs - worstPrechecks >=
      RECOMMENDATIONS_BUDGET.minimumGenerationMs,
  );
});

Deno.test("a fast request returns results and keeps the discovery spent", async () => {
  const { ledger, dependencies } = fakes({ generationMs: 10 });
  const { response, body } = await run(dependencies);
  assertEquals(response.status, 200);
  assertEquals(body.recommendations[0].name, "Tartine");
  assertEquals(ledger.consumed, 1);
  assertEquals(ledger.refunds, 0);
});

Deno.test("slow pre-checks shrink the Gemini window instead of extending the request", async () => {
  // 3 × 60 ms of checks leaves ~120 ms of a 300 ms deadline; Gemini needs 250 ms.
  const { ledger, dependencies } = fakes({
    precheckDelayMs: 60,
    generationMs: 250,
  });
  const { response, body, elapsedMs } = await run(dependencies);
  assertEquals(response.status, 504);
  assertEquals(body.code, "UPSTREAM_TIMEOUT");
  assert(ledger.generationAborted, "Gemini is told to stop at the deadline");
  assertEquals(ledger.consumed, 1);
  assertEquals(ledger.refunds, 1, "A server timeout returns the discovery");
  assertEquals(ledger.refundTimeouts, [testBudget.refundTimeoutMs]);
  assert(
    elapsedMs < testBudget.generationDeadlineMs + testBudget.refundTimeoutMs,
    `Responded after ${elapsedMs} ms`,
  );
});

Deno.test("checks that leave too little time skip Gemini and refund", async () => {
  // 3 × 85 ms leaves ~45 ms, below the 60 ms minimum generation window.
  const { ledger, dependencies } = fakes({
    precheckDelayMs: 85,
    generationMs: 10,
  });
  const { response, body } = await run(dependencies);
  assertEquals(response.status, 504);
  assertEquals(body.code, "UPSTREAM_TIMEOUT");
  assertEquals(ledger.generationStarts.length, 0, "No paid Gemini call");
  assertEquals(ledger.refunds, 1);
});

Deno.test("a provider that ignores the abort still cannot delay the response", async () => {
  const { ledger, dependencies } = fakes({
    generationMs: 1_000,
    ignoreAbort: true,
  });
  const { response, elapsedMs } = await run(dependencies);
  assertEquals(response.status, 504);
  assertEquals(ledger.refunds, 1);
  assert(
    elapsedMs < testBudget.generationDeadlineMs + testBudget.refundTimeoutMs,
    `Responded after ${elapsedMs} ms`,
  );
  // Let the ignored provider timer finish so the test leaks no timers.
  await delay(1_000);
});

Deno.test("a success just inside the deadline is returned and not refunded", async () => {
  const { ledger, dependencies } = fakes({
    precheckDelayMs: 20,
    generationMs: 120,
  });
  const { response, elapsedMs } = await run(dependencies);
  assertEquals(response.status, 200);
  assertEquals(ledger.refunds, 0);
  assert(elapsedMs < testBudget.generationDeadlineMs);
});
