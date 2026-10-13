-- Verified late notifications may update a deleted owner's replay tombstones,
-- but can never restore its wallet, transfer ownership, or bind a new owner.
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
insert into auth.users(id,is_anonymous) values
  ('eeeeeeee-0000-4000-8000-000000000001',false),
  ('eeeeeeee-0000-4000-8000-000000000002',false);
update public.purchase_wallet_configuration set commerce_enabled = true, pro_enabled = true;

create function pg_temp.pass_notice(p_notice uuid, p_signed timestamptz, p_revoked timestamptz default null)
returns jsonb language sql as $$
  select public.apple_apply_transaction(
    'eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000001',
    '880001','880001','com.simonsoloman.bilu.discovery_pass','Production',
    p_signed,'2020-01-01Z',null,p_revoked,p_notice,
    case when p_revoked is null then 'ONE_TIME_CHARGE' else 'REFUND' end);
$$;
select pg_temp.pass_notice(null, now()-interval '3 hours');
select public.apple_apply_transaction(
  'eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000001',
  '880002','880002','com.simonsoloman.bilu.pro.monthly','Production',
  now()-interval '3 hours','2020-01-01Z','2020-02-01Z');
delete from auth.users where id = 'eeeeeeee-0000-4000-8000-000000000001';
update public.purchase_wallet_configuration set commerce_enabled = false, pro_enabled = false;

-- This previously raised durable-account-required and made Apple retry forever.
select pg_temp.assert_true(pg_temp.pass_notice('ffffffff-0000-4000-8000-000000000001',now()-interval '1 hour')->>'accountId'
  = 'eeeeeeee-0000-4000-8000-000000000001', 'late signed charge is acknowledged for its deleted owner');
select pg_temp.assert_true((select signed_at = now()-interval '1 hour' from public.purchase_apple_transactions
  where environment = 'Production' and transaction_id = '880001'), 'late charge updates signed state');
select pg_temp.assert_true(not (pg_temp.pass_notice('ffffffff-0000-4000-8000-000000000001',now()-interval '1 hour')->>'applied')::boolean,
  'notification UUID replay stays idempotent after deletion');

-- New renewal transaction IDs are legitimate on an already owned subscription.
select public.apple_apply_transaction(
  'eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000001',
  '880003','880002','com.simonsoloman.bilu.pro.monthly','Production',
  now()-interval '1 hour','2020-02-01Z','2020-03-01Z',null,
  'ffffffff-0000-4000-8000-000000000002','EXPIRED');
select public.apple_apply_transaction(
  'eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000001',
  '880003','880002','com.simonsoloman.bilu.pro.monthly','Production',
  now()-interval '2 hours','2020-02-01Z','2020-04-01Z',null,
  'ffffffff-0000-4000-8000-000000000003','DID_RENEW');
select pg_temp.assert_true((select signed_at = now()-interval '1 hour' and expires_at = '2020-03-01Z'::timestamptz
  from public.purchase_apple_transactions where environment = 'Production' and transaction_id = '880003'),
  'older renewal cannot replace the latest deleted-owner state');

select pg_temp.pass_notice('ffffffff-0000-4000-8000-000000000004',now()-interval '30 minutes',now()-interval '45 minutes');
select pg_temp.pass_notice('ffffffff-0000-4000-8000-000000000005',now());
select pg_temp.assert_true((select revoked_at = now()-interval '45 minutes' and signed_at = now()
  from public.purchase_apple_transactions where environment = 'Production' and transaction_id = '880001'),
  'a later non-revocation event cannot erase a refund tombstone');
select pg_temp.assert_true(not exists(select 1 from public.purchase_credit_grants
  where user_id = 'eeeeeeee-0000-4000-8000-000000000001'), 'no late event recreates deleted credit');
select pg_temp.assert_true(not exists(select 1 from auth.users
  where id = 'eeeeeeee-0000-4000-8000-000000000001'), 'no late event recreates the deleted account');
select pg_temp.assert_true(public.apple_transaction_owner('880001','Production') = 'eeeeeeee-0000-4000-8000-000000000001'::uuid,
  'original owner is immutable after deletion');

select pg_temp.assert_fails($s$select pg_temp.pass_notice(null,now())$s$,
  'an unauthenticated purchase retry cannot substitute for a verified notification after deletion');
select pg_temp.assert_fails($s$select public.apple_apply_transaction(
  'eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000001',
  '880098','880098','com.simonsoloman.bilu.discovery_pass','Production',now(),'2020-01-01Z',null,now())$s$,
  'revocation cannot create an unknown owner for a deleted account');
select pg_temp.assert_fails($s$select public.apple_apply_transaction(
  'eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000001',
  '880099','880099','com.simonsoloman.bilu.discovery_pass','Production',now(),'2020-01-01Z',null,null,
  'ffffffff-0000-4000-8000-000000000006','ONE_TIME_CHARGE')$s$, 'notification cannot establish deleted ownership');
select pg_temp.assert_fails($s$select public.apple_apply_transaction(
  'eeeeeeee-0000-4000-8000-000000000002','eeeeeeee-0000-4000-8000-000000000002',
  '880001','880001','com.simonsoloman.bilu.discovery_pass','Production',now(),'2020-01-01Z',null,null,
  'ffffffff-0000-4000-8000-000000000007','ONE_TIME_CHARGE')$s$, 'deleted transaction cannot transfer to a living account');

-- The exception applies to missing accounts, never to an anonymous identity.
insert into auth.users(id,is_anonymous) values('eeeeeeee-0000-4000-8000-000000000001',true);
select pg_temp.assert_fails($s$select pg_temp.pass_notice('ffffffff-0000-4000-8000-000000000008',now())$s$,
  'anonymous accounts still cannot accept non-revocation notifications');
rollback;
