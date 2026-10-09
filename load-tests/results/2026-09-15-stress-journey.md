# Concurrent-user Stress result — 2026-09-15

Environment: deployed Supabase Edge Functions `recommendations` version 17 and
`enrich` version 7. The run used 50 concurrent, dedicated test users and one
recommendation-and-enrichment journey per user with synthetic Los Angeles-area
prompts. This is the test plan's Stress tier, run in response to the requested
“Max” tier.

## Result

The Stress tier failed the unexpected-server-failure acceptance gate.

| Metric | Acceptance | Observed | Result |
| --- | ---: | ---: | --- |
| Concurrent users | 50 | 50 | Measured |
| Total journeys | 50 | 50 | Measured |
| Usable journey rate | >= 95% | 98% | Pass |
| Enriched journey rate | >= 90% | 98% | Pass |
| Capacity failure rate | < 1% | 0% | Pass |
| Upstream timeout rate | < 1% | 0% | Pass |
| Unexpected server failure rate | < 1% | 1.01% | **Fail** |
| Per-user limit failures | 0% | 0% | Pass |
| Recommendation p50 | — | 6,591.06 ms | Measured |
| Recommendation p95 | < 15,000 ms | 8,117.58 ms | Pass |
| Enrichment p95 | — | 4,577.36 ms | Measured |
| Complete journey p95 | < 23,000 ms | 12,072.35 ms | Pass |

Forty-nine of 50 recommendation requests returned usable results and proceeded
to enrichment. One recommendation request returned an unexpected 5xx, yielding
a 2% user-visible journey failure rate. The harness's server-failure rate is
calculated over all 99 HTTP calls made by the run, so it reports 1/99, or 1.01%.
No capacity, upstream-timeout, or user-quota error was observed.

The usage counters show 49 Gemini calls for 50 recommendation requests, which
indicates that the failed request did not produce a metered Gemini call. The
summary does not retain failed request IDs, so the precise 5xx cause requires
correlation in production function logs.

## Usage and estimated cost

| Metric | Observed |
| --- | ---: |
| Recommendation requests | 50 |
| Enrichment requests | 49 |
| Gemini calls | 49 |
| Maps grounding queries | 8 |
| Gemini input tokens | 5,009 |
| Gemini output tokens | 18,960 |
| Places enrichment units | 245 |
| Estimated Gemini + grounding cost | $0.18685675 |

The cost is a lower bound because no reviewed blended Google Places enrichment
rate was configured. The machine-readable summary is stored at
`load-tests/stress-journey-summary.json` and ignored by Git by design.

Supabase Auth throttled burst creation of the synthetic identity pool. The final
pool was provisioned with bounded backoff before the synchronized workload, so
authentication setup time is excluded from the measured journey latency and
did not reduce load-phase concurrency.
