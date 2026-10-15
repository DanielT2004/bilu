// Owner decision 4: the TikTok search/resolve pipeline logs lengths and counts
// only. These tests run locatePlaces end to end against a stubbed fetch (no
// live Gemini, Places, TikTok or Supabase calls) and assert that nothing the
// user typed, nothing from the video text, and no venue/city name reaches the
// console.
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { locatePlaces, type VideoInput } from "./tiktok_places.ts";

const QUERY = "secret birria spot near my apartment in LA";
const CAPTION = "my private caption about Zorblax Tacos";
const TRANSCRIPT = "you have to try zorblax tacos on my block";
const VENUE = "Zorblax Tacos";
const AREA = "Glimmerwood";
const CITY = "Los Angeles";
const PLACE_ID = "ChIJzorblaxSecretPlaceId123";
const GEMINI_KEY = "gemini-key-should-not-log";
const PLACES_KEY = "places-key-should-not-log";

const SENSITIVE = [
  QUERY,
  CAPTION,
  TRANSCRIPT,
  VENUE,
  VENUE.toLowerCase(),
  AREA,
  CITY,
  PLACE_ID,
  GEMINI_KEY,
  PLACES_KEY,
  "Neighborhoodville",
  "123 Secret St",
];

const VIDEOS: VideoInput[] = [{
  videoId: "7312345678901234567",
  desc: CAPTION,
  viewCount: 1000,
  shareUrl: "https://www.tiktok.com/@a/video/7312345678901234567",
  transcriptUrl: "https://v16.tiktokcdn.com/caption.vtt",
}, {
  videoId: "7312345678901234568",
  desc: `${CAPTION} again`,
  viewCount: 500,
  shareUrl: "https://www.tiktok.com/@a/video/7312345678901234568",
}];

function geminiBody(text: string): Response {
  return new Response(
    JSON.stringify({
      candidates: [{
        content: { role: "model", parts: [{ text }] },
        finishReason: "STOP",
      }],
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}

function stubFetch(geminiText: string): typeof fetch {
  return (input, init) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url.startsWith("https://generativelanguage.googleapis.com/")) {
      return Promise.resolve(geminiBody(geminiText));
    }
    if (url === "https://v16.tiktokcdn.com/caption.vtt") {
      return Promise.resolve(
        new Response(
          `WEBVTT\n\n00:00:00.000 --> 00:00:02.000\n${TRANSCRIPT}\n`,
        ),
      );
    }
    if (url === "https://places.googleapis.com/v1/places:searchText") {
      const { textQuery } = JSON.parse(String(init?.body ?? "{}"));
      const body = textQuery === CITY
        ? { places: [{ location: { latitude: 34.05, longitude: -118.24 } }] }
        : { places: [{ id: `places/${PLACE_ID}` }] };
      return Promise.resolve(new Response(JSON.stringify(body)));
    }
    if (url.startsWith(`https://places.googleapis.com/v1/places/${PLACE_ID}`)) {
      return Promise.resolve(
        new Response(JSON.stringify({
          displayName: { text: VENUE },
          formattedAddress: "123 Secret St, Los Angeles",
          location: { latitude: 34.06, longitude: -118.25 },
          rating: 4.7,
          userRatingCount: 321,
          photos: [{ name: `places/${PLACE_ID}/photos/abc` }],
          addressComponents: [{
            longText: "Neighborhoodville",
            types: ["neighborhood"],
          }],
        })),
      );
    }
    // Supabase cache (SUPABASE_URL is unset in tests): behave as a cache miss.
    if (url.includes("/rest/v1/")) {
      return Promise.resolve(new Response("[]", { status: 200 }));
    }
    return Promise.reject(new Error(`unexpected fetch ${url}`));
  };
}

async function captureLogs(
  geminiText: string,
  run: () => Promise<unknown>,
  fetcher: typeof fetch = stubFetch(geminiText),
): Promise<{ lines: string[]; result: unknown }> {
  const lines: string[] = [];
  const methods = ["log", "info", "warn", "error", "debug"] as const;
  const originals = methods.map((m) => console[m]);
  const originalFetch = globalThis.fetch;
  for (const m of methods) {
    console[m] = (...args: unknown[]) => {
      lines.push(
        args.map((a) =>
          typeof a === "string"
            ? a
            : a instanceof Error
            ? `${a.name}: ${a.message}`
            : JSON.stringify(a)
        ).join(" "),
      );
    };
  }
  globalThis.fetch = fetcher;
  try {
    const result = await run();
    return { lines, result };
  } finally {
    globalThis.fetch = originalFetch;
    methods.forEach((m, i) => (console[m] = originals[i]));
  }
}

function assertNoSensitive(lines: string[]) {
  assert(lines.length > 0, "pipeline should still log counts");
  for (const line of lines) {
    for (const secret of SENSITIVE) {
      assert(
        !line.includes(secret),
        `log line leaks "${secret}": ${line}`,
      );
    }
  }
}

Deno.test({
  name: "locatePlaces logs no query, caption, transcript, venue or city text",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const geminiText = JSON.stringify({
      queryCity: CITY,
      videos: VIDEOS.map((v) => ({
        videoId: v.videoId,
        places: [{ name: VENUE, area: AREA, confidence: "high" }],
      })),
    });
    const { lines, result } = await captureLogs(
      geminiText,
      () =>
        locatePlaces(
          { videos: VIDEOS, searchQuery: QUERY },
          GEMINI_KEY,
          PLACES_KEY,
        ),
    );
    const ok = result as Awaited<ReturnType<typeof locatePlaces>>;
    assertEquals(ok.kind, "ok");
    if (ok.kind === "ok") {
      assertEquals(ok.locations.length, 1);
      assertEquals(ok.locations[0].placeId, PLACE_ID);
    }
    assert(
      lines.some((l) => l.includes(`Query length: ${QUERY.length}`)),
      "query length is logged instead of the query",
    );
    assertNoSensitive(lines);
  },
});

