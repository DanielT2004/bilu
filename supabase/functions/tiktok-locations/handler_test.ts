import { assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { isTrustedTranscriptURL } from "./handler.ts";

Deno.test("transcript fetching accepts only HTTPS TikTok-controlled hosts", () => {
  for (
    const url of [
      "https://v16.tiktokcdn.com/caption.vtt",
      "https://www.tiktok.com/caption.vtt",
      "https://sub.byteoversea.com/caption.vtt",
    ]
  ) {
    assertEquals(isTrustedTranscriptURL(url), true, url);
  }

  for (
    const url of [
      "http://v16.tiktokcdn.com/caption.vtt",
      "https://tiktokcdn.com.attacker.example/caption.vtt",
      "https://tiktokcdn.com@127.0.0.1/caption.vtt",
      "https://127.0.0.1/caption.vtt",
      "file:///etc/passwd",
      "not a URL",
    ]
  ) {
    assertEquals(isTrustedTranscriptURL(url), false, url);
  }
});
