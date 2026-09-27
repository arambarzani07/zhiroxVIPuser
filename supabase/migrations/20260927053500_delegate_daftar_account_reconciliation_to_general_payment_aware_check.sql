create or replace function public.reconcile_daftar_account_28(p_source_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.daftar_sync_sources s
    where s.id = p_source_id and s.legacy_user_id = 28
      and s.source_fingerprint = 'daftar-live-account-28-v1' and s.enabled
  ) then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;
  return private.reconcile_daftar_source(p_source_id);
end;
$$;
revoke all on function public.reconcile_daftar_account_28(uuid) from public, anon, authenticated;
grant execute on function public.reconcile_daftar_account_28(uuid) to service_role;