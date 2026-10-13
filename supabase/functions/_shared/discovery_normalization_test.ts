import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { normalizedTikTokVideos } from "./discovery_fulfillment.ts";

function post(id = "101", overrides: Record<string, unknown> = {}) {
  return {
    aweme_info: {
      aweme_id: id,
      author: {
        nickname: "Restaurant reviewer",
        unique_id: "food scout",
        avatar_thumb: { url_list: ["https://cdn.example/avatar.jpg"] },
      },
      video: {
        play_addr: { url_list: ["https://cdn.example/video.mp4"] },
        cover: { url_list: ["https://cdn.example/cover.jpg"] },
      },
      statistics: { digg_count: 4, comment_count: 2, play_count: 900 },
      desc: "A cafe in San Diego",
      ...overrides,
    },
  };
}

function withCaption(url: string, extra: Record<string, unknown> = {}) {
  return post("101", {
    video: {
      play_addr: { url_list: ["https://cdn.example/video.mp4"] },
      cla_info: { caption_infos: [{ language_code: "en", url }] },
      ...extra,
    },
  });
}

Deno.test("normalization keeps only the client and extraction contract", () => {
  const payload = [{
    scraper_secret: "must not persist",
    search_item_list: [post("101", {
      private_account_metadata: "must not persist",
      statistics: {
        digg_count: -20,
        comment_count: 8.9,
        play_count: Number.MAX_VALUE,
      },
    })],
  }];
  assertEquals(normalizedTikTokVideos(payload), [{
    videoId: "101",
    shareUrl: "https://www.tiktok.com/@food%20scout/video/101",
    videoUrl: "https://cdn.example/video.mp4",
    thumbnailUrl: "https://cdn.example/cover.jpg",
    author: {
      name: "Restaurant reviewer",
      avatar: "https://cdn.example/avatar.jpg",
    },
    desc: "A cafe in San Diego",
    diggCount: 0,
    commentCount: 8,
    viewCount: Number.MAX_SAFE_INTEGER,
  }]);
});

Deno.test("normalization rejects malformed payloads without creating billable videos", () => {
  for (const input of [null, {}, "page", [null, 12, [], {}]]) {
    assertEquals(normalizedTikTokVideos(input), []);
  }
  assertEquals(
    normalizedTikTokVideos([{
      search_item_list: [
        null,
        {},
        post("not-an-id"),
        post("102", { author: {} }),
        post("103", {
          video: { play_addr: { url_list: ["http://unsafe/video"] } },
        }),
      ],
    }]),
    [],
  );
});

Deno.test("normalization deduplicates across pages and caps paid extraction at twelve videos", () => {
  const result = normalizedTikTokVideos([
    { search_item_list: [post("1"), post("1")] },
    {
      search_item_list: Array.from(
        { length: 30 },
        (_, i) => post(String(i + 1)),
      ),
    },
  ]);
  assertEquals(result.length, 12);
  assertEquals(
    result.map((video) => video.videoId),
    Array.from({ length: 12 }, (_, i) => String(i + 1)),
  );
});

Deno.test("normalization rejects transcript URLs that escape the TikTok CDN allowlist", () => {
  for (
    const url of [
      "http://v.tiktokcdn.com/transcript",
      "https://tiktokcdn.com.attacker.example/transcript",
      "https://tiktokcdn.com@127.0.0.1/transcript",
      "https://127.0.0.1/transcript",
      "https://[::1]/transcript",
      "file:///etc/passwd",
      "not a URL",
    ]
  ) {
    const [video] = normalizedTikTokVideos([{
      search_item_list: [withCaption(url)],
    }]);
    assertEquals(video.transcriptUrl, undefined, url);
  }
  for (
    const domain of [
      "tiktokcdn.com",
      "tiktokcdn-us.com",
      "tiktok.com",
      "byteoversea.com",
    ]
  ) {
    const url = `https://video.${domain}/transcript`;
    const [video] = normalizedTikTokVideos([{
      search_item_list: [withCaption(url)],
    }]);
    assertEquals(video.transcriptUrl, url);
  }
});

Deno.test("normalization prefers English captions and supports missing artwork", () => {
  const [video] = normalizedTikTokVideos([{
    search_item_list: [withCaption("", {
      cla_info: {
        caption_infos: [
          { language_code: "es", url: "https://v.tiktokcdn.com/es" },
          { lang: "eng-US", url_list: ["https://v.tiktokcdn.com/en"] },
        ],
      },
    })],
  }]);
  assertEquals(video.transcriptUrl, "https://v.tiktokcdn.com/en");
  assertEquals(video.thumbnailUrl, "");
});

Deno.test("normalization bounds stored text and invalid numeric values", () => {
  const [video] = normalizedTikTokVideos([{
    search_item_list: [post("101", {
      desc: "a".repeat(5_000),
      statistics: {
        digg_count: NaN,
        comment_count: Infinity,
        play_count: "900",
      },
    })],
  }]);
  assertEquals((video.desc as string).length, 2_000);
  assertEquals([video.diggCount, video.commentCount, video.viewCount], [
    0,
    0,
    0,
  ]);
});