Deno.test({
  name: "locatePlaces parse failure logs the error kind, not the model output",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const { lines, result } = await captureLogs(
      `not json: ${QUERY} ${VENUE} ${CITY}`,
      () =>
        locatePlaces(
          { videos: VIDEOS, searchQuery: QUERY },
          GEMINI_KEY,
          PLACES_KEY,
        ),
    );
    assertEquals(
      (result as Awaited<ReturnType<typeof locatePlaces>>).kind,
      "missing_city",
    );
    assert(
      lines.some((l) => l.includes("Gemini JSON parse failed: SyntaxError")),
      "parse failure keeps its error kind",
    );
    assertNoSensitive(lines);
  },
});

Deno.test({
  name: "a supplied queryCity replaces a missing Gemini city",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    // Gemini omits the city (as it does for "food in <city>" sometimes); the
    // caller's validated city still places the venue.
    const geminiText = JSON.stringify({
      queryCity: null,
      videos: VIDEOS.map((v) => ({
        videoId: v.videoId,
        places: [{ name: VENUE, area: null, confidence: "high" }],
      })),
    });
    const { lines, result } = await captureLogs(
      geminiText,
      () =>
        locatePlaces(
          { videos: VIDEOS, searchQuery: QUERY, queryCity: ` ${CITY} ` },
          GEMINI_KEY,
          PLACES_KEY,
        ),
    );
    const ok = result as Awaited<ReturnType<typeof locatePlaces>>;
    assertEquals(ok.kind, "ok");
    if (ok.kind === "ok") {
      assertEquals(ok.queryCity, CITY);
      assertEquals(ok.locations[0].placeId, PLACE_ID);
    }
    assertNoSensitive(lines);

    // Without the override the same response is still missing_city
    // (tiktok-locations behaviour is unchanged).
    const { result: without } = await captureLogs(
      geminiText,
      () =>
        locatePlaces(
          { videos: VIDEOS, searchQuery: QUERY },
          GEMINI_KEY,
          PLACES_KEY,
        ),
    );
    assertEquals(
      (without as Awaited<ReturnType<typeof locatePlaces>>).kind,
      "missing_city",
    );
  },
});

Deno.test({
  name: "Places HTTP errors log status, error code and length, never the body",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const geminiText = JSON.stringify({
      queryCity: CITY,
      videos: VIDEOS.map((v) => ({
        videoId: v.videoId,
        places: [{ name: VENUE, area: AREA, confidence: "high" }],
      })),
    });
    const base = stubFetch(geminiText);
    // Google echoes the request in its error message.
    const errorBody = JSON.stringify({
      error: {
        code: 400,
        message: `Invalid textQuery "${VENUE} ${AREA} ${CITY}" (${QUERY})`,
        status: "INVALID_ARGUMENT",
      },
    });
    const failingPlaces: typeof fetch = (input, init) => {
      const url = input instanceof Request ? input.url : String(input);
      if (url === "https://places.googleapis.com/v1/places:searchText") {
        return Promise.resolve(new Response(errorBody, { status: 400 }));
      }
      return base(input, init);
    };
    const { lines, result } = await captureLogs(
      geminiText,
      () =>
        locatePlaces(
          { videos: VIDEOS, searchQuery: QUERY },
          GEMINI_KEY,
          PLACES_KEY,
        ),
      failingPlaces,
    );
    const ok = result as Awaited<ReturnType<typeof locatePlaces>>;
    assertEquals(ok.kind, "ok");
    const httpErrors = lines.filter((l) => l.includes("HTTP error"));
    assert(httpErrors.length > 0, "the failure is still logged");
    for (const line of httpErrors) {
      assert(line.includes('"status":400'), line);
      assert(line.includes('"errorStatus":"INVALID_ARGUMENT"'), line);
      assert(line.includes(`"bodyLength":${errorBody.length}`), line);
      assert(!line.includes("Invalid textQuery"), line);
    }
    assertNoSensitive(lines);
  },
});
