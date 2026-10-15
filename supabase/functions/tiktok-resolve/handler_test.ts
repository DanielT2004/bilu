import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  expandShortLink,
  fetchSharedVideo,
  handleTikTokResolve,
  parseTikTokURL,
  type ResolveDependencies,
} from "./handler.ts";
import type {
  LocatePlacesInput,
  LocatePlacesResult,
} from "../_shared/tiktok_places.ts";
import { PaidAPIAccessError } from "../_shared/paid_api_guard.ts";

const VIDEO_URL = "https://www.tiktok.com/@foodscout/video/7312345678901234567";
const OEMBED_BODY = {
  title: "best birria in LA 📍Teddy's Red Tacos, Venice #tacos",
  author_name: "Food Scout",
  thumbnail_url: "https://p16.tiktokcdn.com/thumb.jpg",
  html:
    `<blockquote class="tiktok-embed" cite="${VIDEO_URL}" data-video-id="7312345678901234567"></blockquote>`,
};
const PLACE = {
  placeId: "ChIJteddys",
  placeName: "Teddy's Red Tacos",
  address: "Venice, CA",
  lat: 33.99,
  lng: -118.47,
  rank: 0,
  totalViews: 0,
  videoIds: ["7312345678901234567"],
  videoCount: 1,
  rating: 4.6,
  isOpen: true,
  neighborhood: "Venice",
  score: 1.2,
};

type Fetch = typeof fetch;

function oembedFetch(
  status = 200,
  body: unknown = OEMBED_BODY,
  calls: string[] = [],
): Fetch {
  return (input) => {
    const url = String(input);
    calls.push(url);
    if (url.startsWith("https://www.tiktok.com/oembed")) {
      return Promise.resolve(
        new Response(JSON.stringify(body), { status }),
      );
    }
    if (url.startsWith("https://vm.tiktok.com/")) {
      return Promise.resolve(
        new Response(null, { status: 301, headers: { location: VIDEO_URL } }),
      );
    }
    return Promise.reject(new Error(`unexpected fetch ${url}`));
  };
}

function deps(
  overrides: Partial<ResolveDependencies> = {},
  log: {
    quota: number;
    auth: number;
    locate: LocatePlacesInput[];
    fetches: string[];
  } = { quota: 0, auth: 0, locate: [], fetches: [] },
  result: LocatePlacesResult = {
    kind: "ok",
    locations: [PLACE],
    unresolved: [],
    queryCity: "Los Angeles",
  },
): ResolveDependencies {
  return {
    authenticate: () => {
      log.auth++;
      return Promise.resolve({ id: "user-1", isAnonymous: true });
    },
    consumeQuota: () => {
      log.quota++;
      return Promise.resolve({
        allowed: true,
        retryAfterSeconds: 0,
        minuteRemaining: 4,
        dailyRemaining: 29,
        globalDailyRemaining: 1999,
      });
    },
    fetch: oembedFetch(200, OEMBED_BODY, log.fetches),
    locate: (input) => {
      log.locate.push(input);
      return Promise.resolve(result);
    },
    env: (name) => ({ GEMINI_API_KEY: "g", GOOGLE_PLACES_API_KEY: "p" })[name],
    ...overrides,
  };
}

/** Runs `run` with console output captured instead of printed. */
async function captureConsole<T>(
  run: () => Promise<T>,
): Promise<{ lines: string[]; result: T }> {
  const lines: string[] = [];
  const methods = ["log", "info", "warn", "error", "debug"] as const;
  const originals = methods.map((m) => console[m]);
  for (const m of methods) {
    console[m] = (...args: unknown[]) => {
      lines.push(
        args.map((a) => typeof a === "string" ? a : String(a)).join(" "),
      );
    };
  }
  try {
    return { lines, result: await run() };
  } finally {
    methods.forEach((m, i) => (console[m] = originals[i]));
  }
}

