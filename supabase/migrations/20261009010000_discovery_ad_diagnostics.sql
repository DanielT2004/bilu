-- Opt-in discovery/ad funnel events are separated from MetricKit reports.
-- Event rows contain no account ID. A random, per-discovery ID joins the funnel;
-- authenticated account IDs exist only in the independent abuse-limit table.
create table if not exists public.discovery_diagnostics (
  id uuid primary key,
  discovery_id uuid not null,
  event text not null check (event in (
    'started', 'completed', 'failed', 'cancelled', 'resultsArrived',
    'adRequested', 'adImpression', 'adFailed', 'adRevenue', 'adClicked', 'backgrounded'
  )),
  captured_at timestamptz not null,
  received_at timestamptz not null default now(),
  app_version text not null check (length(app_version) <= 64),
  build text not null check (length(build) <= 64),
  duration_milliseconds integer check (duration_milliseconds between 0 and 3600000),
  ad_visible boolean not null,
  error_code integer check (error_code between -100000 and 100000),
  revenue numeric check (revenue between 0 and 10000),
  currency text check (currency ~ '^[A-Z]{3}$'),
  revenue_precision integer check (revenue_precision between 0 and 3),
  check (
    (event = 'adRevenue' and revenue is not null and currency is not null and revenue_precision is not null)
    or (event <> 'adRevenue' and revenue is null and currency is null and revenue_precision is null)
  )
);
create index if not exists discovery_diagnostics_received_at_idx
  on public.discovery_diagnostics (received_at);
create index if not exists discovery_diagnostics_discovery_idx
  on public.discovery_diagnostics (discovery_id);

create table if not exists public.discovery_diagnostic_daily_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket_date date not null,
  event_count integer not null default 0 check (event_count >= 0),
  primary key (user_id, bucket_date)
);

alter table public.discovery_diagnostics enable row level security;
alter table public.discovery_diagnostic_daily_limits enable row level security;
revoke all on public.discovery_diagnostics, public.discovery_diagnostic_daily_limits
  from public, anon, authenticated;
grant select on public.discovery_diagnostics to service_role;

create or replace function public.ingest_discovery_diagnostics(
  p_user_id uuid,
  p_app_version text,
  p_build text,
  p_events jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := timezone('utc', now())::date;
  v_count integer;
  v_inserted integer;
  v_new_count integer;
begin
  if p_user_id is null or jsonb_typeof(p_events) is distinct from 'array' then return false; end if;
  if jsonb_array_length(p_events) not between 1 and 20
    or octet_length(p_events::text) > 24000 then return false; end if;

  perform pg_advisory_xact_lock(hashtextextended('discovery-diagnostics:' || p_user_id::text || v_today::text, 0));
  insert into public.discovery_diagnostic_daily_limits (user_id, bucket_date)
  values (p_user_id, v_today) on conflict do nothing;
  select event_count into v_count from public.discovery_diagnostic_daily_limits
    where user_id = p_user_id and bucket_date = v_today for update;

  select count(distinct (e->>'id')::uuid) into v_new_count
    from jsonb_array_elements(p_events) e
    where not exists (select 1 from public.discovery_diagnostics d where d.id = (e->>'id')::uuid);
  if v_count + v_new_count > 1000 then return false; end if;

  insert into public.discovery_diagnostics (
    id, discovery_id, event, captured_at, app_version, build,
    duration_milliseconds, ad_visible, error_code, revenue, currency, revenue_precision
  )
  select
    (e->>'id')::uuid, (e->>'discoveryID')::uuid, e->>'event', (e->>'capturedAt')::timestamptz,
    left(p_app_version, 64), left(p_build, 64), (e->>'durationMilliseconds')::integer,
    (e->>'adVisible')::boolean, (e->>'code')::integer, (e->>'revenue')::numeric,
    e->>'currency', (e->>'precision')::integer
  from jsonb_array_elements(p_events) e
  on conflict (id) do nothing;
  get diagnostics v_inserted = row_count;
  update public.discovery_diagnostic_daily_limits
    set event_count = event_count + v_inserted where user_id = p_user_id and bucket_date = v_today;
  return true;
end;
$$;
revoke all on function public.ingest_discovery_diagnostics(uuid, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.ingest_discovery_diagnostics(uuid, text, text, jsonb)
  to service_role;

-- Compare cohorts with and without a recorded impression. This is observational
-- correlation: longer waits themselves make both impressions and exits likelier.
create or replace view public.discovery_loading_daily as
with discoveries as (
  select discovery_id, app_version, build,
    (min(received_at) at time zone 'UTC')::date as received_date,
    bool_or(event = 'started') as started,
    bool_or(event = 'completed') as completed,
    bool_or(event = 'resultsArrived') as arrived,
    bool_or(event = 'cancelled') as cancelled,
    bool_or(event = 'backgrounded') as backgrounded,
    bool_or(event = 'adImpression') as had_ad_impression,
    max(duration_milliseconds) filter (where event = 'completed') as loading_ms
  from public.discovery_diagnostics
  group by discovery_id, app_version, build
)
select received_date, app_version, build, had_ad_impression,
  count(*) filter (where started) as discoveries_started,
  count(*) filter (where started and completed) as discoveries_completed,
  count(*) filter (where started and arrived) as results_arrived,
  avg(loading_ms) filter (where started and completed) as average_loading_milliseconds,
  count(*) filter (where started and arrived)::numeric /
    nullif(count(*) filter (where started), 0) as results_arrival_rate,
  count(*) filter (where started and cancelled and not arrived) as cancellations_without_arrival,
  count(*) filter (where started and backgrounded and not arrived) as backgrounded_without_arrival
from discoveries
group by received_date, app_version, build, had_ad_impression;

create or replace view public.discovery_ad_events_daily as
select (received_at at time zone 'UTC')::date as received_date, app_version, build, event, count(*) as event_count
from public.discovery_diagnostics group by 1, 2, 3, 4;

-- Keep currencies and SDK precision separate. These client-reported values are
-- diagnostic estimates; finalized AdMob reporting remains the source of truth.
create or replace view public.discovery_ad_revenue_daily as
select (received_at at time zone 'UTC')::date as received_date, app_version, build,
  currency, revenue_precision, count(*) as revenue_events, sum(revenue) as revenue
from public.discovery_diagnostics where event = 'adRevenue'
group by 1, 2, 3, 4, 5;

revoke all on public.discovery_loading_daily, public.discovery_ad_events_daily, public.discovery_ad_revenue_daily
  from public, anon, authenticated;
grant select on public.discovery_loading_daily, public.discovery_ad_events_daily, public.discovery_ad_revenue_daily
  to service_role;

select cron.unschedule(jobid) from cron.job where jobname = 'purge-bilu-discovery-diagnostics';
select cron.schedule('purge-bilu-discovery-diagnostics', '23 3 * * *', $$
  delete from public.discovery_diagnostics where received_at < now() - interval '30 days';
  delete from public.discovery_diagnostic_daily_limits where bucket_date < current_date - 31;
$$);
