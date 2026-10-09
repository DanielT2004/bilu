# Recommendation capacity test

For the end-to-end concurrent-user test covering both recommendations and
Places enrichment, use [CONCURRENT_USERS.md](CONCURRENT_USERS.md) and
`concurrent-journeys.k6.js`. The test below isolates recommendation capacity.

This test measures concurrent recommendation searches, end-to-end latency,
Gemini quota exhaustion, upstream call amplification, token usage, and estimated
cost. It is deliberately request-bounded: a run cannot exceed `MAX_REQUESTS`
(500 by default), and it will not start without an explicit paid-test
acknowledgement.

## Before testing

1. Deploy the instrumented `recommendations` Edge Function.
2. Use a non-production Gemini project when possible.
3. Confirm the Gemini project has enough remaining quota and budget for the run.
   Raising the provider spending cap is an operational change; application code
   cannot override it.
4. Install [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/).
5. Look up the current Gemini and Maps-grounding prices for the deployed model.
   Pass them as environment variables rather than hard-coding rates that will age.

## Run a bounded smoke test

```sh
CONFIRM_PAID_TEST=yes \
TARGET_URL="https://PROJECT.supabase.co/functions/v1/recommendations" \
SUPABASE_ANON_KEY="YOUR_ANON_KEY" \
USER_ACCESS_TOKENS="TOKEN_FOR_USER_1,TOKEN_FOR_USER_2" \
VUS=2 \
TOTAL_REQUESTS=10 \
SUMMARY_PATH="load-tests/smoke-summary.json" \
k6 run load-tests/recommendations.k6.js
```

The public project key identifies the Supabase project; it no longer authorizes
paid calls. `USER_ACCESS_TOKENS` must contain at least one current JWT per VU,
each belonging to a dedicated test user. This prevents a concurrency test from
measuring a single user's rate limit instead of system capacity.
`TOTAL_REQUESTS` must be evenly divisible by `VUS`; each virtual user receives
the same fixed number of searches so faster users cannot consume another
user's iterations and accidentally trip a per-user quota.

To include an estimate, add the applicable rates:

```sh
INPUT_USD_PER_MILLION_TOKENS="CURRENT_INPUT_RATE" \
OUTPUT_USD_PER_MILLION_TOKENS="CURRENT_OUTPUT_RATE" \
GROUNDING_QUERY_USD="CURRENT_MAPS_GROUNDING_QUERY_RATE"
```

Gemini 3 Maps grounding is billed per search query selected by the model, not
per HTTP request. The function therefore reports `X-Grounding-Queries`. A search
can also make as many as three Gemini calls, so the report records both values.
If a provider call times out before usage metadata is returned, the report marks
it as unmetered and treats the cost result as a lower bound instead of reporting
a misleading complete estimate.

## Capacity matrix

Run one tier at a time and stop when a tier fails. Keep `TOTAL_REQUESTS` fixed so
every run has a known maximum cost.

| Tier | VUs | Requests | Purpose |
| --- | ---: | ---: | --- |
| Smoke | 2 | 10 | Validate auth, telemetry, and response shape |
| Expected | 10 | 50 | Test normal launch concurrency |
| Peak | 25 | 100 | Test anticipated burst traffic |
| Stress | 50 | 200 | Find the first failing limit |

The default acceptance gates are:

- at least 95% successful searches;
- less than 1% typed upstream-capacity responses;
- p95 end-to-end latency under 20 seconds;
- every response has a request ID and Gemini usage headers.

Override the latency gate with `P95_TARGET_MS`. Tighten the success and capacity
thresholds in the script once a production SLO is agreed.

## Reading a failure

- `503` with `UPSTREAM_CAPACITY`: Gemini quota, rate limit, or spending cap. The
  function does not retry these errors, returns `Retry-After: 60`, and records the
  failure separately from application errors. A warm function instance also
  opens a 60-second circuit breaker so the rest of a burst does not keep hitting
  a provider that is already rejecting requests.
- `504` with `UPSTREAM_TIMEOUT`: Gemini exceeded the server latency budget. The
  report records this separately from quota exhaustion and flags any call with
  missing usage metadata as unmetered.
- High `X-Gemini-Calls`: prompt/JSON failures are activating the retry ladder and
  multiplying latency and cost.
- High total latency with low Gemini time: investigate Edge Function startup,
  routing, or response serialization.
- High Gemini time: reduce retry frequency/output size or request more upstream
  capacity before increasing user concurrency.

The JSON summary contains the observed concurrency settings, success and
capacity-exhaustion rates, p95 latency, calls, tokens, and estimated cost. Keep a
summary from each tier as release evidence.
