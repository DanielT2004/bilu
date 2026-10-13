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

## Optional discovery and banner diagnostics

`DiscoveryAnalytics` collects only when Profile → Privacy → Share Diagnostics is
enabled (off by default). Its bounded, memory-only queue holds at most 100 events,
uploads batches of 20 independently of recommendations, and drops a failed batch
after three attempts. A process exit can lose pending events. Opt-out clears the
queue and cancels pending uploads. No request prompt, location, restaurant,
dietary preference, reward token, advertising identifier, or backend discovery
identifier is sent. Each discovery uses a fresh random correlation ID.

This contract is separate from MetricKit: do not send these events to `telemetry`.
To enable collection on the server, apply
`20261009010000_discovery_ad_diagnostics.sql` after the earlier observability and
retention migrations, then deploy `discovery-telemetry` with JWT verification
enabled and deploy the updated `privacy-policy` function. The handler validates
the Supabase user before ingestion, rejects unknown fields, limits a request to
20 events/24 KB, and uses a service-role-only RPC with an atomic 1,000 event/user/UTC
day limit. Retries reuse event IDs and are idempotent. The event table does not
store account IDs; the separate daily abuse counter does. RLS and explicit grants
make raw events and aggregate views unavailable to app clients.

Use the service-role-only views:

- `discovery_loading_daily`: starts, completions, results arrivals, average
  completed loading duration, arrival rate, cancellations without arrival, and
  backgrounding without arrival, grouped by whether an impression was recorded.
- `discovery_ad_events_daily`: requests, impressions, failures, clicks and other
  event counts by release and server receipt date.
- `discovery_ad_revenue_daily`: sum SDK-reported revenue separately by currency
  and precision. Enable AdMob impression-level ad revenue reporting in the AdMob
  dashboard if needed for paid-event callbacks. Finalized AdMob reporting is the
  financial source of truth; do not sum mixed currencies or treat estimates as
  settled revenue.

Average loading time uses `completed.durationMilliseconds`; it excludes cancelled
and failed requests. Results-screen arrival rate is discoveries with both `started`
and `resultsArrived` divided by recorded starts. To examine possible ad-related
abandonment, compare cancellation/background-without-arrival counts between the
impression cohorts alongside latency. These are correlations, not evidence that
an ad caused an exit: slow requests are likelier both to show an ad and lose a
user. Backgrounding can be temporary or caused by opening an ad. Missing terminal
events can reflect app termination, offline loss, opt-out, queue limits, or upload
failure; they must not automatically be classified as ad-caused abandonment.
Opt-in users are a selected sample, so neither revenue nor conversion rates from
this pipeline represent all users. Use a consent-respecting randomized comparison
before attributing a change in arrival rate to banners.

The local tests make no provider or production calls:

```sh
npx --yes deno test --allow-env supabase/functions/discovery-telemetry/handler_test.ts
python3 scripts/test_discovery_diagnostics.py
```

The SQL runner uses a disposable loopback-only PostgreSQL instance and stubs Cron
registration only. Production retention scheduling and the deployed endpoint
still require operational verification after release configuration.

## Retention

`20260915000000_diagnostic_retention.sql` schedules a daily cleanup matching
the published 30-day diagnostic retention period. The cleanup performs:

```sql
delete from public.app_diagnostics
where received_at < now() - interval '30 days';

delete from public.app_diagnostic_daily_limits
where bucket_date < current_date - 30;
```

The discovery diagnostics migration adds `purge-bilu-discovery-diagnostics`, which
deletes raw discovery/ad events after 30 days and abuse counters after 31 days.
The aggregate views read the retained events; they do not retain a hidden copy.
