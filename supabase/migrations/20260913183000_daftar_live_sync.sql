-- Automatic, tenant-scoped Daftar Qarz -> Zhirox synchronization.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.daftar_sync_sources (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  legacy_user_id bigint not null,
  source_name text not null default 'Daftar Qarz',
  source_fingerprint text not null,
  api_base_url text not null,
  trigger_secret_hash text not null,
  enabled boolean not null default true,
  last_contact_id bigint not null default 0,
  last_transaction_id bigint not null default 0,
  lease_until timestamptz,
  last_started_at timestamptz,
  last_success_at timestamptz,
  last_status text not null default 'idle'
    check (last_status in ('idle','running','success','failed')),
  last_error text,
  last_result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(admin_id, legacy_user_id)
);

create table if not exists public.daftar_sync_seen (
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  entity_kind text not null
    check (entity_kind in ('customer','debt','payment','payment_allocation','zero_event')),
  source_id text not null,
  target_id uuid,
  payload_hash text,
  created_at timestamptz not null default now(),
  primary key(sync_source_id, entity_kind, source_id)
);

create table if not exists public.daftar_sync_runs (
  id uuid primary key default gen_random_uuid(),
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  status text not null default 'running'
    check (status in ('running','success','failed','skipped')),
  fetched_contacts integer not null default 0,
  fetched_transactions integer not null default 0,
  new_customers integer not null default 0,
  new_debts integer not null default 0,
  new_payment_allocations integer not null default 0,
  new_zero_events integer not null default 0,
  reused_records integer not null default 0,
  error_message text,
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists daftar_sync_seen_target_idx
  on public.daftar_sync_seen(target_id);
create index if not exists daftar_sync_runs_source_started_idx
  on public.daftar_sync_runs(sync_source_id, started_at desc);

alter table public.daftar_sync_sources enable row level security;
alter table public.daftar_sync_seen enable row level security;
alter table public.daftar_sync_runs enable row level security;

revoke all on public.daftar_sync_sources from anon, authenticated;
revoke all on public.daftar_sync_seen from anon, authenticated;
revoke all on public.daftar_sync_runs from anon, authenticated;

create or replace function public.claim_daftar_sync(p_source_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.daftar_sync_sources
  set lease_until = now() + interval '9 minutes',
      last_started_at = now(),
      last_status = 'running',
      last_error = null,
      updated_at = now()
  where id = p_source_id
    and enabled = true
    and (lease_until is null or lease_until < now());
  return found;
end;
$$;

revoke all on function public.claim_daftar_sync(uuid) from public, anon, authenticated;
grant execute on function public.claim_daftar_sync(uuid) to service_role;

do $$
declare
  v_admin_id uuid;
  v_sync_source_id uuid;
  v_trigger_secret text;
  v_contact_checkpoint bigint;
  v_transaction_checkpoint bigint;
begin
  select id into v_admin_id
  from public.profiles
  where role = 'admin'
    and market_name = 'سوپەرمارکێتی کانی چنار'
  order by created_at
  limit 1;

  if v_admin_id is null then
    raise exception 'Kanichnar admin account was not found';
  end if;

  select coalesce(max(source_id::bigint), 0) into v_contact_checkpoint
  from public.legacy_import_links
  where admin_id = v_admin_id
    and entity_kind = 'customer'
    and source_id ~ '^[0-9]+$';

  select coalesce(max(substring(source_id from '^[0-9]+')::bigint), 0)
    into v_transaction_checkpoint
  from public.legacy_import_links
  where admin_id = v_admin_id
    and entity_kind in ('debt','payment')
    and source_id ~ '^[0-9]+';

  v_trigger_secret := encode(gen_random_bytes(32), 'hex');

  insert into public.daftar_sync_sources(
    admin_id, legacy_user_id, source_name, source_fingerprint, api_base_url,
    trigger_secret_hash, last_contact_id, last_transaction_id
  ) values (
    v_admin_id, 28, 'Daftar Qarz / account 28', 'daftar-live-account-28-v1',
    'https://api-daftar-qarz.kasbkar.net/api/v1',
    encode(digest(v_trigger_secret, 'sha256'), 'hex'),
    v_contact_checkpoint, v_transaction_checkpoint
  )
  on conflict(admin_id, legacy_user_id) do update set
    enabled = true,
    api_base_url = excluded.api_base_url,
    updated_at = now()
  returning id into v_sync_source_id;

  if not exists(select 1 from vault.decrypted_secrets where name = 'daftar_sync_account_28_trigger') then
    perform vault.create_secret(v_trigger_secret, 'daftar_sync_account_28_trigger');
  else
    select decrypted_secret into v_trigger_secret
    from vault.decrypted_secrets
    where name = 'daftar_sync_account_28_trigger'
    limit 1;
  end if;

  update public.daftar_sync_sources
  set trigger_secret_hash = encode(digest(v_trigger_secret, 'sha256'), 'hex')
  where id = v_sync_source_id;

  insert into public.daftar_sync_seen(sync_source_id, entity_kind, source_id, target_id)
  select v_sync_source_id,
         case l.entity_kind when 'payment' then 'payment_allocation' else l.entity_kind end,
         l.source_id,
         l.target_id
  from public.legacy_import_links l
  where l.admin_id = v_admin_id
  on conflict do nothing;
end;
$$;

select cron.schedule(
  'daftar-live-sync-account-28',
  '*/10 * * * *',
  $cron$
  select net.http_post(
    url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-daftar-sync-secret', (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'daftar_sync_account_28_trigger' limit 1
      )
    ),
    body := jsonb_build_object(
      'source_id', (
        select id from public.daftar_sync_sources
        where legacy_user_id = 28 and enabled = true limit 1
      )
    ),
    timeout_milliseconds := 120000
  );
  $cron$
);
