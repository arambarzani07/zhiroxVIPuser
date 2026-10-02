drop policy if exists owner_daily_digest_deny_client on private.owner_daily_digest_settings;
create policy owner_daily_digest_deny_client
on private.owner_daily_digest_settings
for all
to anon, authenticated
using (false)
with check (false);
