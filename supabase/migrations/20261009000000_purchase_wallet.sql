-- Server-owned purchase ledger. Apple identifiers are durable replay tombstones;
-- deleting/recreating an app account must never make a transaction redeemable again.
create table public.purchase_wallet_configuration (
  singleton boolean primary key default true check (singleton),
  commerce_enabled boolean not null default false,
  pro_enabled boolean not null default false,
  apple_environment text not null default 'Production' check (apple_environment in ('Production', 'Sandbox'))
);
insert into public.purchase_wallet_configuration (singleton) values (true);

create table public.purchase_apple_owners (
  environment text not null,
  original_transaction_id text not null,
  user_id uuid not null,
  primary key (environment, original_transaction_id)
);
create table public.purchase_apple_transactions (
  environment text not null,
  transaction_id text not null,
  original_transaction_id text not null,
  user_id uuid not null,
  product_id text not null check (product_id in ('com.simonsoloman.bilu.discovery_pass', 'com.simonsoloman.bilu.pro.monthly', 'com.simonsoloman.bilu.pro.annual')),
  purchased_at timestamptz not null,
  expires_at timestamptz,
  signed_at timestamptz not null,
  revoked_at timestamptz,
  primary key (environment, transaction_id),
  foreign key (environment, original_transaction_id) references public.purchase_apple_owners (environment, original_transaction_id)
);
create index purchase_apple_transactions_user_idx on public.purchase_apple_transactions (user_id, expires_at);
create table public.purchase_apple_notifications (
  notification_id uuid primary key,
  environment text not null,
  transaction_id text not null,
  notification_type text,
  received_at timestamptz not null default now()
);
create table public.purchase_credit_grants (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null,
  transaction_id text not null,
  explore_remaining integer not null check (explore_remaining between 0 and 4),
  tiktok_remaining integer not null check (tiktok_remaining between 0 and 1),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique (environment, transaction_id),
  foreign key (environment, transaction_id) references public.purchase_apple_transactions (environment, transaction_id)
);
create index purchase_credit_grants_user_idx on public.purchase_credit_grants (user_id, created_at);
create table public.purchase_service_periods (
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null default 'Production' check (environment in ('Production', 'Sandbox')),
  plan text not null check (plan in ('free', 'pro')),
  period_start timestamptz not null,
  period_end timestamptz not null check (period_end > period_start),
  explore_used integer not null default 0 check (explore_used >= 0),
  tiktok_used integer not null default 0 check (tiktok_used >= 0),
  primary key (user_id, environment, plan, period_start)
);
create table public.purchase_discoveries (
  discovery_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null check (environment in ('Production', 'Sandbox')),
  kind text not null check (kind in ('explore', 'tiktok')),
  status text not null check (status in ('reserved', 'committed', 'released', 'expired', 'revoked')),
  source text not null check (source in ('included', 'purchased')),
  source_plan text,
  source_period_start timestamptz,
  source_grant_id uuid references public.purchase_credit_grants(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  result jsonb check (result is null or octet_length(result::text) <= 524288),
  result_expires_at timestamptz,
  check ((source = 'included' and source_plan is not null and source_period_start is not null and source_grant_id is null)
    or (source = 'purchased' and source_grant_id is not null and source_plan is null and source_period_start is null))
);
create index purchase_discoveries_user_idx on public.purchase_discoveries (user_id, status, expires_at);

-- Internal helpers have no client grants, just like the externally called RPCs.
create function public.purchase_release_reservation(p_discovery_id uuid, p_status text)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_row public.purchase_discoveries%rowtype;
begin
  if p_status not in ('released', 'expired', 'revoked') then raise exception 'invalid terminal status'; end if;
  select * into v_row from public.purchase_discoveries where discovery_id = p_discovery_id for update;
  if not found or v_row.status <> 'reserved' then return; end if;
  if v_row.source = 'included' then
    update public.purchase_service_periods set
      explore_used = explore_used - case when v_row.kind = 'explore' then 1 else 0 end,
      tiktok_used = tiktok_used - case when v_row.kind = 'tiktok' then 1 else 0 end
    where user_id = v_row.user_id and environment = v_row.environment
      and plan = v_row.source_plan and period_start = v_row.source_period_start;
  else
    -- A refunded purchase never regains credit, even if an old worker releases it.
    update public.purchase_credit_grants set
      explore_remaining = explore_remaining + case when v_row.kind = 'explore' then 1 else 0 end,
      tiktok_remaining = tiktok_remaining + case when v_row.kind = 'tiktok' then 1 else 0 end
    where id = v_row.source_grant_id and revoked_at is null;
  end if;
  update public.purchase_discoveries set status = p_status where discovery_id = p_discovery_id;
end;
$$;

create function public.purchase_expire_reservations(p_user_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('wallet:' || p_user_id::text, 0));
  for v_id in select discovery_id from public.purchase_discoveries
    where user_id = p_user_id and status = 'reserved' and expires_at <= now()
  loop perform public.purchase_release_reservation(v_id, 'expired'); end loop;
  update public.purchase_discoveries set result = null
    where user_id = p_user_id and result_expires_at <= now() and result is not null;
end;
$$;

create function public.purchase_anchored_month(p_anchor timestamptz, p_now timestamptz)
returns table (period_start timestamptz, period_end timestamptz)
language plpgsql immutable set search_path = pg_catalog, public as $$
declare
  v_anchor timestamp := p_anchor at time zone 'UTC';
  v_now timestamp := p_now at time zone 'UTC';
  v_months integer;
begin
  v_months := (extract(year from v_now)::integer - extract(year from v_anchor)::integer) * 12
    + extract(month from v_now)::integer - extract(month from v_anchor)::integer;
  if v_anchor + make_interval(months => v_months) > v_now then v_months := v_months - 1; end if;
  return query select (v_anchor + make_interval(months => v_months)) at time zone 'UTC',
    (v_anchor + make_interval(months => v_months + 1)) at time zone 'UTC';
end;
$$;

create function public.purchase_current_period(p_user_id uuid, p_environment text default null)
returns table (plan text, period_start timestamptz, period_end timestamptz, explore_limit integer, tiktok_limit integer)
language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_original text; v_environment text; v_anchor timestamptz; v_entitlement_end timestamptz;
begin
  select t.original_transaction_id, t.environment, t.expires_at into v_original, v_environment, v_entitlement_end
  from public.purchase_apple_transactions t join public.purchase_wallet_configuration c on c.singleton
  where t.user_id = p_user_id and t.product_id in ('com.simonsoloman.bilu.pro.monthly', 'com.simonsoloman.bilu.pro.annual')
    and t.revoked_at is null and t.purchased_at <= now() and t.expires_at > now()
    and t.environment = coalesce(p_environment, c.apple_environment)
  order by t.expires_at desc limit 1;
  if found then
    select min(t.purchased_at) into v_anchor from public.purchase_apple_transactions t
      where t.environment = v_environment and t.original_transaction_id = v_original;
    return query select 'pro'::text, m.period_start, least(m.period_end, v_entitlement_end), 6, 1
      from public.purchase_anchored_month(v_anchor, now()) m;
  else
    return query select 'free'::text,
      date_trunc('month', now() at time zone 'UTC') at time zone 'UTC',
      (date_trunc('month', now() at time zone 'UTC') + interval '1 month') at time zone 'UTC', 2, 1;
  end if;
end;
$$;

create function public.purchase_wallet_snapshot(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_period record; v_used public.purchase_service_periods%rowtype; v_explore integer; v_tiktok integer; v_anonymous boolean; v_config public.purchase_wallet_configuration%rowtype;
begin
  select coalesce(is_anonymous, false) into v_anonymous from auth.users where id = p_user_id;
  if not found then raise exception 'wallet account missing'; end if;
  perform public.purchase_expire_reservations(p_user_id);
  select * into v_config from public.purchase_wallet_configuration where singleton;
  select * into v_period from public.purchase_current_period(p_user_id, v_config.apple_environment);
  select * into v_used from public.purchase_service_periods where user_id = p_user_id and environment = v_config.apple_environment
    and plan = v_period.plan and period_start = v_period.period_start;
  select coalesce(sum(explore_remaining), 0), coalesce(sum(tiktok_remaining), 0) into v_explore, v_tiktok
    from public.purchase_credit_grants where user_id = p_user_id and environment = v_config.apple_environment and revoked_at is null;
  return jsonb_build_object('accountId', p_user_id, 'requiresSignIn', v_anonymous, 'appAccountToken', p_user_id,
    'plan', v_period.plan, 'periodStart', v_period.period_start, 'periodEnd', v_period.period_end,
    'included', jsonb_build_object('explore', greatest(0, v_period.explore_limit - coalesce(v_used.explore_used, 0)), 'tiktok', greatest(0, v_period.tiktok_limit - coalesce(v_used.tiktok_used, 0))),
    'purchased', jsonb_build_object('explore', v_explore, 'tiktok', v_tiktok),
    'commerceEnabled', coalesce(v_config.commerce_enabled, false), 'proEnabled', coalesce(v_config.commerce_enabled and v_config.pro_enabled, false),
    'appleEnvironment', v_config.apple_environment);
end;
$$;

create function public.apple_transaction_owner(p_original_transaction_id text, p_environment text)
returns uuid language sql security definer set search_path = pg_catalog, public as $$
  select user_id from public.purchase_apple_owners where environment = p_environment and original_transaction_id = p_original_transaction_id;
$$;

create function public.apple_apply_transaction(
  p_user_id uuid, p_app_account_token uuid, p_transaction_id text, p_original_transaction_id text,
  p_product_id text, p_environment text, p_signed_at timestamptz, p_purchased_at timestamptz,
  p_expires_at timestamptz default null, p_revoked_at timestamptz default null,
  p_notification_id uuid default null, p_notification_type text default null
)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_owner uuid; v_existing public.purchase_apple_transactions%rowtype; v_config public.purchase_wallet_configuration%rowtype; v_new boolean; v_id uuid;
begin
  if p_user_id is null or p_app_account_token is distinct from p_user_id
    or p_transaction_id is null or p_transaction_id !~ '^[0-9]{1,128}$'
    or p_original_transaction_id is null or p_original_transaction_id !~ '^[0-9]{1,128}$'
    or p_environment is null or p_environment not in ('Production', 'Sandbox')
    or p_product_id is null or p_product_id not in ('com.simonsoloman.bilu.discovery_pass', 'com.simonsoloman.bilu.pro.monthly', 'com.simonsoloman.bilu.pro.annual')
    or p_signed_at is null or p_purchased_at is null or p_signed_at > now() + interval '5 minutes'
    or p_purchased_at > now() + interval '5 minutes'
    or (p_product_id <> 'com.simonsoloman.bilu.discovery_pass' and (p_expires_at is null or p_expires_at <= p_purchased_at)) then
    raise exception 'invalid verified transaction';
  end if;
  -- A shared transaction lock also guards competing claims with different
  -- original IDs; never rely on an upsert to establish transaction ownership.
  perform pg_advisory_xact_lock(hashtextextended('apple-transaction:' || p_environment || ':' || p_transaction_id, 0));
  -- Transaction locks precede the account lock everywhere Apple transactions enter.
  perform pg_advisory_xact_lock(hashtextextended('apple:' || p_environment || ':' || p_original_transaction_id, 0));
  perform pg_advisory_xact_lock(hashtextextended('wallet:' || p_user_id::text, 0));
  select * into v_config from public.purchase_wallet_configuration where singleton;
  if p_environment is distinct from v_config.apple_environment then raise exception 'purchase environment mismatch'; end if;
  select user_id into v_owner from public.purchase_apple_owners where environment = p_environment and original_transaction_id = p_original_transaction_id;
  if found and v_owner <> p_user_id then raise exception 'transaction ownership mismatch'; end if;
  -- Notifications may mutate existing ownership, but may never create ownership.
  if p_notification_id is not null and v_owner is null then raise exception 'transaction ownership missing'; end if;
  select * into v_existing from public.purchase_apple_transactions where environment = p_environment and transaction_id = p_transaction_id;
  v_new := not found;
  if not v_new and (v_existing.user_id <> p_user_id or v_existing.product_id <> p_product_id
    or v_existing.original_transaction_id <> p_original_transaction_id or v_existing.purchased_at <> p_purchased_at) then
    raise exception 'transaction claims mismatch';
  end if;
  -- Only verified server notifications may reconcile a deleted owner's existing
  -- mapping without a live account. Keep its monotonic transaction tombstones,
  -- including delayed renewal IDs; the grant insert below still requires a user.
  -- Anonymous accounts and purchase retries must not use this exception.
  if not exists(select 1 from auth.users where id = p_user_id and not coalesce(is_anonymous, false))
    and not (coalesce(v_owner = p_user_id, false) and (p_revoked_at is not null
      or (p_notification_id is not null and not exists(select 1 from auth.users where id = p_user_id)))) then
    raise exception 'durable account required';
  end if;
  -- Sales can pause after StoreKit has already charged. A cryptographically
  -- verified paid pass must still fulfill; flags only gate offering new sales.
  -- New Pro activation is restricted, while existing subscriptions reconcile.
  if v_owner is null and p_revoked_at is null and p_product_id <> 'com.simonsoloman.bilu.discovery_pass'
    and not coalesce(v_config.commerce_enabled and v_config.pro_enabled, false) then raise exception 'pro disabled'; end if;
  if p_notification_id is not null then
    insert into public.purchase_apple_notifications(notification_id, environment, transaction_id, notification_type)
      values(p_notification_id, p_environment, p_transaction_id, left(p_notification_type, 80)) on conflict do nothing;
    if not found then return jsonb_build_object('applied', false, 'accountId', p_user_id); end if;
  end if;
  insert into public.purchase_apple_owners values(p_environment, p_original_transaction_id, p_user_id) on conflict do nothing;
  insert into public.purchase_apple_transactions(environment, transaction_id, original_transaction_id, user_id, product_id, purchased_at, expires_at, signed_at, revoked_at)
    values(p_environment, p_transaction_id, p_original_transaction_id, p_user_id, p_product_id, p_purchased_at, p_expires_at, p_signed_at, p_revoked_at)
  on conflict (environment, transaction_id) do update set
    signed_at = greatest(public.purchase_apple_transactions.signed_at, excluded.signed_at),
    expires_at = case when excluded.signed_at > public.purchase_apple_transactions.signed_at then excluded.expires_at else public.purchase_apple_transactions.expires_at end,
    revoked_at = coalesce(public.purchase_apple_transactions.revoked_at, excluded.revoked_at);
  if p_product_id = 'com.simonsoloman.bilu.discovery_pass' then
    -- ON CONFLICT + permanent revocation is the exactly-once grant barrier.
    insert into public.purchase_credit_grants(user_id, environment, transaction_id, explore_remaining, tiktok_remaining, revoked_at)
      select p_user_id, p_environment, p_transaction_id, case when revoked_at is null then 4 else 0 end,
        case when revoked_at is null then 1 else 0 end, revoked_at
      from public.purchase_apple_transactions where environment = p_environment and transaction_id = p_transaction_id
        and v_new and exists(select 1 from auth.users where id = p_user_id)
      on conflict (environment, transaction_id) do nothing;
    if p_revoked_at is not null then
      update public.purchase_credit_grants set explore_remaining = 0, tiktok_remaining = 0, revoked_at = coalesce(revoked_at, p_revoked_at)
        where environment = p_environment and transaction_id = p_transaction_id;
      for v_id in select d.discovery_id from public.purchase_discoveries d join public.purchase_credit_grants g on g.id = d.source_grant_id
        where g.environment = p_environment and g.transaction_id = p_transaction_id and d.status = 'reserved'
      loop perform public.purchase_release_reservation(v_id, 'revoked'); end loop;
    end if;
  end if;
  return jsonb_build_object('applied', v_new or (v_existing.revoked_at is null and p_revoked_at is not null), 'accountId', p_user_id);
end;
$$;

create function public.purchase_discovery_json(p_row public.purchase_discoveries, p_acquired boolean default false)
returns jsonb language sql stable set search_path = pg_catalog, public as $$
  select jsonb_strip_nulls(jsonb_build_object('discoveryId', p_row.discovery_id, 'kind', p_row.kind,
    'status', p_row.status, 'source', p_row.source, 'acquired', p_acquired, 'expiresAt', p_row.expires_at,
    'result', case when p_row.result_expires_at > now() then p_row.result else null end, 'resultExpiresAt', p_row.result_expires_at));
$$;

create function public.purchase_discovery(p_user_id uuid, p_discovery_id uuid, p_kind text, p_action text, p_result jsonb default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_row public.purchase_discoveries%rowtype; v_period record; v_used integer; v_grant uuid; v_source text; v_config public.purchase_wallet_configuration%rowtype;
begin
  if p_user_id is null or p_discovery_id is null or p_kind is null or p_kind not in ('explore', 'tiktok')
    or p_action is null or p_action not in ('reserve', 'read', 'commit', 'release') then raise exception 'invalid discovery arguments'; end if;
  if p_action = 'commit' and (p_result is null or octet_length(p_result::text) > 524288) then raise exception 'invalid discovery result'; end if;
  -- Global discovery IDs cannot be transferred or changed between kinds.
  perform pg_advisory_xact_lock(hashtextextended('discovery:' || p_discovery_id::text, 0));
  perform public.purchase_expire_reservations(p_user_id);
  select * into v_config from public.purchase_wallet_configuration where singleton;
  select * into v_row from public.purchase_discoveries where discovery_id = p_discovery_id for update;
  if found then
    if v_row.user_id <> p_user_id or v_row.kind <> p_kind then raise exception 'discovery ownership mismatch'; end if;
    -- A job never crosses Store environments. Cleanup may always return an
    -- original source; execution and result recovery require its environment.
    if p_action <> 'release' and v_row.environment is distinct from v_config.apple_environment then
      return jsonb_build_object('discoveryId', p_discovery_id, 'kind', p_kind,
        'status', 'environment_mismatch', 'source', null, 'acquired', false);
    end if;
    if p_action = 'release' then
      perform public.purchase_release_reservation(p_discovery_id, 'released');
    elsif p_action = 'commit' and v_row.status = 'reserved' then
      update public.purchase_discoveries set status = 'committed', result = p_result, result_expires_at = now() + interval '24 hours'
        where discovery_id = p_discovery_id;
    end if;
    select * into v_row from public.purchase_discoveries where discovery_id = p_discovery_id;
    return public.purchase_discovery_json(v_row);
  end if;
  if p_action <> 'reserve' then return jsonb_build_object('discoveryId', p_discovery_id, 'kind', p_kind, 'status', 'missing', 'source', null, 'acquired', false); end if;
  if not coalesce(v_config.commerce_enabled, false) then raise exception 'commerce disabled'; end if;
  if not exists(select 1 from auth.users where id = p_user_id) then raise exception 'wallet account missing'; end if;
  select * into v_period from public.purchase_current_period(p_user_id, v_config.apple_environment);
  insert into public.purchase_service_periods(user_id, environment, plan, period_start, period_end)
    values(p_user_id, v_config.apple_environment, v_period.plan, v_period.period_start, v_period.period_end) on conflict do nothing;
  select case when p_kind = 'explore' then explore_used else tiktok_used end into v_used
    from public.purchase_service_periods where user_id = p_user_id and environment = v_config.apple_environment
      and plan = v_period.plan and period_start = v_period.period_start;
  if v_used < (case when p_kind = 'explore' then v_period.explore_limit else v_period.tiktok_limit end) then
    v_source := 'included';
    update public.purchase_service_periods set explore_used = explore_used + case when p_kind = 'explore' then 1 else 0 end,
      tiktok_used = tiktok_used + case when p_kind = 'tiktok' then 1 else 0 end
      where user_id = p_user_id and environment = v_config.apple_environment
        and plan = v_period.plan and period_start = v_period.period_start;
  else
    select id into v_grant from public.purchase_credit_grants where user_id = p_user_id
      and environment = v_config.apple_environment and revoked_at is null
      and case when p_kind = 'explore' then explore_remaining else tiktok_remaining end > 0 order by created_at, id limit 1;
    if v_grant is null then return jsonb_build_object('discoveryId', p_discovery_id, 'kind', p_kind, 'status', 'exhausted', 'source', null, 'acquired', false); end if;
    v_source := 'purchased';
    update public.purchase_credit_grants set explore_remaining = explore_remaining - case when p_kind = 'explore' then 1 else 0 end,
      tiktok_remaining = tiktok_remaining - case when p_kind = 'tiktok' then 1 else 0 end where id = v_grant;
  end if;
  insert into public.purchase_discoveries(discovery_id, user_id, environment, kind, status, source, source_plan, source_period_start, source_grant_id, expires_at)
    values(p_discovery_id, p_user_id, v_config.apple_environment, p_kind, 'reserved', v_source,
      case when v_source = 'included' then v_period.plan else null end,
      case when v_source = 'included' then v_period.period_start else null end, v_grant, now() + interval '30 minutes') returning * into v_row;
  return public.purchase_discovery_json(v_row, true);
end;
$$;

create function public.purchase_wallet_maintenance()
returns void language plpgsql security definer set search_path = pg_catalog, public as $$
declare v_user uuid;
begin
  for v_user in select distinct user_id from public.purchase_discoveries where status = 'reserved' and expires_at <= now() order by user_id
  loop perform public.purchase_expire_reservations(v_user); end loop;
  update public.purchase_discoveries set result = null where result_expires_at <= now() and result is not null;
end;
$$;

do $$
declare v_table text; v_function regprocedure;
begin
  foreach v_table in array array['purchase_wallet_configuration', 'purchase_apple_owners', 'purchase_apple_transactions', 'purchase_apple_notifications', 'purchase_credit_grants', 'purchase_service_periods', 'purchase_discoveries'] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', v_table);
    execute format('grant all on table public.%I to service_role', v_table);
  end loop;
  for v_function in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and (p.proname like 'purchase_%' or p.proname in ('apple_transaction_owner', 'apple_apply_transaction'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', v_function);
    execute format('grant execute on function %s to service_role', v_function);
  end loop;
  -- Supabase has pg_cron from the diagnostic-retention migration. A vanilla
  -- local Postgres test database can run the maintenance RPC explicitly.
  if exists(select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule('purge-bilu-purchase-results', '*/5 * * * *', 'select public.purchase_wallet_maintenance()');
  end if;
end;
$$;

comment on table public.purchase_credit_grants is 'Nonexpiring consumable balances; revoked grants can never be recredited.';
comment on table public.purchase_discoveries is 'Server workflow reservations; original source is immutable, results expire after 24 hours, IDs remain replay tombstones.';
