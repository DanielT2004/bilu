# Concurrent-user load-test design

## Objective

Measure how many simultaneous users can complete the app's real discovery
journey before latency, reliability, provider capacity, or cost becomes
unacceptable. A journey consists of:

1. `recommendations`: time to the first usable shortlist.
2. `enrich`: background Places metadata, photos, and coordinates.

Each virtual user uses a distinct authenticated test account. This prevents the
per-user quota from masquerading as a system-capacity limit.

## Test environments and safety

- Prefer a staging Supabase project with production-equivalent function limits.
- Use synthetic locations and prompts; never copy production user data.
- Confirm provider hard budgets and alerts before each run.
- Run tiers sequentially and stop at the first failed tier.
- The script requires `CONFIRM_PAID_TEST=yes` and refuses more than 500 journeys
  unless `MAX_JOURNEYS` is deliberately raised.
- Refresh all JWTs immediately before testing. The script verifies that every
  concurrent user has a distinct, unexpired subject.

## Workload tiers

| Tier | Concurrent users | Journeys/user | Think time | Maximum journeys | Purpose |
| --- | ---: | ---: | ---: | ---: | --- |
| Smoke | 2 | 1 | 0s | 2 | Validate auth, response shape, and telemetry |
| Expected | 10 | 1 | 0s | 10 | Normal simultaneous launch traffic |
| Peak | 25 | 1 | 0s | 25 | Anticipated burst traffic |
| Stress | 50 | 1 | 0s | 50 | Find the first capacity breakpoint |
| Soak | 10 | 20 | 15s | 200 | Detect degradation, leaks, and quota drift over ~5 minutes |

Run at least three repetitions of Expected and Peak. Use the median p95 and the
worst observed error rate; one unusually good run is not release evidence.

## Acceptance criteria

- At least 95% of journeys return a usable initial shortlist.
- At least 90% also complete enrichment; an enrichment failure must leave the
  initial shortlist usable.
- Recommendation p95 is below 15 seconds.
- Complete recommendation-plus-enrichment p95 is below 23 seconds.
- Unexpected 5xx, upstream timeouts, and capacity failures are each below 1%.
- No request reaches a per-user limit during a capacity tier.
- Every recommendation response contains a request ID and usage headers.
- The observed token, grounding-query, and quota-unit totals fit the approved
  maximum cost for the tier.

## Run command

```sh
CONFIRM_PAID_TEST=yes \
API_BASE_URL="https://PROJECT.supabase.co/functions/v1" \
SUPABASE_ANON_KEY="PUBLIC_PROJECT_KEY" \
USER_ACCESS_TOKENS="USER_1_JWT,USER_2_JWT,..." \
CONCURRENT_USERS=10 \
JOURNEYS_PER_USER=1 \
SUMMARY_PATH="load-tests/expected-journey-summary.json" \
k6 run load-tests/concurrent-journeys.k6.js
```

For an estimated cost, also provide the current
`INPUT_USD_PER_MILLION_TOKENS`, `OUTPUT_USD_PER_MILLION_TOKENS`,
`GROUNDING_QUERY_USD`, and a measured blended
`PLACES_ENRICHMENT_UNIT_USD`. An estimate is reported as a lower bound whenever
a timed-out Gemini call lacks usage metadata.

For the soak tier, set `CONCURRENT_USERS=10`, `JOURNEYS_PER_USER=20`, and
`THINK_TIME_SECONDS=15`.

## Evidence to retain

Keep the JSON summary, deployed function version, provider/model versions,
configured quota limits, provider billing export for the test window, and
Supabase invocation/log screenshots. Record cold and warm runs separately.

Correlate failures using `X-Request-Id`. Compare client-observed latency with
Supabase invocation duration and `Server-Timing`; the difference isolates edge
routing/network overhead from Gemini generation time.

## Stop conditions

Stop immediately if the global application budget reaches 20% remaining, a
provider hard-spend alert fires, the capacity circuit breaker opens repeatedly,
unexpected 5xx exceeds 5% over any 20 requests, or p95 exceeds twice its target.
Do not increase concurrency until the preceding tier passes.
