-- Resolve transient Daftar sync dead letters only after a later verified recovery.

create or replace function public.resolve_daftar_recovered_dead_letters(
  p_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reconciliation_status text;
  v_last_reconciled_at timestamptz;
  v_cutover_status text;
  v_cutover_mismatches bigint;
  v_last_cutover_at timestamptz;
  v_reconciliation_resolved integer := 0;
  v_cutover_resolved integer := 0;
begin
  select
    s.reconciliation_status,
    s.last_reconciled_at,
    s.cutover_rehearsal_status,
    coalesce(s.cutover_rehearsal_mismatches, 0),
    s.last_cutover_rehearsal_at
  into
    v_reconciliation_status,
    v_last_reconciled_at,
    v_cutover_status,
    v_cutover_mismatches,
    v_last_cutover_at
  from public.daftar_sync_sources s
  where s.id = p_source_id;

  if not found then
    raise exception 'sync_source_not_found' using errcode = 'P0002';
  end if;

  if v_reconciliation_status = 'clean' and v_last_reconciled_at is not null then
    update public.daftar_sync_dead_letters d
    set resolved_at = now(),
        resolution_note = 'resolved_after_clean_reconciliation'
    where d.sync_source_id = p_source_id
      and d.resolved_at is null
      and d.error_code = 'reconciliation_failed'
      and d.last_seen_at < v_last_reconciled_at;
    get diagnostics v_reconciliation_resolved = row_count;
  end if;

  if v_cutover_status = 'pass'
     and v_cutover_mismatches = 0
     and v_last_cutover_at is not null then
    update public.daftar_sync_dead_letters d
    set resolved_at = now(),
        resolution_note = 'resolved_after_passing_cutover_rehearsal'
    where d.sync_source_id = p_source_id
      and d.resolved_at is null
      and d.error_code = 'cutover_rehearsal_failed'
      and d.last_seen_at < v_last_cutover_at;
    get diagnostics v_cutover_resolved = row_count;
  end if;

  return jsonb_build_object(
    'source_id', p_source_id,
    'reconciliation_resolved', v_reconciliation_resolved,
    'cutover_resolved', v_cutover_resolved,
    'reconciliation_status', v_reconciliation_status,
    'cutover_status', v_cutover_status,
    'cutover_mismatches', v_cutover_mismatches
  );
end;
$function$;

revoke all on function public.resolve_daftar_recovered_dead_letters(uuid)
  from public, anon, authenticated;
grant execute on function public.resolve_daftar_recovered_dead_letters(uuid)
  to service_role;

do $recover_existing$
declare
  r record;
begin
  for r in select id from public.daftar_sync_sources loop
    perform public.resolve_daftar_recovered_dead_letters(r.id);
  end loop;
end
$recover_existing$;
