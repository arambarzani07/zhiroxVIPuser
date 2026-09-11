-- Block inactive, unapproved, and expired tenants at the database boundary.
create or replace function private."current_role"()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
  where p.id = auth.uid()
    and p.active = true
    and p.approved = true
    and (
      p.is_system_owner = true
      or (
        tenant.role = 'admin'
        and tenant.active = true
        and tenant.approved = true
        and (tenant.subscription_end is null or tenant.subscription_end >= now())
      )
    )
  limit 1
$$;

create or replace function private.current_admin_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case when p.role = 'admin' then p.id else p.admin_id end
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
  where p.id = auth.uid()
    and p.active = true
    and p.approved = true
    and (
      p.is_system_owner = true
      or (
        tenant.role = 'admin'
        and tenant.active = true
        and tenant.approved = true
        and (tenant.subscription_end is null or tenant.subscription_end >= now())
      )
    )
  limit 1
$$;

-- RLS does not protect TRUNCATE. Financial audit history is read-only to app users.
revoke all privileges on table public.financial_events from anon;
revoke all privileges on table public.financial_events from authenticated;
grant select on table public.financial_events to authenticated;

