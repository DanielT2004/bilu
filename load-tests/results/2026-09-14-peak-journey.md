# Concurrent-user Peak results — 2026-09-14 to 2026-09-15

Environment: deployed Supabase Edge Functions `recommendations` version 17 and
`enrich` version 7. Each repetition ran 25 concurrent, dedicated test users
through one recommendation-and-enrichment journey using synthetic Los
Angeles-area prompts. Run 1 occurred on September 14; Runs 2 and 3 occurred on
September 15.

## Result

All three required Peak-tier repetitions passed every acceptance gate.

| Metric | Acceptance | Run 1 | Run 2 | Run 3 | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Concurrent users | 25 | 25 | 25 | 25 | Measured |
| Total journeys | 25/run | 25 | 25 | 25 | Measured |
| Usable journey rate | >= 95% | 100% | 100% | 100% | Pass |
| Enriched journey rate | >= 90% | 100% | 100% | 100% | Pass |
| Capacity failure rate | < 1% | 0% | 0% | 0% | Pass |
| Upstream timeout rate | < 1% | 0% | 0% | 0% | Pass |
| Unexpected server failure rate | < 1% | 0% | 0% | 0% | Pass |
| Per-user limit failures | 0% | 0% | 0% | 0% | Pass |
| Recommendation p50 | — | 5,175.55 ms | 6,371.10 ms | 5,500.41 ms | Measured |
| Recommendation p95 | < 15,000 ms | 6,722.07 ms | 12,205.67 ms | 6,933.88 ms | Pass |
| Enrichment p95 | — | 2,476.51 ms | 1,972.80 ms | 2,389.89 ms | Measured |
| Complete journey p95 | < 23,000 ms | 8,177.20 ms | 12,988.60 ms | 9,253.80 ms | Pass |

Across 75 journeys, usable and enriched rates were both 100%, and the worst
observed rate for every failure category was 0%. Median repetition-level p95
was 6,933.88 ms for recommendations and 9,253.80 ms for the complete journey.
Run 2 showed higher latency than the other repetitions but remained within both
targets.

## Usage and estimated cost

| Metric | Run 1 | Run 2 | Run 3 | Total |
| --- | ---: | ---: | ---: | ---: |
| Gemini calls | 25 | 25 | 25 | 75 |
| Maps grounding queries | 0 | 10 | 9 | 19 |
| Gemini input tokens | 2,556 | 2,556 | 2,556 | 7,668 |
| Gemini output tokens | 10,187 | 10,737 | 9,849 | 30,773 |
| Places enrichment units | 125 | 125 | 125 | 375 |
| Estimated Gemini + grounding cost | $0.04011825 | $0.18218075 | $0.16485075 | $0.38714975 |

The cost is a lower bound because no reviewed blended Google Places enrichment
rate was configured. Machine-readable summaries are stored at
`load-tests/peak-journey-summary.json`,
`load-tests/peak-journey-run2-summary.json`, and
`load-tests/peak-journey-run3-summary.json`; these generated artifacts are
ignored by Git by design.
