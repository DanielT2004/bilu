import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { handleEnrichment } from "./handler.ts";

/** Fakes Supabase and Google Places; no request leaves the process. */
async function enrichWithPlaces(placeDetails: () => Response) {
  const previousKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
  const previousCommerce = Deno.env.get("BILU_COMMERCE_ENABLED");
  Deno.env.set("GOOGLE_PLACES_API_KEY", "local-test-no-provider-call");
  Deno.env.delete("BILU_COMMERCE_ENABLED");
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (input: string | URL | Request) => {
    const url = String(input instanceof Request ? input.url : input);
    if (url.includes("rpc/consume_paid_api_quota")) {
      return Promise.resolve(
        Response.json([{
          allowed: true,
          retry_after_seconds: 0,
          minute_remaining: 20,
          daily_remaining: 100,
          global_daily_remaining: 4_000,
        }]),
      );
    }
    if (url.startsWith("https://places.googleapis.com/v1/places/")) {
      return Promise.resolve(placeDetails());
    }
    // Cache reads and writes fail; enrichment must tolerate that.
    return Promise.resolve(new Response("unavailable", { status: 503 }));
  };
  try {
    const response = await handleEnrichment(
      new Request("https://local.invalid/enrich", {
        method: "POST",
        body: JSON.stringify({
          recommendations: [{
            name: "Tartine",
            dish: "Croissant",
            image: "",
            explanation: "Flaky",
            mapsUrl: "",
          }],
          groundingPlaces: [{ placeId: "abc", title: "Tartine", uri: "" }],
        }),
      }),
      { user: { id: "user-1", isAnonymous: true } },
    );
    return { status: response.status, body: await response.json() };
  } finally {
    globalThis.fetch = originalFetch;
    if (previousKey === undefined) Deno.env.delete("GOOGLE_PLACES_API_KEY");
    else Deno.env.set("GOOGLE_PLACES_API_KEY", previousKey);
    if (previousCommerce !== undefined) {
      Deno.env.set("BILU_COMMERCE_ENABLED", previousCommerce);
    }
  }
}

Deno.test("a Places outage is reported as unverified, not as no match", async () => {
  const { status, body } = await enrichWithPlaces(() =>
    new Response("quota", { status: 500 })
  );
  assertEquals(status, 200);
  assertEquals(body.recommendations, []);
  assertEquals(body.unverifiedCount, 1);
});

Deno.test("a confirmed closed place is a genuine no match", async () => {
  const { status, body } = await enrichWithPlaces(() =>
    Response.json({
      displayName: { text: "Tartine" },
      regularOpeningHours: { openNow: false },
    })
  );
  assertEquals(status, 200);
  assertEquals(body.recommendations, []);
  assertEquals(body.unverifiedCount, 0);
});
