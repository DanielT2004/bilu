import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  handleRecommendations,
  RECOMMENDATIONS_BUDGET,
  RECOMMENDATIONS_SUCCESS_DEADLINE_MS,
  RECOMMENDATIONS_WORST_CASE_MS,
  recommendationsDependencies,
} from "./handler.ts";
import {
  consumeDiscoveryAccess,
  refundDiscoveryAccess,
} from "../_shared/discovery_access.ts";
import {
  consumePaidAPIQuota,
  quotaPolicy,
  requireAuthenticatedUser,
} from "../_shared/paid_api_guard.ts";

/** Read from GeminiService.swift so the two sides cannot drift apart. */
const CLIENT_TIMEOUT_MS = await (async () => {
  const swift = await Deno.readTextFile(
    new URL("../../../bilu/Services/GeminiService.swift", import.meta.url),
  );
  const match = swift.match(
    /static let recommendationTimeout: TimeInterval = (\d+(?:\.\d+)?)/,
  );
  if (!match) throw new Error("GeminiService.recommendationTimeout not found");
  return Number(match[1]) * 1_000;
})();
/** Cold start, gateway, TLS and transfer time the handler's clock cannot see. */
const UNSEEN_OVERHEAD_MS = 5_000;

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Millisecond-scale budget so the slow-path tests run quickly. */
const testBudget = {
  generationDeadlineMs: 300,
  minimumGenerationMs: 60,
  precheckTimeoutMs: 100,
  refundTimeoutMs: 100,
};
const testWorstCaseMs = testBudget.generationDeadlineMs -
  testBudget.minimumGenerationMs + testBudget.precheckTimeoutMs +
  testBudget.refundTimeoutMs;
/** Timer jitter allowance for wall-clock assertions. */
const SLACK_MS = 40;

interface Ledger {
  consumed: number;
  quotaBilled: number;
  refunds: number;
  refundTimeouts: (number | undefined)[];
  generationStarts: number[];
  generationAborted: boolean;
}

function fakes(options: {
  precheckDelayMs?: number;
  authMs?: number;
  accessMs?: number;
  quotaMs?: number;
  generationMs?: number;
  ignoreAbort?: boolean;
}) {
  const ledger: Ledger = {
    consumed: 0,
    quotaBilled: 0,
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
      await delay(options.authMs ?? precheck);
      return { id: "user-1", isAnonymous: true };
    },
    consumeAccess: async () => {
      await delay(options.accessMs ?? precheck);
      ledger.consumed += 1;
      return "free" as const;
    },
    consumeQuota: async () => {
      await delay(options.quotaMs ?? precheck);
      ledger.quotaBilled += 1;
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
  const { generationDeadlineMs, minimumGenerationMs, precheckTimeoutMs } =
    RECOMMENDATIONS_BUDGET;
  // Three bounded checks can never by themselves outlast the deadline, and a
  // started Gemini call always gets at least the minimum window.
  assert(3 * precheckTimeoutMs < generationDeadlineMs);
  assert(minimumGenerationMs > 0);
  assertEquals(RECOMMENDATIONS_SUCCESS_DEADLINE_MS, 20_000);
  assertEquals(RECOMMENDATIONS_WORST_CASE_MS, 26_000);
  // A charged success leaves the client room for unseen overhead...
  assert(
    CLIENT_TIMEOUT_MS - RECOMMENDATIONS_SUCCESS_DEADLINE_MS >=
      2 * UNSEEN_OVERHEAD_MS,
  );
  // ...and even the slowest refunded failure normally reaches the client.
  assert(CLIENT_TIMEOUT_MS > RECOMMENDATIONS_WORST_CASE_MS);
});

