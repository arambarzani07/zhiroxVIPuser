-- ZHIROX -> Daftar Qarz outbound create queue.
-- Disabled by default until the Daftar write contract and account credential
-- are verified server-side. No Flutter client receives Daftar credentials.

alter table public.daftar_sync_sources
  add column if not exists outbound_sync_enabled boolean not null default false,
  add column if not exists outbound_write_contract_status text not null default 'unverified';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='daftar_sync_sources_outbound_write_contract_status_check'
      and conrelid='public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_outbound_write_contract_status_check
      check (outbound_write_contract_status in ('unverified','verified','blocked'));
  end if;
end;
$$;

create table if not exists public.daftar_outbound_events (
  id uuid primary key default gen_random_uuid(),
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  entity_kind text not null check (entity_kind in ('customer','debt','payment')),
  entity_id uuid not null,
  operation text not null default 'create' check (operation in ('create')),
  idempotency_key text not null unique,
  status text not null default 'pending'
    check (status in ('pending','processing','sent','skipped','failed','blocked')),
  remote_id text,
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default (now() + interval '2 minutes'),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists daftar_outbound_events_pending_idx
  on public.daftar_outbound_events(status, next_attempt_at, created_at)
  where status in ('pending','failed');

create index if not exists daftar_outbound_events_entity_idx
  on public.daftar_outbound_events(sync_source_id, entity_kind, entity_id);

alter table public.daftar_outbound_events enable row level security;
revoke all on public.daftar_outbound_events from public, anon, authenticated;
grant select, insert, update, delete on public.daftar_outbound_events to service_role;

create or replace function public.enqueue_daftar_outbound_create()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id uuid;
  v_entity_kind text;
  v_entity_id uuid;
  v_source_id uuid;
begin
  if tg_table_name = 'profiles' then
    if new.role <> 'customer' or new.admin_id is null then
      return new;
    end if;
    v_admin_id := new.admin_id;
    v_entity_kind := 'customer';
    v_entity_id := new.id;
  elsif tg_table_name = 'debts' then
    select p.admin_id into v_admin_id
    from public.profiles p
    where p.id = new.customer_id
      and p.role = 'customer';
    if v_admin_id is null then return new; end if;
    v_entity_kind := 'debt';
    v_entity_id := new.id;
  elsif tg_table_name = 'payments' then
    select p.admin_id into v_admin_id
    from public.debts d
    join public.profiles p on p.id=d.customer_id
    where d.id = new.debt_id
      and p.role='customer';
    if v_admin_id is null then return new; end if;
    v_entity_kind := 'payment';
    v_entity_id := new.id;
  else
    return new;
  end if;

  select s.id into v_source_id
  from public.daftar_sync_sources s
  where s.admin_id=v_admin_id
    and s.legacy_user_id=28
    and s.source_fingerprint='daftar-live-account-28-v1'
    and s.sync_mode='zhirox_primary'
    and s.outbound_sync_enabled=true
  limit 1;

  if v_source_id is null then return new; end if;

  -- Fast-path echo prevention. The worker repeats this check immediately
  -- before any network write to cover the short race before inbound links exist.
  if exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id=v_admin_id
      and l.source_fingerprint='daftar-live-account-28-v1'
      and l.entity_kind=v_entity_kind
      and l.target_id=v_entity_id
  ) then
    return new;
  end if;

  insert into public.daftar_outbound_events(
    sync_source_id,
    entity_kind,
    entity_id,
    operation,
    idempotency_key
  ) values (
    v_source_id,
    v_entity_kind,
    v_entity_id,
    'create',
    'zhirox:' || v_entity_kind || ':' || v_entity_id::text || ':create'
  )
  on conflict (idempotency_key) do nothing;

  return new;
end;
$$;

revoke all on function public.enqueue_daftar_outbound_create()
  from public, anon, authenticated;

drop trigger if exists daftar_outbound_profile_create on public.profiles;
create trigger daftar_outbound_profile_create
after insert on public.profiles
for each row execute function public.enqueue_daftar_outbound_create();

drop trigger if exists daftar_outbound_debt_create on public.debts;
create trigger daftar_outbound_debt_create
after insert on public.debts
for each row execute function public.enqueue_daftar_outbound_create();

drop trigger if exists daftar_outbound_payment_create on public.payments;
create trigger daftar_outbound_payment_create
after insert on public.payments
for each row execute function public.enqueue_daftar_outbound_create();
