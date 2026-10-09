# Production monitoring

The repository provides first-party crash ingestion, structured Edge Function
logs, quota threshold events, and SQL views for API usage and estimated cost.
These controls become operational only after deployment and alert routing.

## Deployment

1. Apply `20260914000000_paid_api_quotas.sql`, then
   `20260914010000_production_observability.sql`.
2. Deploy the `telemetry` function with JWT verification enabled.
3. Ship the iOS build. MetricKit reports are queued on disk until the telemetry
   endpoint accepts them; each user is limited to 20 reports per UTC day.
4. Enter the deployed `privacy-policy` function URL in App Store Connect and
   keep the App Store privacy disclosures aligned with MetricKit collection.

## Dashboards

Query `app_diagnostics_daily` for crash/performance volume by release. Raw
MetricKit JSON is available in `app_diagnostics` for symbolication and analysis.

Populate `paid_api_cost_rates` with reviewed blended USD costs per accounting
unit. Do not hard-code vendor prices in a migration; update them whenever Gemini,
Places, or Apify pricing or the request shape changes. Query
`paid_api_cost_dashboard` for daily units and estimated spend:

```sql
select *
from public.paid_api_cost_dashboard
where usage_date >= current_date - 30
order by usage_date desc, service;
```

## Alerts

Edge Functions emit structured events suitable for saved log queries and alert
rules:

- `paid_api_budget_warning` at 20%, 10%, and 5% global budget remaining
- `paid_api_budget_exhausted` when a service-wide budget blocks work
- `paid_api_quota_rpc_failed` when quota enforcement is unavailable
- `recommendations_capacity`, including latency, status, calls, and token usage
- `telemetry_ingest_failed` when crash storage is unavailable

In Supabase, inspect function invocation status/duration in Functions > Logs.
For paging, configure Project Settings > Log Drains to an OTLP, Datadog, Loki,
Sentry Logs, Axiom, or custom endpoint and create alerts for the events above.
At minimum, page on budget exhaustion, repeated quota-RPC failures, sustained 5xx
rates, and a release-to-release increase in crash diagnostics.

MetricKit is delayed and sampled by the operating system. If the product needs
real-time crash notification, add a dedicated crash SDK after choosing a vendor
and completing the required privacy and credential setup.

## Retention

`20260915000000_diagnostic_retention.sql` schedules a daily cleanup matching
the published 30-day diagnostic retention period. The cleanup performs:

```sql
delete from public.app_diagnostics
where received_at < now() - interval '30 days';

delete from public.app_diagnostic_daily_limits
where bucket_date < current_date - 30;
```