function post(body: unknown): Request {
  return new Request("https://local.test/tiktok-resolve", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("share links are accepted only for TikTok over HTTPS", () => {
  for (
    const ok of [
      VIDEO_URL,
      "https://vm.tiktok.com/ZMabc123/",
      "https://vt.tiktok.com/ZSabc123/",
      "https://m.tiktok.com/v/7312345678901234567.html",
    ]
  ) {
    assertEquals(parseTikTokURL(ok)?.hostname !== undefined, true, ok);
  }
  for (
    const bad of [
      "http://www.tiktok.com/@a/video/1234567",
      "https://tiktok.com.attacker.example/@a/video/1234567",
      "https://www.tiktok.com@127.0.0.1/@a/video/1234567",
      "https://www.tiktok.com:8443/@a/video/1234567",
      "https://127.0.0.1/",
      "file:///etc/passwd",
      "not a url",
      42,
      null,
    ]
  ) {
    assertEquals(parseTikTokURL(bad), null, String(bad));
  }
});

Deno.test("short links expand only to TikTok hosts", async () => {
  const expanded = await expandShortLink(
    new URL("https://vm.tiktok.com/ZMabc123/"),
    oembedFetch(),
  );
  assertEquals(expanded?.toString(), VIDEO_URL);

  const offsite: Fetch = () =>
    Promise.resolve(
      new Response(null, {
        status: 302,
        headers: { location: "https://attacker.example/" },
      }),
    );
  assertEquals(
    await expandShortLink(new URL("https://vm.tiktok.com/x/"), offsite),
    null,
  );

  const loop: Fetch = () =>
    Promise.resolve(
      new Response(null, {
        status: 302,
        headers: { location: "https://vm.tiktok.com/again/" },
      }),
    );
  assertEquals(
    await expandShortLink(new URL("https://vm.tiktok.com/x/"), loop),
    null,
  );

  const canonical = new URL(VIDEO_URL);
  assertEquals(
    await expandShortLink(canonical, () => Promise.reject(new Error("no"))),
    canonical,
  );
});

Deno.test("oEmbed caption and video id are read from the embed", async () => {
  const video = await fetchSharedVideo(new URL(VIDEO_URL), oembedFetch());
  assertEquals(video?.videoId, "7312345678901234567");
  assertEquals(video?.caption, OEMBED_BODY.title);
  assertEquals(video?.canonicalUrl, VIDEO_URL);
  assertEquals(video?.authorName, "Food Scout");

  const noHtml = await fetchSharedVideo(
    new URL(VIDEO_URL),
    oembedFetch(200, { title: "caption only" }),
  );
  assertEquals(noHtml?.videoId, "7312345678901234567");

  assertEquals(
    await fetchSharedVideo(new URL(VIDEO_URL), oembedFetch(404, {})),
    null,
  );
});

Deno.test("a resolved share returns its places and spends one quota unit", async () => {
  const log = {
    quota: 0,
    auth: 0,
    locate: [] as LocatePlacesInput[],
    fetches: [] as string[],
  };
  const res = await handleTikTokResolve(
    post({
      shareUrl: "https://vm.tiktok.com/ZMabc123/",
      city: "Los Angeles",
      latitude: 34.05,
      longitude: -118.24,
    }),
    deps({}, log),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.places[0].placeName, "Teddy's Red Tacos");
  assertEquals(body.video.videoId, "7312345678901234567");
  assertEquals(body.queryCity, "Los Angeles");
  assertEquals(log.quota, 1);
  assertEquals(log.locate.length, 1);
  assertEquals(log.locate[0].searchQuery, "food in Los Angeles");
  assertEquals(log.locate[0].queryCity, "Los Angeles");
  assertEquals(log.locate[0].videos[0].desc, OEMBED_BODY.title);
  assertEquals(log.locate[0].latitude, 34.05);
  assertEquals(res.headers.get("X-Daily-Budget-Remaining"), "29");
});

Deno.test("a non-TikTok link is refused before auth, quota or any fetch", async () => {
  const log = {
    quota: 0,
    auth: 0,
    locate: [] as LocatePlacesInput[],
    fetches: [] as string[],
  };
  const res = await handleTikTokResolve(
    post({ shareUrl: "https://attacker.example/x", city: "LA" }),
    deps({}, log),
  );
  assertEquals(res.status, 400);
  assertEquals((await res.json()).error, "invalid_share_url");
  assertEquals([log.auth, log.quota, log.fetches.length], [0, 0, 0]);
});

Deno.test("a private or deleted video does not spend quota", async () => {
  const log = {
    quota: 0,
    auth: 0,
    locate: [] as LocatePlacesInput[],
    fetches: [] as string[],
  };
  const res = await handleTikTokResolve(
    post({ shareUrl: VIDEO_URL, city: "Los Angeles" }),
    deps({ fetch: oembedFetch(404, {}) }, log),
  );
  assertEquals(res.status, 422);
  assertEquals((await res.json()).error, "video_unavailable");
  assertEquals(log.quota, 0);
  assertEquals(log.locate.length, 0);
});

Deno.test("no city returns missing_city with the video before any paid work", async () => {
  const log = {
    quota: 0,
    auth: 0,
    locate: [] as LocatePlacesInput[],
    fetches: [] as string[],
  };
  const res = await handleTikTokResolve(
    post({ shareUrl: VIDEO_URL }),
    deps({}, log),
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.error, "missing_city");
  assertEquals(body.video.videoId, "7312345678901234567");
  assertEquals(log.quota, 0);
  assertEquals(log.locate.length, 0);
});

Deno.test("a supplied city is authoritative: no charged missing_city", async () => {
  const log = {
    quota: 0,
    auth: 0,
    locate: [] as LocatePlacesInput[],
    fetches: [] as string[],
  };
  const res = await handleTikTokResolve(
    post({ shareUrl: VIDEO_URL, city: "  Nowhere  " }),
    deps({}, log, { kind: "missing_city" }),
  );
  // The pipeline gets the city as its query city, and even if it still
  // reports missing_city the user sees "no place found", not "choose a city".
  assertEquals(log.locate[0].queryCity, "Nowhere");
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.places, []);
  assertEquals(body.queryCity, "Nowhere");
  assertEquals(body.video.videoId, "7312345678901234567");
  assertEquals(log.quota, 1);
});

Deno.test("a pipeline failure after the quota unit is spent says charged", async () => {
  const log = {
    quota: 0,
    auth: 0,
    locate: [] as LocatePlacesInput[],
    fetches: [] as string[],
  };
  const secret = "upstream said: Teddy's Red Tacos near 123 Secret St";
  const { lines, result: res } = await captureConsole(() =>
    handleTikTokResolve(
      post({ shareUrl: VIDEO_URL, city: "Los Angeles" }),
      deps({ locate: () => Promise.reject(new Error(secret)) }, log),
    )
  );
  assertEquals(res.status, 502);
  const body = await res.json();
  assertEquals(body.error, "place_lookup_failed");
  assertEquals(body.charged, true);
  assertEquals(log.quota, 1);
  assertEquals(lines.length, 1);
  assertEquals(JSON.parse(lines[0]), {
    event: "tiktok_resolve_failed",
    charged: true,
    errorName: "Error",
  });
  for (const line of lines) {
    assertEquals(line.includes("Secret"), false, line);
    assertEquals(line.includes("Teddy"), false, line);
  }
});

Deno.test("a failure before the quota unit is spent says not charged", async () => {
  const log = {
    quota: 0,
    auth: 0,
    locate: [] as LocatePlacesInput[],
    fetches: [] as string[],
  };
  const { lines, result: res } = await captureConsole(() =>
    handleTikTokResolve(
      post({ shareUrl: VIDEO_URL, city: "Los Angeles" }),
      deps({
        fetch: () => Promise.reject(new TypeError("dns fail for secret.host")),
      }, log),
    )
  );
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, "resolve_failed");
  assertEquals(body.charged, false);
  assertEquals(log.quota, 0);
  assertEquals(lines.some((l) => l.includes("secret.host")), false);
  assertEquals(JSON.parse(lines[0]).errorName, "TypeError");
});

Deno.test("quota and auth refusals pass through as their own status", async () => {
  const limited = await handleTikTokResolve(
    post({ shareUrl: VIDEO_URL, city: "Los Angeles" }),
    deps({
      consumeQuota: () =>
        Promise.reject(
          new PaidAPIAccessError(429, "RATE_LIMITED", "Slow down", 30),
        ),
    }),
  );
  assertEquals(limited.status, 429);

  const unauthenticated = await handleTikTokResolve(
    post({ shareUrl: VIDEO_URL, city: "Los Angeles" }),
    deps({
      authenticate: () =>
        Promise.reject(
          new PaidAPIAccessError(401, "UNAUTHENTICATED", "Sign in"),
        ),
    }),
  );
  assertEquals(unauthenticated.status, 401);
});

Deno.test("missing server keys fail closed", async () => {
  const res = await handleTikTokResolve(
    post({ shareUrl: VIDEO_URL, city: "Los Angeles" }),
    deps({ env: () => undefined }),
  );
  assertEquals(res.status, 500);
});
