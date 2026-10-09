-- Server-enforced discovery allowance: one free run per UTC day, then one run
-- for each Google-verified rewarded ad. Only service-role Edge Functions may
-- read or mutate this accounting data.

create table if not exists public.rewarded_ad_sessions (
  token uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  verified_at timestamptz,
  consumed_at timestamptz,
  transaction_id text unique,
  reward_amount integer,
  ad_unit text
);

alter table public.rewarded_ad_sessions enable row level security;
revoke all on table public.rewarded_ad_sessions from anon, authenticated;

create table if not exists public.free_discovery_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  units integer not null default 0 check (units >= 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_day)
);

alter table public.free_discovery_usage enable row level security;
revoke all on table public.free_discovery_usage from anon, authenticated;

create or replace function public.consume_discovery_access(
  p_user_id uuid,
  p_reward_token uuid default null,
  p_daily_free_limit integer default 1
)
returns table (allowed boolean, access_source text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (clock_timestamp() at time zone 'utc')::date;
  v_units integer := 0;
begin
  if p_user_id is null or p_daily_free_limit < 0 then
    raise exception 'invalid discovery access arguments';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('discovery:' || p_user_id::text, 0));

  select units into v_units
  from public.free_discovery_usage
  where user_id = p_user_id and usage_day = v_today;
  v_units := coalesce(v_units, 0);

  if v_units < p_daily_free_limit then
    insert into public.free_discovery_usage (user_id, usage_day, units, updated_at)
    values (p_user_id, v_today, 1, now())
    on conflict (user_id, usage_day) do update
      set units = public.free_discovery_usage.units + 1,
          updated_at = now();
    return query select true, 'free'::text;
    return;
  end if;

  if p_reward_token is not null then
    update public.rewarded_ad_sessions
      set consumed_at = now()
    where token = p_reward_token
      and user_id = p_user_id
      and verified_at is not null
      and consumed_at is null
      and expires_at > now();
    if found then
      return query select true, 'rewarded'::text;
      return;
    end if;
  end if;

  return query select false, 'required'::text;
end;
$$;

revoke all on function public.consume_discovery_access(uuid, uuid, integer)
  from public, anon, authenticated;
grant execute on function public.consume_discovery_access(uuid, uuid, integer)
  to service_role;
