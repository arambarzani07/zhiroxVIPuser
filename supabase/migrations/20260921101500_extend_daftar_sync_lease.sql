-- A full Daftar snapshot plus reconciliation can legitimately exceed the old
-- three-minute lease. Keep a second cron invocation from overlapping it.
create or replace function public.claim_daftar_sync(p_source_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.daftar_sync_sources
  set lease_until = now() + interval '10 minutes',
      last_started_at = now(),
      last_heartbeat_at = now(),
      last_status = 'running',
      last_error = null,
      updated_at = now()
  where id = p_source_id
    and enabled = true
    and (lease_until is null or lease_until < now())
    and (next_retry_at is null or next_retry_at <= now())
    and (circuit_open_until is null or circuit_open_until <= now());
  return found;
end;
$$;

revoke all on function public.claim_daftar_sync(uuid) from public, anon, authenticated;
grant execute on function public.claim_daftar_sync(uuid) to service_role;
