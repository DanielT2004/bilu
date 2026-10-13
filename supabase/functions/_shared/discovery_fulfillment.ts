import { handleRecommendations } from "../recommendations/handler.ts";
import { handleEnrichment } from "../enrich/handler.ts";
import { handleTikTokSearch } from "../tiktok-search/handler.ts";
import { handleTikTokLocations } from "../tiktok-locations/handler.ts";
import { PaidAPIAccessError } from "./paid_api_guard.ts";
import type { DiscoveryExecution } from "./discovery_execution.ts";

type ObjectValue = Record<string, unknown>;
/** Match the downstream extraction cap so one paid TikTok discovery has a
 * predictable maximum amount of scraping, transcript processing, and Places work. */
export const MAX_TIKTOK_DISCOVERY_VIDEOS = 12;
const object = (value: unknown): ObjectValue =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as ObjectValue
    : {};
const array = (value: unknown): unknown[] => Array.isArray(value) ? value : [];
const string = (value: unknown, limit = 2048): string =>
  typeof value === "string" ? value.slice(0, limit) : "";
const number = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value)
    ? Math.min(Number.MAX_SAFE_INTEGER, Math.max(0, Math.floor(value)))
    : 0;
const firstURL = (value: unknown): string => {
  const url = string(array(object(value).url_list)[0]);
  return url.startsWith("https://") ? url : "";
};

/** Keeps only display and extraction fields; never persists an entire scraper response. */
export function normalizedTikTokVideos(payload: unknown): ObjectValue[] {
  const videos: ObjectValue[] = [];
  const seen = new Set<string>();
  for (const page of array(payload)) {
    for (const item of array(object(page).search_item_list)) {
      const post = object(object(item).aweme_info);
      const id = string(post.aweme_id, 64);
      const author = object(post.author);
      const video = object(post.video);
      const stats = object(post.statistics);
      const nickname = string(author.nickname, 200);
      const bitrates = array(video.bit_rate);
      const videoURL =
        firstURL(object(bitrates[bitrates.length - 1]).play_addr) ||
        firstURL(video.play_addr);
      if (!/^\d+$/.test(id) || !nickname || !videoURL || seen.has(id)) continue;
      seen.add(id);
      const captions = array(object(video.cla_info).caption_infos).map(object);
      const caption = captions.find((c) =>
        string(c.language_code).startsWith("en") ||
        string(c.lang).startsWith("en")
      ) ?? captions[0];
      const transcript = string(caption?.url) || firstURL(caption);
      // Only scraper-owned TikTok CDN transcripts are eligible for server retrieval.
      let transcriptURL: string | undefined;
      try {
        const url = new URL(transcript);
        if (
          url.protocol === "https:" &&
          ["tiktokcdn.com", "tiktokcdn-us.com", "tiktok.com", "byteoversea.com"]
            .some((host) =>
              url.hostname === host || url.hostname.endsWith(`.${host}`)
            )
        ) {
          transcriptURL = url.href;
        }
      } catch {
        /* Missing captions are a supported input. */
      }
      const handle = string(author.unique_id, 100);
      videos.push({
        videoId: id,
        shareUrl: handle
          ? `https://www.tiktok.com/@${encodeURIComponent(handle)}/video/${id}`
          : `https://www.tiktok.com/video/${id}`,
        videoUrl: videoURL,
        thumbnailUrl: firstURL(video.cover) || firstURL(video.dynamic_cover),
        author: { name: nickname, avatar: firstURL(author.avatar_thumb) },
        desc: string(post.desc, 2000),
        diggCount: number(stats.digg_count),
        commentCount: number(stats.comment_count),
        viewCount: number(stats.play_count),
        ...(transcriptURL ? { transcriptUrl: transcriptURL } : {}),
      });
      if (videos.length === MAX_TIKTOK_DISCOVERY_VIDEOS) {
        return videos;
      }
    }
  }
  return videos;
}

async function responseJSON(response: Response): Promise<unknown> {
  const payload = await response.json();
  if (!response.ok) {
    const error = object(payload);
    throw new PaidAPIAccessError(
      response.status,
      typeof error.code === "string"
        ? error.code
        : error.error === "missing_city"
        ? "MISSING_CITY"
        : "DISCOVERY_FAILED",
      error.error === "missing_city"
        ? "Please include a city in your search."
        : "This discovery could not finish. Your allowance has been returned.",
    );
  }
  return payload;
}

export interface FulfillmentResult {
  usable: boolean;
  result: ObjectValue;
}

export const fulfillmentDependencies = {
  recommendations: handleRecommendations,
  enrichment: handleEnrichment,
  tiktokSearch: handleTikTokSearch,
  tiktokLocations: handleTikTokLocations,
};

/** Provider input comes only from this server orchestration, not a client completion claim. */
export async function fulfillDiscovery(
  kind: "explore" | "tiktok",
  input: ObjectValue,
  execution: DiscoveryExecution,
  dependencies = fulfillmentDependencies,
): Promise<FulfillmentResult> {
  const request = (body: ObjectValue) =>
    new Request("http://internal/discovery", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  if (kind === "explore") {
    const generated = object(
      await responseJSON(
        await dependencies.recommendations(request(input), execution),
      ),
    );
    const candidates = array(generated.recommendations);
    if (!candidates.length) {
      return {
        usable: false,
        result: { recommendations: [], groundingPlaces: [] },
      };
    }
    const enriched = object(
      await responseJSON(
        await dependencies.enrichment(
          request({
            recommendations: candidates,
            groundingPlaces: array(generated.groundingPlaces),
            location: string(input.location, 300),
            ...(typeof input.latitude === "number"
              ? { latitude: input.latitude }
              : {}),
            ...(typeof input.longitude === "number"
              ? { longitude: input.longitude }
              : {}),
          }),
          execution,
        ),
      ),
    );
    const recommendations = array(enriched.recommendations)
      .filter((rec) => object(rec).isOpen === true);
    return {
      usable: recommendations.length > 0,
      result: {
        recommendations,
        groundingPlaces: array(generated.groundingPlaces),
        relaxed: generated.relaxed === true,
      },
    };
  }

  const raw = await responseJSON(
    await dependencies.tiktokSearch(
      request({
        query: input.query,
        maxResults: MAX_TIKTOK_DISCOVERY_VIDEOS,
        sortType: input.sortType ?? 0,
      }),
      execution,
    ),
  );
  const videos = normalizedTikTokVideos(raw);
  if (!videos.length) {
    return {
      usable: false,
      result: { videos: [], locations: [], unresolved: [] },
    };
  }
  const extracted = object(
    await responseJSON(
      await dependencies.tiktokLocations(
        request({
          videos,
          searchQuery: input.query,
        }),
        execution,
      ),
    ),
  );
  const locations = array(extracted.locations);
  return {
    usable: locations.length > 0,
    result: {
      videos,
      locations,
      unresolved: array(extracted.unresolved),
      queryCity: extracted.queryCity ?? null,
    },
  };
}
