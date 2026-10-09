# AdMob release setup

The app is configured with Bilu's production AdMob app and rewarded ad-unit
IDs. The production identifiers are:

- App: `ca-app-pub-2845173126212624~6002912892`
- Rewarded unit: `ca-app-pub-2845173126212624/6016275205`

Before archiving a release:

1. Confirm `GADApplicationIdentifier` and `BILURewardedAdUnitIdentifier` in
   `bilu/Info.plist` still match the production IDs above.
2. Apply `supabase/migrations/20260918000000_rewarded_discovery_access.sql`
   and `supabase/migrations/20260923000000_refund_discovery_access.sql`.
3. Set the Edge Function secret `ADMOB_REWARDED_AD_UNIT_ID` to the production
   rewarded ad-unit ID. The function accepts the full SDK identifier and
   compares its numeric suffix with AdMob's SSV `ad_unit` callback parameter.
4. Deploy `rewarded-access` with JWT verification disabled because Google's SSV
   callback is an unauthenticated signed GET. POST actions still validate the
   user's Supabase JWT inside the function:

   `supabase functions deploy rewarded-access --no-verify-jwt`

5. Deploy `recommendations`, then configure the rewarded ad unit's SSV callback:

   `https://yysxjtexwlnvoptxcxlp.supabase.co/functions/v1/rewarded-access`

6. Use AdMob's SSV testing tool to verify the signed callback endpoint, then
   confirm a real TestFlight rewarded ad verifies a session before submitting
   the release. Never ship Google's sample IDs.
7. Update App Store Connect's App Privacy answers for the data declared by the
   embedded Google Mobile Ads SDK (including identifiers, advertising data,
   usage data, diagnostics, and coarse location where applicable).

The EU and US-state messages are published in AdMob and use the hosted Bilu
privacy-policy URL. The app requests consent with Google's User Messaging
Platform before starting the ads SDK. It requests non-personalized ads, disables
Google's publisher first-party ID, does not request App Tracking Transparency
permission, and does not use interrupting interstitial, banner, or app-open ads.

App Store Connect's published App Privacy details include Device ID and
Advertising Data for third-party advertising, developer advertising/marketing,
and analytics. Both are disclosed as linked to the user but not used for
tracking, matching Bilu's non-personalized ad requests and lack of ATT-based
tracking.
