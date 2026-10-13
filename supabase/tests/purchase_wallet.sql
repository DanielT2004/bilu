-- Run against an isolated local database after the purchase-wallet migration.
-- No provider calls, production project, pgTAP, or live Apple purchase required.
begin;
create function pg_temp.assert_true(p_value boolean, p_message text)
returns void language plpgsql as $$ begin
  if p_value is distinct from true then raise exception 'ASSERTION FAILED: %', p_message; end if;
end $$;
create function pg_temp.assert_fails(p_sql text, p_message text)
returns void language plpgsql as $$ begin
  begin execute p_sql; exception when others then return; end;
  raise exception 'ASSERTION FAILED (expected rejection): %', p_message;
end $$;
create function pg_temp.buy(p_user uuid, p_tx text, p_revoked timestamptz default null)
returns jsonb language sql as $$
  select public.apple_apply_transaction(p_user, p_user, p_tx, p_tx,
    'com.simonsoloman.bilu.discovery_pass', 'Production', now(), now() - interval '1 day', null, p_revoked);
$$;
insert into auth.users(id, is_anonymous) values
  ('aaaaaaaa-0000-0000-0000-000000000001', false),
  ('aaaaaaaa-0000-0000-0000-000000000002', false),
  ('aaaaaaaa-0000-0000-0000-000000000003', true),
  ('aaaaaaaa-0000-0000-0000-000000000004', false);

select pg_temp.assert_true(not (public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->>'commerceEnabled')::boolean, 'commerce defaults off');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000002', '600');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000002')->'purchased' = '{"explore":4,"tiktok":1}'::jsonb, 'already paid pass fulfills while sales flag is off');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000002', '600', now());
update public.purchase_wallet_configuration set commerce_enabled = true;
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->'included' = '{"explore":2,"tiktok":1}'::jsonb, 'free included allowance');
select pg_temp.assert_true((public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000003')->>'requiresSignIn')::boolean, 'anonymous requires sign in');
select pg_temp.assert_fails($s$select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000003', '101')$s$, 'anonymous cannot buy');
select pg_temp.assert_fails($s$select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000002','100','100','com.simonsoloman.bilu.discovery_pass','Production',now(),now())$s$, 'appAccountToken binds account');
select pg_temp.assert_fails($s$select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','100','100','com.simonsoloman.bilu.discovery_pass','Sandbox',now(),now())$s$, 'sandbox cannot grant production');
select pg_temp.assert_fails($s$select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','100','100','com.simonsoloman.bilu.discovery_pass','Production',now(),now(),null,null,gen_random_uuid(),'ONE_TIME_CHARGE')$s$, 'notification cannot establish ownership');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '100');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '100');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->'purchased' = '{"explore":4,"tiktok":1}'::jsonb, 'duplicate transaction grants once');
select pg_temp.assert_fails($s$select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000002', '100')$s$, 'purchase cannot transfer accounts');

-- Monthly allowance is spent before purchased credits, and reservations debit once.
select pg_temp.assert_true((public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','explore','reserve')->>'acquired')::boolean, 'initial acquire');
select pg_temp.assert_true(not (public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','explore','reserve')->>'acquired')::boolean, 'repeat never starts another worker');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','explore','commit','{"restaurants":[{"name":"Fixture"}]}');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','explore','commit','{"replaced":true}')->'result' = '{"restaurants":[{"name":"Fixture"}]}'::jsonb, 'replayed commit preserves original result');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','explore','release')->>'status' = 'committed', 'committed cannot refund by releasing');
select pg_temp.assert_fails($s$select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000001','explore','read')$s$, 'cannot read another account result');
select pg_temp.assert_fails($s$select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','tiktok','read')$s$, 'kind cannot change');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002','explore','reserve');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002','explore','commit','{}');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000003','explore','reserve')->>'source' = 'purchased', 'purchased fallback');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000003','explore','commit','{}');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004','explore','reserve');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004','explore','release');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004','explore','release');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->'purchased' = '{"explore":3,"tiktok":1}'::jsonb, 'release returns exactly one purchased unit');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000004','explore','reserve')->>'status' = 'released', 'released identifier cannot start again');

-- Refund touches only its own remaining credit; pending work cannot resurrect it.
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000005','explore','reserve');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '200');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '100', now());
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '100');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000005','explore','release');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000005','explore','commit','{}')->>'status' = 'revoked', 'revoked work cannot commit');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->'purchased' = '{"explore":4,"tiktok":1}'::jsonb, 'refund preserves unrelated transaction and never regrants');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '300', now());
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '300');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->'purchased' = '{"explore":4,"tiktok":1}'::jsonb, 'revoked-before-purchase remains zero');