Deno.test("a fast request returns results and keeps the discovery spent", async () => {
  const { ledger, dependencies } = fakes({ generationMs: 10 });
  const { response, body } = await run(dependencies);
  assertEquals(response.status, 200);
  assertEquals(body.recommendations[0].name, "Tartine");
  assertEquals(ledger.consumed, 1);
  assertEquals(ledger.quotaBilled, 1);
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

Deno.test("a slow auth check that uses up the window never charges", async () => {
  // Auth alone leaves 300 - 250 = 50 ms, under the 60 ms minimum window.
  const { ledger, dependencies } = fakes({ authMs: 250, generationMs: 10 });
  const { response, body, elapsedMs } = await run(dependencies);
  assertEquals(response.status, 504);
  assertEquals(body.code, "UPSTREAM_TIMEOUT");
  assertEquals(ledger.consumed, 0, "No discovery reserved");
  assertEquals(ledger.quotaBilled, 0, "No paid-API quota billed");
  assertEquals(ledger.refunds, 0, "Nothing to refund, so nothing can be lost");
  assertEquals(ledger.generationStarts.length, 0);
  assert(elapsedMs < testBudget.generationDeadlineMs, `${elapsedMs} ms`);
});

Deno.test("a slow access check refunds without billing the paid-API quota", async () => {
  const { ledger, dependencies } = fakes({ accessMs: 260, generationMs: 10 });
  const { response } = await run(dependencies);
  assertEquals(response.status, 504);
  assertEquals(ledger.consumed, 1);
  assertEquals(ledger.quotaBilled, 0);
  assertEquals(ledger.refunds, 1);
  assertEquals(ledger.generationStarts.length, 0);
});

for (
  const [name, slow] of [
    ["auth", { authMs: 230 }],
    ["access", { accessMs: 230 }],
    ["quota", { quotaMs: 230 }],
    ["every", { precheckDelayMs: 95 }],
  ] as const
) {
  Deno.test(`slow ${name} pre-check: response stays inside the full-path budget`, async () => {
    const { ledger, dependencies } = fakes({
      ...slow,
      generationMs: 1_000,
      ignoreAbort: true,
    });
    const { response, elapsedMs } = await run(dependencies);
    assertEquals(response.status, 504);
    assertEquals(
      ledger.refunds,
      ledger.consumed,
      "Every reserved discovery is refunded",
    );
    assert(elapsedMs <= testWorstCaseMs + SLACK_MS, `${elapsedMs} ms`);
    await delay(1_000);
  });
}

Deno.test("a success is only ever sent before the generation deadline", async () => {
  for (const generationMs of [50, 150, 230, 290, 320]) {
    const { ledger, dependencies } = fakes({
      precheckDelayMs: 10,
      generationMs,
    });
    const { response, elapsedMs } = await run(dependencies);
    if (response.status === 200) {
      assert(
        elapsedMs <= testBudget.generationDeadlineMs + SLACK_MS,
        `Charged success after ${elapsedMs} ms`,
      );
      assertEquals(ledger.refunds, 0);
    } else {
      assertEquals(response.status, 504);
      assertEquals(ledger.refunds, 1);
    }
  }
});

/** Fake fetch that only settles when its abort signal fires. */
function hangingFetch(): typeof fetch {
  return (_input, init) =>
    new Promise((_, reject) => {
      const signal = init?.signal;
      if (!signal) return; // A missing timeout would hang the test, failing it.
      signal.addEventListener("abort", () => reject(signal.reason));
    });
}

Deno.test("the real refund gives up at the handler's refund timeout", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = hangingFetch();
  try {
    const startedAt = performance.now();
    const refunded = await refundDiscoveryAccess("user-1", "free", null, 80);
    const elapsedMs = performance.now() - startedAt;
    assertEquals(refunded, false);
    assert(elapsedMs < 80 + SLACK_MS * 5, `${elapsedMs} ms`);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("the real pre-checks give up at their fetch timeout", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = hangingFetch();
  const settle = async (work: () => Promise<unknown>) => {
    const startedAt = performance.now();
    await work().then(() => {}, () => {});
    return performance.now() - startedAt;
  };
  try {
    const durations = await Promise.all([
      settle(() =>
        requireAuthenticatedUser(
          new Request("https://local.invalid", {
            headers: { Authorization: "Bearer test" },
          }),
        )
      ),
      settle(() => consumeDiscoveryAccess("user-1", null)),
      settle(() =>
        consumePaidAPIQuota(
          "user-1",
          quotaPolicy("recommendations", "TEST_ONLY", 5, 30, 1_000),
        )
      ),
    ]);
    for (const elapsedMs of durations) {
      assert(
        elapsedMs <= RECOMMENDATIONS_BUDGET.precheckTimeoutMs + 500,
        `A pre-check took ${elapsedMs} ms`,
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});
