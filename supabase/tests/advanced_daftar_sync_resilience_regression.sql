begin;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'daftar_sync_sources'
      and column_name = 'consecutive_failures'
  ) then raise exception 'missing daftar sync resilience columns'; end if;

  if not exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = 'daftar_sync_dead_letters'
      and c.relrowsecurity
  ) then raise exception 'dead-letter table must exist with RLS'; end if;

  if has_table_privilege('anon', 'public.daftar_sync_dead_letters', 'select')
     or has_table_privilege('authenticated', 'public.daftar_sync_dead_letters', 'select') then
    raise exception 'dead letters must not be client-readable';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.record_daftar_sync_failure(uuid,text,text,text,text,jsonb)',
    'execute'
  ) then raise exception 'failure recorder must be service-role only'; end if;

  if not has_function_privilege(
    'authenticated', 'public.get_my_daftar_sync_health()', 'execute'
  ) then raise exception 'tenant health RPC must be authenticated'; end if;

  if not exists (
    select 1 from cron.job
    where jobname = 'daftar-live-sync-account-28'
      and schedule = '* * * * *'
      and active
      and command like '%daftar-sync-gateway%'
  ) then raise exception 'near-live gateway cron is not active'; end if;
end;
$$;

rollback;
