-- First-party crash/performance ingestion and paid-API cost dashboard primitives.

create table if not exists public.app_diagnostics (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('diagnostic', 'metric')),
  payload jsonb not null,
  app_version text not null,
  build text not null,
  os_version text not null,
  captured_at timestamptz not null,
  received_at timestamptz not null default now()
);

create index if not exists app_diagnostics_received_at_idx
  on public.app_diagnostics (received_at desc);
create index if not exists app_diagnostics_kind_version_idx
  on public.app_diagnostics (kind, app_version, received_at desc);

create table if not exists public.app_diagnostic_daily_limits (
  user_id uuid not null references auth.users(id) on delete cascade,
  bucket_date date not null,
  event_count integer not null default 0 check (event_count >= 0),
  primary key (user_id, bucket_date)
);

alter table public.app_diagnostics enable row level security;
alter table public.app_diagnostic_daily_limits enable row level security;
revoke all on public.app_diagnostics from anon, authenticated;
revoke all on public.app_diagnostic_daily_limits from anon, authenticated;

create or replace function public.ingest_app_diagnostic(
  p_event_id uuid,
  p_user_id uuid,
  p_kind text,
  p_payload jsonb,
  p_app_version text,
  p_build text,
  p_os_version text,
  p_captured_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := timezone('utc', now())::date;
  v_count integer;
begin
  if p_kind not in ('diagnostic', 'metric')
     or octet_length(p_payload::text) > 500000 then
    return false;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text || v_today::text, 0));
  insert into public.app_diagnostic_daily_limits (user_id, bucket_date, event_count)
  values (p_user_id, v_today, 0)
  on conflict (user_id, bucket_date) do nothing;

  select event_count into v_count
  from public.app_diagnostic_daily_limits
  where user_id = p_user_id and bucket_date = v_today
  for update;

  if v_count >= 20 then return false; end if;

  insert into public.app_diagnostics (
    id, user_id, kind, payload, app_version, build, os_version, captured_at
  ) values (
    p_event_id, p_user_id, p_kind, p_payload,
    left(p_app_version, 64), left(p_build, 64), left(p_os_version, 128), p_captured_at
  ) on conflict (id) do nothing;

  if found then
    update public.app_diagnostic_daily_limits
    set event_count = event_count + 1
    where user_id = p_user_id and bucket_date = v_today;
  end if;
  return true;
end;
$$;

revoke all on function public.ingest_app_diagnostic(uuid, uuid, text, jsonb, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.ingest_app_diagnostic(uuid, uuid, text, jsonb, text, text, text, timestamptz)
  to service_role;

create table if not exists public.paid_api_cost_rates (
  service text primary key,
  usd_per_unit numeric(14, 8) not null check (usd_per_unit >= 0),
  updated_at timestamptz not null default now()
);
alter table public.paid_api_cost_rates enable row level security;
revoke all on public.paid_api_cost_rates from anon, authenticated;

create or replace view public.paid_api_cost_dashboard as
select
  g.service,
  g.bucket_start::date as usage_date,
  g.units,
  r.usd_per_unit,
  case when r.usd_per_unit is null then null
       else round(g.units * r.usd_per_unit, 4) end as estimated_usd,
  r.updated_at as rate_updated_at
from public.paid_api_global_usage_buckets g
left join public.paid_api_cost_rates r using (service);

revoke all on public.paid_api_cost_dashboard from anon, authenticated;
grant select on public.paid_api_cost_dashboard to service_role;

create or replace view public.app_diagnostics_daily as
select
  received_at::date as received_date,
  app_version,
  build,
  kind,
  count(*) as event_count
from public.app_diagnostics
group by received_at::date, app_version, build, kind;

revoke all on public.app_diagnostics_daily from anon, authenticated;
grant select on public.app_diagnostics_daily to service_role;
