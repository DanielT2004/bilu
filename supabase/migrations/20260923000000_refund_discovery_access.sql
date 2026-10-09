-- Restore a discovery allowance when the paid upstream request fails after the
-- allowance was atomically reserved. Only service-role Edge Functions may call
-- this helper.

create or replace function public.refund_discovery_access(
  p_user_id uuid,
  p_access_source text,
  p_reward_token uuid default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today date := (clock_timestamp() at time zone 'utc')::date;
begin
  if p_user_id is null or p_access_source not in ('free', 'rewarded') then
    return false;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('discovery:' || p_user_id::text, 0));

  if p_access_source = 'free' then
    update public.free_discovery_usage
      set units = greatest(0, units - 1),
          updated_at = now()
    where user_id = p_user_id
      and usage_day = v_today
      and units > 0;
    return found;
  end if;

  if p_reward_token is null then
    return false;
  end if;

  update public.rewarded_ad_sessions
    set consumed_at = null
  where token = p_reward_token
    and user_id = p_user_id
    and verified_at is not null
    and consumed_at is not null
    and expires_at > now();
  return found;
end;
$$;

revoke all on function public.refund_discovery_access(uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function public.refund_discovery_access(uuid, text, uuid)
  to service_role;