-- Expiring abandoned work releases to the original grant/period; grants never expire.
update public.purchase_credit_grants set created_at = now() - interval '3 years' where transaction_id = '200';
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000006','explore','reserve');
update public.purchase_discoveries set expires_at = now() - interval '1 minute' where discovery_id = 'bbbbbbbb-0000-0000-0000-000000000006';
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000006','explore','commit','{}')->>'status' = 'expired', 'expired work cannot commit');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->'purchased' = '{"explore":4,"tiktok":1}'::jsonb, 'old consumables stay spendable and expired lease is returned');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000007','explore','reserve');
insert into public.purchase_service_periods(user_id,plan,period_start,period_end,explore_used)
  values('aaaaaaaa-0000-0000-0000-000000000002','free','2020-01-01Z','2020-02-01Z',1);
update public.purchase_discoveries set source_period_start = '2020-01-01Z' where discovery_id = 'bbbbbbbb-0000-0000-0000-000000000007';
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000007','explore','release');
select pg_temp.assert_true((select explore_used = 0 from public.purchase_service_periods where user_id = 'aaaaaaaa-0000-0000-0000-000000000002' and period_start = '2020-01-01Z'), 'old period restored');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000002')->'included'->>'explore' = '1', 'old period release never increases current allowance');

-- Pro subscription: feature off until explicitly activated, then six Explore
-- and one TikTok discovery for each anchored monthly service period.
select pg_temp.assert_fails($s$select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000004','400','400','com.simonsoloman.bilu.pro.annual','Production',now(),now(),now()+interval '1 year')$s$, 'pro disabled initially');
select pg_temp.assert_true((select period_start = '2025-02-28 12:00Z' and period_end = '2025-03-31 12:00Z' from public.purchase_anchored_month('2025-01-31 12:00Z','2025-03-01Z')), 'Jan31 anchor does not drift after February');
select pg_temp.assert_true((select period_start = '2024-02-29 12:00Z' and period_end = '2024-03-31 12:00Z' from public.purchase_anchored_month('2024-01-31 12:00Z','2024-03-01Z')), 'leap year anchor');
update public.purchase_wallet_configuration set pro_enabled = true;
select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000004','400','400','com.simonsoloman.bilu.pro.annual','Production',now(),now()-interval '45 days',now()+interval '320 days');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000004')->'included' = '{"explore":6,"tiktok":1}'::jsonb, 'pro monthly service allowance');
select pg_temp.assert_true((select period_end - period_start <= interval '31 days' from public.purchase_current_period('aaaaaaaa-0000-0000-0000-000000000004')), 'annual pro has a monthly service period');
update public.purchase_wallet_configuration set commerce_enabled = false, pro_enabled = false;
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000004')->>'plan' = 'pro', 'sales pause retains existing paid service entitlement');
select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000004','401','400','com.simonsoloman.bilu.pro.annual','Production',now(),now(),now()+interval '1 year');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000004')->>'plan' = 'pro', 'known subscription renewals reconcile while sales are paused');
select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000004','401','400','com.simonsoloman.bilu.pro.annual','Production',now(),now(),now()+interval '1 year',now());
select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000004','aaaaaaaa-0000-0000-0000-000000000004','400','400','com.simonsoloman.bilu.pro.annual','Production',now(),now()-interval '45 days',now()+interval '320 days',now());
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000004')->>'plan' = 'free', 'revoked pro falls back to free');

