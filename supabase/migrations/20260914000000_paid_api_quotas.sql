-- Per-user and global spend-unit limits for paid Edge Function upstreams.
-- Only the service role can execute the accounting function or read the table.

create table if not exists public.paid_api_usage_buckets (
  user_id     uuid not null references auth.users(id) on delete cascade,
  service     text not null,
  window_kind text not null check (window_kind in ('minute', 'day')),
  bucket_start timestamptz not null,
  units       integer not null check (units >= 0),
  updated_at  timestamptz not null default now(),
  primary key (user_id, service, window_kind, bucket_start)
);

alter table public.paid_api_usage_buckets enable row level security;
revoke all on table public.paid_api_usage_buckets from anon, authenticated;

create table if not exists public.paid_api_global_usage_buckets (
  service      text not null,
  bucket_start timestamptz not null,
  units        integer not null check (units >= 0),
  updated_at   timestamptz not null default now(),
  primary key (service, bucket_start)
);

alter table public.paid_api_global_usage_buckets enable row level security;
revoke all on table public.paid_api_global_usage_buckets from anon, authenticated;

create or replace function public.consume_paid_api_quota(
  p_user_id uuid,
  p_service text,
  p_cost_units integer,
  p_minute_limit integer,
  p_daily_limit integer,
  p_global_daily_limit integer
)
returns table (
  allowed boolean,
  retry_after_seconds integer,
  minute_remaining integer,
  daily_remaining integer,
  global_daily_remaining integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_minute_bucket timestamptz := date_trunc('minute', v_now);
  v_day_bucket timestamptz := date_trunc('day', v_now);
  v_minute_units integer := 0;
  v_day_units integer := 0;
  v_global_day_units integer := 0;
begin
  if p_user_id is null
     or p_service is null
     or length(p_service) = 0
     or p_cost_units <= 0
     or p_minute_limit <= 0
     or p_daily_limit <= 0
     or p_global_daily_limit <= 0 then
    raise exception 'invalid quota arguments';
  end if;

  -- Serialize accounting for a single user/service pair so concurrent requests
  -- cannot race past either limit.
  -- Always take the global lock first to avoid deadlocks across users.
  perform pg_advisory_xact_lock(hashtextextended('global:' || p_service, 0));
  perform pg_advisory_xact_lock(
    hashtextextended(p_user_id::text || ':' || p_service, 0)
  );

  select b.units into v_global_day_units
  from public.paid_api_global_usage_buckets b
  where b.service = p_service
    and b.bucket_start = v_day_bucket;
  v_global_day_units := coalesce(v_global_day_units, 0);

  select b.units into v_minute_units
  from public.paid_api_usage_buckets b
  where b.user_id = p_user_id
    and b.service = p_service
    and b.window_kind = 'minute'
    and b.bucket_start = v_minute_bucket;
  v_minute_units := coalesce(v_minute_units, 0);

  select b.units into v_day_units
  from public.paid_api_usage_buckets b
  where b.user_id = p_user_id
    and b.service = p_service
    and b.window_kind = 'day'
    and b.bucket_start = v_day_bucket;
  v_day_units := coalesce(v_day_units, 0);

  if v_global_day_units + p_cost_units > p_global_daily_limit then
    return query select
      false,
      greatest(1, ceil(extract(epoch from (v_day_bucket + interval '1 day' - v_now)))::integer),
      greatest(0, p_minute_limit - v_minute_units),
      greatest(0, p_daily_limit - v_day_units),
      0;
    return;
  end if;

  if v_day_units + p_cost_units > p_daily_limit then
    return query select
      false,
      greatest(1, ceil(extract(epoch from (v_day_bucket + interval '1 day' - v_now)))::integer),
      greatest(0, p_minute_limit - v_minute_units),
      greatest(0, p_daily_limit - v_day_units),
      greatest(0, p_global_daily_limit - v_global_day_units);
    return;
  end if;

  if v_minute_units + p_cost_units > p_minute_limit then
    return query select
      false,
      greatest(1, ceil(extract(epoch from (v_minute_bucket + interval '1 minute' - v_now)))::integer),
      greatest(0, p_minute_limit - v_minute_units),
      greatest(0, p_daily_limit - v_day_units),
      greatest(0, p_global_daily_limit - v_global_day_units);
    return;
  end if;

  insert into public.paid_api_usage_buckets (
    user_id, service, window_kind, bucket_start, units, updated_at
  ) values (
    p_user_id, p_service, 'minute', v_minute_bucket, p_cost_units, v_now
  )
  on conflict (user_id, service, window_kind, bucket_start)
  do update set
    units = public.paid_api_usage_buckets.units + excluded.units,
    updated_at = excluded.updated_at;

  insert into public.paid_api_global_usage_buckets (
    service, bucket_start, units, updated_at
  ) values (
    p_service, v_day_bucket, p_cost_units, v_now
  )
  on conflict (service, bucket_start)
  do update set
    units = public.paid_api_global_usage_buckets.units + excluded.units,
    updated_at = excluded.updated_at;

  insert into public.paid_api_usage_buckets (
    user_id, service, window_kind, bucket_start, units, updated_at
  ) values (
    p_user_id, p_service, 'day', v_day_bucket, p_cost_units, v_now
  )
  on conflict (user_id, service, window_kind, bucket_start)
  do update set
    units = public.paid_api_usage_buckets.units + excluded.units,
    updated_at = excluded.updated_at;

  return query select
    true,
    0,
    greatest(0, p_minute_limit - v_minute_units - p_cost_units),
    greatest(0, p_daily_limit - v_day_units - p_cost_units),
    greatest(0, p_global_daily_limit - v_global_day_units - p_cost_units);
end;
$$;

revoke all on function public.consume_paid_api_quota(uuid, text, integer, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_paid_api_quota(uuid, text, integer, integer, integer, integer)
  to service_role;

comment on table public.paid_api_usage_buckets is
  'Server-only per-user accounting for paid upstream API budget units.';
comment on table public.paid_api_global_usage_buckets is
  'Server-only service-wide accounting that caps exposure across all users.';
