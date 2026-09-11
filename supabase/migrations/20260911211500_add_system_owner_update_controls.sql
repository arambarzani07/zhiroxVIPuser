create table if not exists public.app_update_settings (
  edition text primary key check (edition in ('owner','user')),
  mandatory boolean not null default false,
  notes text not null default '',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

insert into public.app_update_settings (edition, mandatory, notes)
values ('owner', false, ''), ('user', false, '')
on conflict (edition) do nothing;

alter table public.app_update_settings enable row level security;

drop policy if exists app_update_settings_read on public.app_update_settings;
create policy app_update_settings_read
on public.app_update_settings
for select
to anon, authenticated
using (true);

drop policy if exists app_update_settings_owner_update on public.app_update_settings;
create policy app_update_settings_owner_update
on public.app_update_settings
for update
to authenticated
using (
  exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  )
)
with check (
  exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  )
);

revoke all privileges on table public.app_update_settings from anon, authenticated;
grant select on table public.app_update_settings to anon, authenticated;
grant update (mandatory, notes, updated_at, updated_by)
  on table public.app_update_settings to authenticated;
grant select, insert, update, delete
  on table public.app_update_settings to service_role;
