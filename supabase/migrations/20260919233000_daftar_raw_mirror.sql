-- Durable raw mirror for the transitional Daftar Qarz -> ZHIROX phase.
-- Daftar Qarz remains the temporary upstream source; ZHIROX keeps a complete
-- raw copy so it can later become the independent source of truth.

alter table public.daftar_sync_sources
  add column if not exists sync_mode text not null default 'mirror',
  add column if not exists mirror_bootstrapped_at timestamptz,
  add column if not exists mirror_last_full_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_sync_mode_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_sync_mode_check
      check (sync_mode in ('mirror','zhirox_primary'));
  end if;
end;
$$;

update public.daftar_sync_sources
set sync_mode = 'mirror'
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1';

create table if not exists public.daftar_mirror_contacts (
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete restrict,
  source_id text not null,
  payload jsonb not null,
  payload_hash text not null,
  first_mirrored_at timestamptz not null default now(),
  last_mirrored_at timestamptz not null default now(),
  primary key (sync_source_id, source_id)
);

create table if not exists public.daftar_mirror_transactions (
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete restrict,
  source_id text not null,
  payload jsonb not null,
  payload_hash text not null,
  first_mirrored_at timestamptz not null default now(),
  last_mirrored_at timestamptz not null default now(),
  primary key (sync_source_id, source_id)
);

create index if not exists daftar_mirror_contacts_last_idx
  on public.daftar_mirror_contacts(sync_source_id, last_mirrored_at desc);
create index if not exists daftar_mirror_transactions_last_idx
  on public.daftar_mirror_transactions(sync_source_id, last_mirrored_at desc);

alter table public.daftar_mirror_contacts enable row level security;
alter table public.daftar_mirror_transactions enable row level security;

revoke all on public.daftar_mirror_contacts from public, anon, authenticated;
revoke all on public.daftar_mirror_transactions from public, anon, authenticated;
grant all on public.daftar_mirror_contacts to service_role;
grant all on public.daftar_mirror_transactions to service_role;

create or replace function public.get_my_daftar_mirror_status()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_build_object(
      'sync_mode', s.sync_mode,
      'mirror_bootstrapped_at', s.mirror_bootstrapped_at,
      'mirror_last_full_at', s.mirror_last_full_at,
      'contacts_count', (
        select count(*)
        from public.daftar_mirror_contacts c
        where c.sync_source_id = s.id
      ),
      'transactions_count', (
        select count(*)
        from public.daftar_mirror_transactions t
        where t.sync_source_id = s.id
      ),
      'last_success_at', s.last_success_at,
      'health_status', s.health_status,
      'consecutive_failures', s.consecutive_failures,
      'cutover_ready',
        s.mirror_bootstrapped_at is not null
        and s.health_status = 'healthy'
        and s.consecutive_failures = 0
        and s.last_success_at is not null
        and s.last_success_at >= now() - interval '5 minutes'
    ),
    '{}'::jsonb
  )
  from public.daftar_sync_sources s
  where (select auth.uid()) is not null
    and s.admin_id = (select auth.uid())
    and s.legacy_user_id = 28
    and s.source_fingerprint = 'daftar-live-account-28-v1'
  order by s.created_at
  limit 1;
$$;

revoke all on function public.get_my_daftar_mirror_status()
  from public, anon;
grant execute on function public.get_my_daftar_mirror_status()
  to authenticated;
