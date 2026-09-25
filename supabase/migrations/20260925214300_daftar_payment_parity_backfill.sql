-- Backfill mirror PAYMENT gaps only after the general-ledger accounting and
-- reconciliation functions have been upgraded.

do $backfill$
declare
  r record;
begin
  for r in
    select id
    from public.daftar_sync_sources
    where enabled=true
      and sync_mode='zhirox_primary'
      and inbound_sync_enabled=true
    order by created_at
  loop
    perform private.backfill_missing_daftar_general_payments(r.id);
  end loop;

  perform private.reconcile_daftar_sync_sources();
end
$backfill$;
