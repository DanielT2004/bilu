# Concurrent-user smoke result — 2026-09-14

Environment: deployed Supabase Edge Functions `recommendations` version 17 and
`enrich` version 7. The run used two dedicated anonymous test users and
synthetic Los Angeles-area prompts.

## Result

| Metric | Acceptance | Observed | Result |
| --- | ---: | ---: | --- |
| Concurrent users | 2 | 2 | Measured |
| Total journeys | 2 | 2 | Measured |
| Usable journey rate | >= 95% | 100% | Pass |
| Enriched journey rate | >= 90% | 100% | Pass |
| Capacity failure rate | < 1% | 0% | Pass |
| Upstream timeout rate | < 1% | 0% | Pass |
| Unexpected server failure rate | < 1% | 0% | Pass |
| Per-user limit failures | 0% | 0% | Pass |
| Recommendation p50 | — | 5,050.26 ms | Measured |
| Recommendation p95 | < 15,000 ms | 5,088.92 ms | Pass |
| Enrichment p95 | — | 938.97 ms | Measured |
| Complete journey p95 | < 23,000 ms | 6,078.85 ms | Pass |
| Gemini calls | — | 2 | 1.0/search |
| Maps grounding queries | — | 0 | Measured |
| Places enrichment units | — | 10 | Measured |
| Estimated Gemini + grounding cost | — | $0.0027555 | Lower bound |

All smoke-tier acceptance gates passed. The estimated cost excludes Google
Places because no reviewed blended Places enrichment rate was configured.

This successful run supersedes an earlier invalid attempt in which a negative
array index caused one virtual user to send an empty request body. The harness
now uses a zero-based, non-negative test-case index.

The generated machine-readable summary is `load-tests/smoke-journey-summary.json`
(ignored by Git by design).