-- Existing recovery and refunds remain available with new sales disabled.
update public.purchase_wallet_configuration set commerce_enabled = false;
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','explore','read')->'result' is not null, 'paused commerce retains result recovery');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '200', now());
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000001')->'purchased' = '{"explore":0,"tiktok":0}'::jsonb, 'paused commerce processes refunds');
select pg_temp.assert_fails($s$select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001',gen_random_uuid(),'explore','reserve')$s$, 'paused commerce denies fresh reservations');
update public.purchase_discoveries set result_expires_at = now() - interval '1 second' where discovery_id = 'bbbbbbbb-0000-0000-0000-000000000001';
select public.purchase_wallet_maintenance();
select pg_temp.assert_true((select result is null from public.purchase_discoveries where discovery_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'result payload purged after24h');
select pg_temp.assert_fails($s$select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','explore','commit',to_jsonb(repeat('x',524289)))$s$, 'oversized result rejected');

-- Schema authorization: clients cannot self-grant, spend, inspect, or alter flags.
select pg_temp.assert_true(not has_function_privilege('authenticated','public.purchase_wallet_snapshot(uuid)','EXECUTE'), 'no authenticated RPC access');
select pg_temp.assert_true(not has_function_privilege('anon','public.apple_apply_transaction(uuid,uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,timestamptz,uuid,text)','EXECUTE'), 'no anonymous grant RPC access');
select pg_temp.assert_true(not has_table_privilege('authenticated','public.purchase_credit_grants','SELECT,UPDATE,INSERT,DELETE'), 'client cannot access grants');
select pg_temp.assert_true((select bool_and(relrowsecurity) from pg_class where relnamespace = 'public'::regnamespace and relname like 'purchase_%' and relkind = 'r'), 'RLS enabled on every purchase table');
select pg_temp.assert_true(has_function_privilege('service_role','public.purchase_discovery(uuid,uuid,text,text,jsonb)','EXECUTE'), 'server RPC access');

-- A deployment switch cannot turn Sandbox balances, allowances, or jobs into
-- Production credit. Returning to the original environment preserves recovery.
insert into auth.users(id,is_anonymous) values('aaaaaaaa-0000-0000-0000-000000000005',false);
update public.purchase_wallet_configuration set commerce_enabled = true, apple_environment = 'Sandbox';
select public.apple_apply_transaction('aaaaaaaa-0000-0000-0000-000000000005','aaaaaaaa-0000-0000-0000-000000000005','800','800','com.simonsoloman.bilu.discovery_pass','Sandbox',now(),now()-interval '1 day');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000001','explore','reserve');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000001','explore','commit','{"fixture":"sandbox"}');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000002','explore','reserve');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000003','explore','reserve');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000004','explore','reserve');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'purchased' = '{"explore":2,"tiktok":1}'::jsonb, 'Sandbox grant reservations debit only Sandbox');
update public.purchase_wallet_configuration set apple_environment = 'Production';
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'purchased' = '{"explore":0,"tiktok":0}'::jsonb, 'Sandbox credit is hidden in Production snapshot');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'included' = '{"explore":2,"tiktok":1}'::jsonb, 'included usage also remains environment isolated');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000001','explore','read')->>'status' = 'environment_mismatch', 'Sandbox result cannot be read as Production');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000003','explore','commit','{}')->>'status' = 'environment_mismatch', 'pending Sandbox work cannot commit as Production');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000003','explore','reserve')->>'status' = 'environment_mismatch', 'Sandbox ID cannot reacquire in Production');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000004','explore','release');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000002','explore','release');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'purchased' = '{"explore":0,"tiktok":0}'::jsonb, 'old worker release never deposits Sandbox credit into Production');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'included' = '{"explore":2,"tiktok":1}'::jsonb, 'old worker release never alters Production period');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000005','explore','reserve');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000005','explore','commit','{}');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000006','explore','reserve');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000006','explore','commit','{}');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000007','explore','reserve')->>'status' = 'exhausted', 'Production cannot spend available Sandbox credits');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000005','800');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000005','801');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000007','explore','reserve')->>'source' = 'purchased', 'Production spends its own verified grant');
select public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000007','explore','commit','{}');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'purchased' = '{"explore":7,"tiktok":2}'::jsonb, 'Production balances do not sum Sandbox grants');
update public.purchase_wallet_configuration set apple_environment = 'Sandbox';
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'purchased' = '{"explore":3,"tiktok":1}'::jsonb, 'Sandbox balance survives isolated Production spending');
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'included' = '{"explore":1,"tiktok":1}'::jsonb, 'released Sandbox included credit returns to its own period');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000001','explore','read')->'result' = '{"fixture":"sandbox"}'::jsonb, 'owned result recovers in original environment');
select pg_temp.assert_true(public.purchase_discovery('aaaaaaaa-0000-0000-0000-000000000005','eeeeeeee-0000-4000-8000-000000000003','explore','commit','{}')->>'status' = 'committed', 'unexpired pending work completes in original environment');
update public.purchase_wallet_configuration set apple_environment = 'Production';
select pg_temp.assert_true(public.purchase_wallet_snapshot('aaaaaaaa-0000-0000-0000-000000000005')->'purchased' = '{"explore":7,"tiktok":2}'::jsonb, 'Sandbox completion cannot change Production balance');

-- Account deletion retains transaction tombstones; signed refund still records.
delete from auth.users where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select pg_temp.assert_true(public.apple_transaction_owner('100','Production') = 'aaaaaaaa-0000-0000-0000-000000000001'::uuid, 'deleted account retains ownership tombstone');
select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000001', '200', now());
select pg_temp.assert_fails($s$select pg_temp.buy('aaaaaaaa-0000-0000-0000-000000000002', '200')$s$, 'deleted account purchase cannot transfer');
rollback;
