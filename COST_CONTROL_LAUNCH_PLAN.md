# Bilu cost-control launch plan

**Status: local implementation only — not deployed, not submitted, and not
selling.** This plan pairs the paid-discovery contract with hard technical
limits. It deliberately avoids an “unlimited” subscription promise: every
provider-backed discovery has a bounded cost and an atomic server allowance.

## What is now bounded

| Journey | Guardrail | Why it matters |
| --- | --- | --- |
| Explore | Wallet reserves one unit before provider work; result must be useful before it commits | Failed or empty work returns the allowance instead of charging a user for a bad result. |
| TikTok discovery | At most 12 normalized videos, 8 caption downloads, 11 venue geocodes, and 8 ranked places | Prevents one broad TikTok query from multiplying scraper, model, and Places work. |
| Caption downloads | HTTPS-only TikTok/ByteDance CDN allowlist and redirects rejected | Blocks arbitrary-server fetches and accidental egress. |
| Places enrichment | No fresh `reviews` field | Review text is an Enterprise + Atmosphere field; identity, hours, rating, address, phone, website, and photos remain. Existing cached reviews can still render. Remaining requested fields still determine the final Places SKU. |
| Restaurant detail | Extra photos load only after an explicit tap; TikTok clips only after the Media/Insights path is opened | Browsing a result cannot silently create media/provider work. |
| TikTok sort | A changed sort asks for confirmation before a fresh search; commerce copy states it uses one TikTok discovery | No surprise allowance burn or background paid request. |
| Service capacity | Server daily quotas and global budgets remain authoritative, even for Pro | A valid entitlement never bypasses an operational spend cap. |

The approved entitlement is intentionally finite: **Discovery Pass = 4 Explore
+ 1 TikTok**, **Bilu Pro = 6 Explore + 1 TikTok per anchored service month**.
Free browsing, saved places, directions, and already-delivered results do not
spend an allowance.

## Economics: what is known vs. what must be measured

The repository has cost instrumentation but does **not** contain vendor invoice
rates. `paid_api_cost_rates` must be populated from the applicable Gemini,
Google Maps, Apify, and hosting invoices before a production price decision.
Do not treat a web-list price or a local test fixture as unit economics.

Before launching a paid offer, record for each discovery type:

1. Provider calls and cache hits per completed decision.
2. Input/output tokens, Places SKU counts, scraper units, and server duration.
3. Blended cost per *successful* discovery, including retries and refunds.
4. 7/30-day repeat usage, pass conversion, Pro conversion, churn, refund rate,
   and lost ad revenue for subscribers.

Use `paid_api_cost_dashboard` (documented in `supabase/MONITORING.md`) for
estimated spend after finance has entered reviewed rates. Compare it with vendor
invoices weekly; invoices are the source of truth.

## Staged rollout

### Stage 0 — local and code review

- Keep `BILUCommerceEnabled`, `BILUProEnabled`, `BILU_COMMERCE_ENABLED`, and
  `BILU_PRO_ENABLED` false.
- Run the Swift unit tests and the Deno normalization/fulfillment tests after
  every cost-control change. Use local StoreKit fixtures only.
- Review the frozen recommendation corpus for relevance, correct place identity,
  hard filters, diversity, latency, and provider calls per successful decision.
- Confirm there is no automatic Explore Trending request, detail media request,
  or sort-triggered paid request.

### Stage 1 — isolated sandbox (owner-approved)

- Create separate sandbox-only backend, Apple products, notification endpoint,
  and provider budget. Never point a sandbox StoreKit transaction at production.
- Start with internal testers and the approved finite allowance only. Do not
  offer a trial or an introductory price until retention and cost are measured.
- Exercise purchase, restore, pending approval, refund, renewal, expiry,
  account deletion, and kill-switch behavior using Apple’s sandbox.
- Enter actual unit rates, set a low daily global budget, and verify that a
  budget stop blocks new work but preserves verification and restore.

### Stage 2 — closed beta (50–100 invited users)

- Test the value proposition before scaling price: show the offer after a
  useful decision or attempted allowance use, never at first launch.
- A/B test *presentation*, not entitlement volume: “save time deciding” versus
  “more discoveries.” Keep the free experience useful.
- Monitor daily: completion rate, p95 latency, useful-result rate, provider
  cost/completed decision, cost per paying subscriber, payer repeat rate, and
  refunds/support complaints about allowances.
- Pause new sales immediately if provider cost exceeds the approved contribution
  margin or if identity/location correctness regresses. Existing purchases must
  still verify and restore.

### Stage 3 — limited public release

- Enable Commerce first; leave Pro off until pass retention and actual cost are
  stable for at least two billing/usage cycles.
- Offer a consumable Discovery Pass before a subscription in occasional-use
  markets. Enable Pro only for the cohort repeatedly using its 6+1 service-month
  allowance.
- Begin with a narrowly scoped region and a documented daily provider spend
  ceiling. Review invoice reconciliation and funnel data every week.

## Launch decision gates

Do not enable paid commerce until all of these are true:

- [ ] Reviewed vendor invoices populate cost rates and the margin model works at
      p95, not just average, provider usage.
- [ ] Global daily budget and provider quotas fail closed in the target backend.
- [ ] Sandbox purchase/restore/refund/notification tests pass against isolated
      Apple and Supabase environments.
- [ ] Discovery result quality passes the regression corpus, including sparse
      markets and wrong-place prevention.
- [ ] App Store privacy, hosted policy, Sign in with Apple, Account Deletion,
      price/region, and support/restore copy are complete.
- [ ] On-call owner knows how to pause new sales and paid discovery without
      invalidating restore or already-paid balances.

## Owner decisions still required

1. Actual App Store price/territories: the code reads StoreKit’s localized price;
   local `.storekit` values are not a launch price. The previously proposed
   experiment is $4.99 for Pass and $3.99/month or $34.99/year for Pro.
2. A contribution-margin floor and daily spend ceiling after invoice rates are
   entered.
3. Whether to run an annual plan, trial, or introductory offer. Start without
   one unless beta retention justifies it.
4. Explicit authorization to configure App Store Connect, deploy functions, and
   apply migrations. None of those actions are performed by this code change.

## Rollback

Turn off new sales/commerce flags first. Keep Apple verification, restore,
refund, notification, wallet reads, and existing discovery result recovery
available. Do not delete transactions, balances, or diagnostics as a rollback.
Record the cause, the affected version/region, observed cost and quality, and
the condition required to resume.
