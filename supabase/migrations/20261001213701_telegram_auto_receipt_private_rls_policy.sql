drop policy if exists telegram_auto_receipt_jobs_deny_client on private.telegram_auto_receipt_jobs;
create policy telegram_auto_receipt_jobs_deny_client
on private.telegram_auto_receipt_jobs
for all
to anon, authenticated
using (false)
with check (false);