# Concurrent-user Stress rerun — 2026-09-16

Environment: deployed Supabase Edge Functions after removing opaque
`sb_secret_...` values from `Authorization: Bearer` headers. Secret keys are
now sent only through the `apikey` header for internal Data API calls.

Deployed versions used by this run:

- `recommendations` version 19
- `enrich` version 8
- `photos` version 8
- `tiktok-search` version 11
- `tiktok-locations` version 9
- `telemetry` version 2

The run used 50 concurrent, distinct test users and one full recommendation and
enrichment journey per user. All 50 temporary accounts were deleted after the
run.

## Result

The Stress tier passed every reliability and latency gate.

| Metric | Acceptance | Observed | Result |
| --- | ---: | ---: | --- |
| Concurrent users | 50 | 50 | Measured |
| Total journeys | 50 | 50 | Measured |
| Usable journey rate | >= 95% | 100% | Pass |
| Enriched journey rate | >= 90% | 100% | Pass |
| Capacity failure rate | < 1% | 0% | Pass |
| Upstream timeout rate | < 1% | 0% | Pass |
| Unexpected server failure rate | < 1% | 0% | Pass |
| Per-user limit failures | 0% | 0% | Pass |
| Recommendation p50 | — | 6,663.76 ms | Measured |
| Recommendation p95 | < 15,000 ms | 8,136.30 ms | Pass |
| Enrichment p95 | — | 6,757.67 ms | Measured |
| Complete journey p95 | < 23,000 ms | 13,462.55 ms | Pass |

All 50 recommendation requests and all 50 enrichment requests succeeded. The
run made 50 metered Gemini calls, 9 grounding queries, and 249 Places
enrichment units. Pricing variables were not configured, so this rerun does not
claim a cost estimate.

Production-log correlation for the test window found 50 recommendation
capacity events with status 200, zero `paid_api_quota_rpc_failed` events, and
zero PostgREST `PGRST303` authentication failures.

The machine-readable summary is stored at
`load-tests/stress-journey-summary.json` and ignored by Git by design.
