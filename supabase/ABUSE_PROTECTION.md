# Paid API protection

The Supabase project key in the app is public by design. It identifies the
project and can create an Auth session, but it must never be treated as proof of
a user. Paid Edge Functions enforce two separate controls:

1. `requireAuthenticatedUser` validates the bearer token with Supabase Auth and
   rejects the public project key or an expired session.
2. `consume_paid_api_quota` atomically enforces per-user minute and daily
   limits plus a service-wide daily budget before any paid upstream request
   begins. The global budget still applies if an attacker creates new users.

## Required deployment settings

1. Enable Anonymous Sign-Ins in Supabase Auth. The iOS app creates one anonymous
   user per installation and keeps its refresh token in Keychain.
2. Apply `20260914000000_paid_api_quotas.sql` before deploying the functions.
   Quota accounting fails closed when the RPC is unavailable.
3. Keep JWT verification enabled for every paid function. Never deploy
   `recommendations`, `enrich`, `photos`, `tiktok-search`, or
   `tiktok-locations` with `--no-verify-jwt`.
4. Configure anonymous-signup abuse protection in Supabase Auth: retain the IP
   signup rate limit and enable CAPTCHA/Turnstile when the client flow supports
   it. Per-user quotas alone cannot prevent an attacker from creating new users.
5. Keep hard provider budgets and alerts enabled for Gemini, Google Places, and
   Apify. Application quotas reduce exposure but do not replace provider caps.

## Default limits

| Service | User/minute | User/day | Global/day | Unit definition |
| --- | ---: | ---: | ---: | --- |
| Recommendations | 5 | 30 | 1,000 | one search |
| Places enrichment | 25 | 150 | 5,000 | one place enriched |
| Place photos | 40 | 300 | 10,000 | one photo resolved |
| TikTok search | 3 | 20 | 500 | one Apify run |
| TikTok locations | 10 | 40 | 1,000 | `1 + ceil(video count / 5)` |

Override a default with Edge Function secrets named `<PREFIX>_PER_MINUTE`,
`<PREFIX>_PER_DAY`, and `<PREFIX>_GLOBAL_PER_DAY`, where the prefixes are
`RECOMMENDATIONS`, `PLACES_ENRICH`, `PLACE_PHOTOS`, `TIKTOK_SEARCH`, and
`TIKTOK_LOCATIONS`. Set each global value from an explicit monetary budget and
the worst-case observed cost per unit before launch; the checked-in values are
conservative starting points, not a substitute for that calculation.

The response headers `X-RateLimit-Remaining`, `X-Daily-Budget-Remaining`, and
`X-Global-Daily-Budget-Remaining` expose the remaining allowance. A denied
request returns HTTP 429,
`USAGE_LIMIT_EXCEEDED` (user limit) or `GLOBAL_BUDGET_EXCEEDED` (service-wide
budget), plus `Retry-After`, without calling the paid provider.

Old usage buckets can be deleted periodically; they are accounting history and
are not required after the applicable day has ended.
