-- Harden public bootstrap/market RPCs and make service-only RLS intent explicit.

revoke execute on function public.claim_initial_system_owner(text,text)
  from public, anon;
grant execute on function public.claim_initial_system_owner(text,text)
  to authenticated, service_role;

create or replace function public.initial_owner_bootstrap_open()
returns boolean
language sql
security invoker
stable
set search_path = ''
as $function$
  select not exists (
    select 1 from public.profiles where is_system_owner = true
  );
$function$;

revoke all on function public.initial_owner_bootstrap_open() from public;
grant execute on function public.initial_owner_bootstrap_open()
  to anon, authenticated, service_role;

create or replace function public.list_active_markets()
returns table(id uuid, name text, market_name text)
language sql
security invoker
stable
set search_path = ''
as $function$
  select p.id, p.name, p.market_name
  from public.profiles p
  where p.role = 'admin'
    and p.is_system_owner = false
    and p.active = true
    and p.approved = true
    and nullif(trim(p.market_name), '') is not null
    and (p.subscription_end is null or p.subscription_end >= now())
  order by p.created_at desc;
$function$;

revoke all on function public.list_active_markets() from public;
grant execute on function public.list_active_markets()
  to anon, authenticated, service_role;

do $$
declare
  r record;
begin
  for r in
    select n.nspname as schema_name, c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r','p')
      and c.relrowsecurity = true
      and n.nspname in ('public','private')
      and not exists (
        select 1
        from pg_policy p
        where p.polrelid = c.oid
      )
  loop
    execute format(
      'create policy deny_direct_client_access on %I.%I for all to anon, authenticated using (false) with check (false)',
      r.schema_name,
      r.table_name
    );
  end loop;
end $$;
