create policy "daftar_sync_sources_no_client_access"
on public.daftar_sync_sources
for all
to anon, authenticated
using (false)
with check (false);

create policy "daftar_sync_seen_no_client_access"
on public.daftar_sync_seen
for all
to anon, authenticated
using (false)
with check (false);

create policy "daftar_sync_runs_no_client_access"
on public.daftar_sync_runs
for all
to anon, authenticated
using (false)
with check (false);
