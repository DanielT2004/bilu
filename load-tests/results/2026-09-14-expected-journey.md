# Concurrent-user Expected result — 2026-09-14

Environment: deployed Supabase Edge Functions `recommendations` version 17 and
`enrich` version 7. Each repetition ran ten concurrent, dedicated test users
through one recommendation-and-enrichment journey using synthetic Los
Angeles-area prompts.

## Result

All three required Expected-tier repetitions passed every acceptance gate.

| Metric | Acceptance | Run 1 | Run 2 | Run 3 | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Concurrent users | 10 | 10 | 10 | 10 | Measured |
| Total journeys | 10/run | 10 | 10 | 10 | Measured |
| Usable journey rate | >= 95% | 100% | 100% | 100% | Pass |
| Enriched journey rate | >= 90% | 100% | 100% | 100% | Pass |
| Capacity failure rate | < 1% | 0% | 0% | 0% | Pass |
| Upstream timeout rate | < 1% | 0% | 0% | 0% | Pass |
| Unexpected server failure rate | < 1% | 0% | 0% | 0% | Pass |
| Per-user limit failures | 0% | 0% | 0% | 0% | Pass |
| Recommendation p50 | — | 5,800.56 ms | 5,105.53 ms | 4,992.94 ms | Measured |
| Recommendation p95 | < 15,000 ms | 7,032.12 ms | 6,500.79 ms | 5,335.73 ms | Pass |
| Enrichment p95 | — | 1,111.63 ms | 1,124.64 ms | 1,435.36 ms | Measured |
| Complete journey p95 | < 23,000 ms | 7,926.05 ms | 7,382.90 ms | 6,633.60 ms | Pass |

Across 30 journeys, usable and enriched rates were both 100%, and the worst
observed rate for every failure category was 0%. Median repetition-level p95
was 6,500.79 ms for recommendations and 7,382.90 ms for the complete journey.

## Usage and estimated cost

| Metric | Run 1 | Run 2 | Run 3 | Total |
| --- | ---: | ---: | ---: | ---: |
| Gemini calls | 10 | 10 | 10 | 30 |
| Maps grounding queries | 3 | 2 | 2 | 7 |
| Gemini input tokens | 1,022 | 1,022 | 1,022 | 3,066 |
| Gemini output tokens | 4,525 | 3,781 | 3,876 | 12,182 |
| Places enrichment units | 50 | 50 | 50 | 150 |
| Estimated Gemini + grounding cost | $0.05973525 | $0.04294525 | $0.04330150 | $0.14598200 |

The cost is a lower bound because no reviewed blended Google Places enrichment
rate was configured. Machine-readable summaries are stored at
`load-tests/expected-journey-summary.json`,
`load-tests/expected-journey-run2-summary.json`, and
`load-tests/expected-journey-run3-summary.json`; these generated artifacts are
ignored by Git by design.
