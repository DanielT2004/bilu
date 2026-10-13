import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  fulfillDiscovery,
  fulfillmentDependencies,
} from "./discovery_fulfillment.ts";
import { PaidAPIAccessError } from "./paid_api_guard.ts";

const execution = {
  user: { id: "11111111-1111-4111-8111-111111111111", isAnonymous: false },
};
const unexpected = (): Promise<Response> => {
  throw new Error("Unnecessary paid provider work");
};
const dependencies: typeof fulfillmentDependencies = {
  recommendations: unexpected,
  enrichment: unexpected,
  tiktokSearch: unexpected,
  tiktokLocations: unexpected,
};
const videoResponse = () =>
  Response.json([{
    search_item_list: [{
      aweme_info: {
        aweme_id: "123",
        author: { nickname: "Food scout" },
        video: { play_addr: { url_list: ["https://cdn.example/video.mp4"] } },
        desc: "A restaurant in San Diego",
      },
    }],
  }]);

Deno.test("empty Explore generation spends no Places request and has no billable result", async () => {
  const result = await fulfillDiscovery(
    "explore",
    { prompt: "Dinner" },
    execution,
    {
      ...dependencies,
      recommendations: async () => Response.json({ recommendations: [] }),
    },
  );
  assertEquals(result.usable, false);
  assertEquals(result.result.recommendations, []);
});

Deno.test("Explore fulfillment preserves location and bills only verified open results", async () => {
  const open = { name: "Open Cafe", isOpen: true, placeId: "verified" };
  const result = await fulfillDiscovery(
    "explore",
    {
      prompt: "Dinner",
      location: "San Diego",
      latitude: 32.72,
      longitude: -117.16,
    },
    execution,
    {
      ...dependencies,
      recommendations: async (_request, context) => {
        assertEquals(context, execution);
        return Response.json({
          recommendations: [{ name: "Open Cafe" }],
          relaxed: true,
        });
      },
      enrichment: async (request, context) => {
        assertEquals(context, execution);
        const body = await request.json();
        assertEquals([body.location, body.latitude, body.longitude], [
          "San Diego",
          32.72,
          -117.16,
        ]);
        return Response.json({
          recommendations: [open, { name: "Closed", isOpen: false }, {
            name: "Unknown",
            isOpen: null,
          }],
        });
      },
    },
  );
  assertEquals(result.usable, true);
  assertEquals(result.result.recommendations, [open]);
  assertEquals(result.result.relaxed, true);
});

Deno.test("unverified Explore suggestions do not consume a discovery", async () => {
  const result = await fulfillDiscovery(
    "explore",
    { prompt: "Dinner" },
    execution,
    {
      ...dependencies,
      recommendations: async () =>
        Response.json({ recommendations: [{ name: "Unverified" }] }),
      enrichment: async () =>
        Response.json({
          recommendations: [{ name: "Unverified", isOpen: null }],
        }),
    },
  );
  assertEquals(result.usable, false);
});

Deno.test("empty TikTok scrape skips paid extraction", async () => {
  const result = await fulfillDiscovery(
    "tiktok",
    { query: "San Diego food" },
    execution,
    {
      ...dependencies,
      tiktokSearch: async () => Response.json([]),
    },
  );
  assertEquals(result, {
    usable: false,
    result: { videos: [], locations: [], unresolved: [] },
  });
});

Deno.test("TikTok videos without a verified venue remain useful media but do not consume a discovery", async () => {
  const result = await fulfillDiscovery(
    "tiktok",
    { query: "San Diego food" },
    execution,
    {
      ...dependencies,
      tiktokSearch: async () => videoResponse(),
      tiktokLocations: async (request, context) => {
        assertEquals(context, execution);
        const body = await request.json();
        assertEquals(body.searchQuery, "San Diego food");
        assertEquals(body.videos[0].videoId, "123");
        return Response.json({ locations: [], unresolved: ["123"] });
      },
    },
  );
  assertEquals(result.usable, false);
  assertEquals((result.result.videos as unknown[]).length, 1);
});

Deno.test("TikTok fulfillment requests only the bounded discovery video set", async () => {
  await fulfillDiscovery(
    "tiktok",
    { query: "San Diego food" },
    execution,
    {
      ...dependencies,
      tiktokSearch: async (request) => {
        assertEquals((await request.json()).maxResults, 12);
        return videoResponse();
      },
      tiktokLocations: async () =>
        Response.json({ locations: [], unresolved: ["123"] }),
    },
  );
});

Deno.test("a final TikTok venue satisfies fulfillment but provider errors cannot masquerade as success", async () => {
  const venue = { placeId: "verified", name: "Cafe" };
  const result = await fulfillDiscovery(
    "tiktok",
    { query: "San Diego food" },
    execution,
    {
      ...dependencies,
      tiktokSearch: async () => videoResponse(),
      tiktokLocations: async () =>
        Response.json({ locations: [venue], unresolved: [] }),
    },
  );
  assertEquals(result.usable, true);
  assertEquals(result.result.locations, [venue]);
  await assertRejects(
    () =>
      fulfillDiscovery("tiktok", { query: "San Diego food" }, execution, {
        ...dependencies,
        tiktokSearch: async () => videoResponse(),
        tiktokLocations: async () =>
          Response.json({ error: "provider unavailable" }, { status: 503 }),
      }),
    PaidAPIAccessError,
  );
});
