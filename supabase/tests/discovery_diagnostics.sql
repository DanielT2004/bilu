begin;
insert into auth.users (id) values ('11111111-1111-4111-8111-111111111111');

do $$
declare
  v_user uuid := '11111111-1111-4111-8111-111111111111';
  v_discovery uuid := gen_random_uuid();
  v_batch jsonb;
  v_rate numeric;
begin
  v_batch := jsonb_build_array(
    jsonb_build_object('id', gen_random_uuid(), 'discoveryID', v_discovery, 'event', 'started',
      'capturedAt', now(), 'adVisible', false),
    jsonb_build_object('id', gen_random_uuid(), 'discoveryID', v_discovery, 'event', 'completed',
      'capturedAt', now(), 'adVisible', true, 'durationMilliseconds', 2500),
    jsonb_build_object('id', gen_random_uuid(), 'discoveryID', v_discovery, 'event', 'adImpression',
      'capturedAt', now(), 'adVisible', true),
    jsonb_build_object('id', gen_random_uuid(), 'discoveryID', v_discovery, 'event', 'resultsArrived',
      'capturedAt', now(), 'adVisible', false),
    jsonb_build_object('id', gen_random_uuid(), 'discoveryID', v_discovery, 'event', 'adRevenue',
      'capturedAt', now(), 'adVisible', true, 'revenue', '0.000001', 'currency', 'USD', 'precision', 3)
  );
  if not public.ingest_discovery_diagnostics(v_user, 'test', '1', v_batch) then raise exception 'valid batch rejected'; end if;
  if not public.ingest_discovery_diagnostics(v_user, 'test', '1', v_batch) then raise exception 'retry rejected'; end if;
  if (select count(*) from public.discovery_diagnostics) <> 5 then raise exception 'retry inserted duplicates'; end if;
  if (select event_count from public.discovery_diagnostic_daily_limits) <> 5 then raise exception 'retry charged quota twice'; end if;
  if (select average_loading_milliseconds from public.discovery_loading_daily) <> 2500 then raise exception 'loading duration wrong'; end if;
  select results_arrival_rate into v_rate from public.discovery_loading_daily;
  if v_rate <> 1 then raise exception 'arrival rate wrong'; end if;
  if (select revenue from public.discovery_ad_revenue_daily) <> 0.000001 then raise exception 'decimal revenue changed'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'discovery_diagnostics' and column_name = 'user_id') then
    raise exception 'event table contains account identifier';
  end if;

  update public.discovery_diagnostic_daily_limits set event_count = 1000;
  if not public.ingest_discovery_diagnostics(v_user, 'test', '1', v_batch) then raise exception 'idempotent retry at limit rejected'; end if;
  v_batch := jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'discoveryID', v_discovery,
    'event', 'started', 'capturedAt', now(), 'adVisible', false));
  if public.ingest_discovery_diagnostics(v_user, 'test', '1', v_batch) then raise exception 'daily cap bypassed'; end if;
  if public.ingest_discovery_diagnostics(v_user, 'test', '1', '[]'::jsonb) then raise exception 'empty batch accepted'; end if;
  if public.ingest_discovery_diagnostics(null, 'test', '1', v_batch) then raise exception 'unauthenticated batch accepted'; end if;
end;
$$;

set local role authenticated;
do $$
begin
  begin
    perform * from public.discovery_diagnostics;
    raise exception 'authenticated role can read raw diagnostics';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.ingest_discovery_diagnostics(gen_random_uuid(), 'test', '1', '[]'::jsonb);
    raise exception 'authenticated role can call ingestion RPC';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
rollback;
