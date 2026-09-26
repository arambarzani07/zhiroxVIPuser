-- Show verified Daftar totals for the account-28 dashboard while the
-- historical transaction ledger is still being materialized. Local recent
-- activity remains local; other tenants cannot access these totals.
create or replace function private.get_daftar_mirror_dashboard_totals(p_admin_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$
  select coalesce((
    select jsonb_build_object(
      'total_customers',s.official_total_customers,
      'total_debt',s.official_total_loan_iqd,
      'total_payments',s.official_total_payment_iqd,
      'total_remaining',greatest(s.official_balance_iqd,0),
      'total_debt_usd',s.official_total_loan_usd,
      'total_payments_usd',s.official_total_payment_usd,
      'total_remaining_usd',greatest(s.official_balance_usd,0)
    )
    from public.daftar_sync_sources s
    where p_admin_id=(select auth.uid())
      and s.admin_id=p_admin_id
      and s.id='ef8dc873-6e48-4caf-9feb-22d53b5aeb24'::uuid
      and s.legacy_user_id=28
      and s.source_fingerprint='daftar-live-account-28-v1'
      and s.enabled=true and s.sync_mode='mirror'
      and s.official_total_customers=519
      and s.official_totals_at>=now()-interval '5 minutes'
    limit 1
  ),'{}'::jsonb)
$$;
revoke all on function private.get_daftar_mirror_dashboard_totals(uuid) from public,anon;
grant execute on function private.get_daftar_mirror_dashboard_totals(uuid) to authenticated,service_role;

do $fix$
declare v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_admin_dashboard_snapshot';
  if v_def is null then raise exception 'admin_dashboard_missing'; end if;
  if position('  return v_result || private.get_daftar_mirror_dashboard_totals(v_admin_id);' in v_def)>0 then
    return;
  end if;
  if position('  return v_result;' in v_def)=0 then
    raise exception 'unexpected_admin_dashboard_definition';
  end if;
  execute replace(v_def,'  return v_result;',
    '  return v_result || private.get_daftar_mirror_dashboard_totals(v_admin_id);');
end $fix$;
