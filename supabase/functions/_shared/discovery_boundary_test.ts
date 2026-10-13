import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleRecommendations } from "../recommendations/handler.ts";
import { handleEnrichment } from "../enrich/handler.ts";
import { handleTikTokSearch } from "../tiktok-search/handler.ts";
import { handleTikTokLocations } from "../tiktok-locations/handler.ts";

const legacyRoutes = [
  { handler: handleRecommendations, input: { prompt: "Dinner in LA" } },
  { handler: handleEnrichment, input: { recommendations: [{ name: "Cafe" }] } },
  { handler: handleTikTokSearch, input: { query: "cafe in LA" } },
  { handler: handleTikTokLocations, input: { videos: [{ videoId: "101" }] } },
];

async function withoutExternalCalls(
  run: (fetchCount: () => number) => Promise<void>,
) {
  const environment = {
    BILU_COMMERCE_ENABLED: "true",
    GEMINI_API_KEY: "local-test-no-provider-call",
    GOOGLE_PLACES_API_KEY: "local-test-no-provider-call",
    APIFY_API_KEY: "local-test-no-provider-call",
  };
  const oldValues = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries(environment)) {
    oldValues.set(key, Deno.env.get(key));
    Deno.env.set(key, value);
  }
  const originalFetch = globalThis.fetch;
  let fetchCount = 0;
  globalThis.fetch = () => {
    fetchCount++;
    return Promise.reject(
      new Error("External calls are forbidden by this test"),
    );
  };
  try {
    await run(() => fetchCount);
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of oldValues) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

Deno.test("commerce rejects every legacy provider route before auth, quota or paid calls", async () => {
  await withoutExternalCalls(async (fetchCount) => {
    for (const { handler, input } of legacyRoutes) {
      const response = await handler(
        new Request("https://local.invalid/legacy", {
          method: "POST",
          headers: { Authorization: "Bearer client-controlled" },
          body: JSON.stringify(input),
        }),
      );
      assertEquals(response.status, 426);
      assertEquals((await response.json()).code, "DISCOVERY_UPDATE_REQUIRED");
    }
    assertEquals(fetchCount(), 0);
  });
});

Deno.test("client-supplied execution identity cannot impersonate server orchestration", async () => {
  await withoutExternalCalls(async (fetchCount) => {
    for (const { handler, input } of legacyRoutes) {
      const response = await handler(
        new Request("https://local.invalid/legacy", {
          method: "POST",
          headers: {
            "x-discovery-execution": "true",
            "x-wallet-authorized": "true",
          },
          body: JSON.stringify({
            ...input,
            execution: {
              user: {
                id: "11111111-1111-4111-8111-111111111111",
                isAnonymous: false,
              },
            },
          }),
        }),
      );
      assertEquals(response.status, 426);
    }
    assertEquals(fetchCount(), 0);
  });
});

Deno.test("provider preflight and unsupported methods do not start billable work", async () => {
  await withoutExternalCalls(async (fetchCount) => {
    for (const { handler } of legacyRoutes) {
      assertEquals(
        (await handler(
          new Request("https://local.invalid/legacy", { method: "OPTIONS" }),
        )).status,
        200,
      );
      assertEquals(
        (await handler(
          new Request("https://local.invalid/legacy", { method: "GET" }),
        )).status,
        405,
      );
    }
    assertEquals(fetchCount(), 0);
  });
});
