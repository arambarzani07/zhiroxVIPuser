-- Make Daftar Qarz the read-only source of truth for the linked account.
-- ZHIROX continues to pull Daftar contacts/transactions, but does not dispatch
-- outbound writes back to Daftar from this source.

select set_config('zhirox.daftar_sync_unlock','on',true);

update public.daftar_sync_sources
set
  sync_mode='mirror',
  inbound_sync_enabled=true,
  outbound_sync_enabled=false,
  updated_at=now()
where enabled=true
  and source_name='Daftar Qarz / account 28';

-- Do not call the bidirectional dispatcher here. Runtime jobs are guarded
-- separately; in mirror mode the dispatcher only performs inbound pulls.
