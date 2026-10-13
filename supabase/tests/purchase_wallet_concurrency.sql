-- LOCAL ONLY: requires an isolated Postgres database, superuser, and dblink.
-- Run after the wallet migration. Opens 24 local sessions and creates/removes
-- fixtures. Never run this test against a shared or production database.
do $$ begin
  if inet_server_addr() not in ('127.0.0.1'::inet, '::1'::inet) then
    raise exception 'concurrency fixture requires a loopback database connection';
  end if;
end $$;
create extension if not exists dblink;
create function pg_temp.assert_true(p_value boolean, p_message text)
returns void language plpgsql as $$ begin
  if p_value is distinct from true then raise exception 'ASSERTION FAILED: %', p_message; end if;
end $$;
create function pg_temp.race(p_queries text[])
returns setof jsonb language plpgsql as $$
declare v_i integer; v_result jsonb; v_name text;
begin
  for v_i in 1..array_length(p_queries, 1) loop
    v_name := 'wallet_race_' || v_i;
    perform dblink_connect(v_name, format('host=127.0.0.1 port=%s dbname=%s user=%s', current_setting('port'), current_database(), current_user));
    perform dblink_send_query(v_name, p_queries[v_i]);
  end loop;
  for v_i in 1..array_length(p_queries, 1) loop
    v_name := 'wallet_race_' || v_i;
    select result into v_result from dblink_get_result(v_name) as rows(result jsonb);
    perform dblink_disconnect(v_name);
    return next v_result;
  end loop;
end $$;
insert into auth.users(id,is_anonymous) values
  ('cccccccc-0000-4000-8000-000000000001',false),
  ('cccccccc-0000-4000-8000-000000000002',false);
update public.purchase_wallet_configuration set commerce_enabled = true;

select pg_temp.assert_true(count(*) filter(where (result->>'applied')::boolean) = 1, '24 duplicate purchase requests grant exactly once')
from pg_temp.race(array_fill($q$select public.apple_apply_transaction('cccccccc-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','999000001','999000001','com.simonsoloman.bilu.discovery_pass','Production',now(),'2026-01-01Z')$q$::text, array[24])) as r(result);
select pg_temp.assert_true(public.purchase_wallet_snapshot('cccccccc-0000-4000-8000-000000000001')->'purchased' = '{"explore":4,"tiktok":1}'::jsonb, 'concurrent duplicate exact grant');

select pg_temp.assert_true(count(*) filter(where (result->>'acquired')::boolean) = 6, 'concurrent unique Explore reservations stop at free2 plus purchased4')
from pg_temp.race(array(select format($q$select public.purchase_discovery('cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-%s','explore','reserve')$q$, lpad(i::text,12,'0')) from generate_series(1,24) i)) as r(result);
select pg_temp.assert_true(public.purchase_wallet_snapshot('cccccccc-0000-4000-8000-000000000001')->'purchased'->>'explore' = '0', 'concurrent reservations never overspend');

select pg_temp.assert_true(count(*) filter(where (result->>'acquired')::boolean) = 1, 'same discovery starts exactly one provider worker')
from pg_temp.race(array_fill($q$select public.purchase_discovery('cccccccc-0000-4000-8000-000000000002','dddddddd-0000-4000-8000-000000000100','explore','reserve')$q$::text, array[24])) as r(result);
select pg_temp.assert_true(public.purchase_wallet_snapshot('cccccccc-0000-4000-8000-000000000002')->'included'->>'explore' = '1', 'duplicate reservation debits once');

select pg_temp.assert_true(count(*) filter(where (result->>'acquired')::boolean) = 2, 'TikTok independently caps at free1 plus purchased1')
from pg_temp.race(array(select format($q$select public.purchase_discovery('cccccccc-0000-4000-8000-000000000001','dddddddd-0000-4000-8000-%s','tiktok','reserve')$q$, lpad((i+200)::text,12,'0')) from generate_series(1,24) i)) as r(result);

-- Competing release and refund cannot restore any of the refunded grant.
select count(*) from pg_temp.race(array(
  select case when i % 2 = 0 then
    $q$select public.apple_apply_transaction('cccccccc-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000001','999000001','999000001','com.simonsoloman.bilu.discovery_pass','Production',now(),'2026-01-01Z',null,now())$q$
  else format($q$select public.purchase_discovery('cccccccc-0000-4000-8000-000000000001',%L,'explore','release')$q$,
    (select discovery_id from public.purchase_discoveries where user_id='cccccccc-0000-4000-8000-000000000001' and kind='explore' and source='purchased' limit 1)) end
  from generate_series(1,24) i));
select pg_temp.assert_true(public.purchase_wallet_snapshot('cccccccc-0000-4000-8000-000000000001')->'purchased' = '{"explore":0,"tiktok":0}'::jsonb, 'refund/release race never resurrects credit');
select pg_temp.assert_true(not exists(select 1 from public.purchase_discoveries d join public.purchase_credit_grants g on g.id = d.source_grant_id where g.transaction_id = '999000001' and d.status = 'reserved'), 'refund invalidates all remaining reservations');

delete from auth.users where id in ('cccccccc-0000-4000-8000-000000000001','cccccccc-0000-4000-8000-000000000002');
delete from public.purchase_apple_transactions where transaction_id = '999000001';
delete from public.purchase_apple_owners where original_transaction_id = '999000001';
update public.purchase_wallet_configuration set commerce_enabled = false;
