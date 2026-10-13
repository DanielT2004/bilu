import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const policy = `BILU PRIVACY POLICY

Effective October 9, 2026

Bilu helps you discover places to eat. This policy explains what information Bilu processes, why it is used, where it goes, and the choices available to you.


INFORMATION PROCESSED

Search and preference information
Your search text, selected occasion, food and atmosphere preferences, dietary preferences, chosen area, and any TikTok link you share with Bilu.

Location
When you grant location permission or choose a nearby-radius search, Bilu processes your approximate current area and may send latitude and longitude with that search. Location is used to return nearby results, not for advertising or tracking.

Service identifiers and usage
Bilu creates a pseudonymous Supabase user identifier and records limited request counts needed to authenticate requests, prevent abuse, enforce spending limits, and keep the service reliable.

Advertising information
When a contextual banner appears while a restaurant discovery loads, or when you choose to watch a rewarded ad, Google Mobile Ads may process device and app information, IP address, advertising identifiers when permitted, consent choices, ad interactions, and diagnostics to select, deliver, measure, and prevent fraud in advertising. For voluntary rewarded ads only, Bilu sends a pseudonymous one-time reward token and service identifier for server-side reward verification. Loading-screen banners do not unlock discoveries. Bilu does not send your restaurant search, dietary preferences, or precise GPS coordinates to Google Mobile Ads for ad selection.

Optional diagnostics
Only if you enable “Share Diagnostics,” Bilu sends Apple MetricKit crash, hang, launch, disk, CPU, memory, network, and performance reports, plus app version, build, and operating-system version. Bilu associates these reports with the pseudonymous service identifier so it can limit abuse and investigate reliability problems.

The same optional setting enables limited discovery and advertising diagnostics: discovery starts, completions, failures, cancellations, time spent loading, results-screen arrival, backgrounding, banner requests, impressions, clicks, numeric error codes, and SDK-reported ad revenue with currency and precision. A fresh random identifier joins events within one discovery; these event records do not contain your account identifier, search text, food preferences, location, reward token, or advertising identifier. Authentication is used separately to limit ingestion abuse. Bilu aggregates these events to compare loading time, result arrival, and abandonment across experiences with and without a recorded banner impression. These optional diagnostics are separate from Google's advertising processing and consent choices.

Information kept on your device
Your profile, dietary settings, saved places and vibes, visited-place state, cached images, and pending shared links are stored locally or in Bilu's App Group container.


HOW INFORMATION IS USED

Bilu uses this information to provide restaurant recommendations and place details, localize results, process shared TikTok links, maintain saved preferences, unlock discoveries after rewarded ads, protect paid APIs from abuse, diagnose failures, measure capacity, and improve app performance. Bilu does not sell personal information. Google processes advertising information according to your consent choices and its own privacy terms.


SERVICE PROVIDERS

Search inputs and location context are sent only as needed to providers that operate Bilu's features:

• Supabase provides authentication, Edge Functions, database storage, and operational infrastructure.

• Google Gemini and Google Maps Platform process prompts and location context to generate and verify recommendations, place details, maps data, parking guidance, and photos.

• Google Mobile Ads and Google's User Messaging Platform deliver contextual loading-screen banners and optional rewarded ads, collect applicable privacy choices, measure ads, prevent fraud, and confirm completed rewards.

• Apify and TikTok are used when you search or share TikTok content so public video metadata, captions, and available transcripts can be processed for mentioned places.

• Unsplash may deliver generic fallback food images when a place photo is unavailable.

• Apple Maps or Google Maps receives a place or route query only when you choose to open that maps service.

These providers process information under their own privacy terms. Bilu requires providers handling user information on its behalf to apply protections consistent with this policy and applicable requirements.


RETENTION AND DELETION

• On-device profile and saved data remains until you remove it in Bilu, clear the app's data, or uninstall the app.

• Raw optional diagnostic reports and discovery/ad diagnostic events are automatically deleted from Bilu's active database after 30 days. MetricKit reports waiting for upload remain protected on your device. Discovery/ad events wait only in a bounded memory queue and are lost when the app process ends. Turning diagnostics off removes both pending queues and stops further optional collection.

• Search inputs are processed to answer the request. Limited service and provider logs may be retained temporarily for security, reliability, abuse prevention, and legal obligations under the relevant provider's retention practices.

• Pseudonymous authentication and quota records are retained while needed to operate and protect the service. You may request deletion through the developer Support link on Bilu's App Store listing.


YOUR CHOICES

You can deny or revoke location access in iOS Settings and enter an area manually. Contextual banners may appear during discovery loading, with frequency limits; they do not delay results or grant or consume rewarded discovery credits. An active ad-free Bilu Pro entitlement suppresses advertising. Rewarded ads remain optional and require an explicit choice to watch; Bilu does not automatically launch rewarded videos or show interrupting interstitial ads. Where required, you can review or change advertising consent under Bilu's Profile → Privacy → Ad privacy choices. Optional diagnostics are off by default; you can enable or disable them at any time under Bilu's Profile → Privacy section. Turning them off stops future collection and removes queued reports from your device. You can remove saved items inside Bilu and request deletion of server-side information through the developer Support link on the App Store listing.


CHILDREN

Bilu is not directed to children under 13 and does not knowingly collect personal information from children under 13.


CHANGES

This policy may be updated when Bilu's features or data practices change. The effective date above identifies the latest version.
`;

serve((request: Request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { "Allow": "GET, HEAD" },
    });
  }

  return new Response(request.method === "HEAD" ? null : policy, {
    status: 200,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
      "Content-Security-Policy":
        "default-src 'none'; base-uri 'none'; frame-ancestors 'none'",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
    },
  });
});
