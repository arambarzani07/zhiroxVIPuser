-- Receipt Studio governance:
-- * preserve every saved template version as an immutable tenant-scoped snapshot
-- * allow the market admin to choose the prefix for future receipt numbers
-- * prevent deleting the active settings row (restore is forward-only)

create table if not exists public.receipt_template_versions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  version_no integer not null check (version_no > 0),
  settings_snapshot jsonb not null check (jsonb_typeof(settings_snapshot) = 'object'),
  change_kind text not null default 'save'
    check (change_kind in ('initial','save','restore')),
  restored_from_version integer,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (admin_id, version_no)
);

create index if not exists receipt_template_versions_admin_created_idx
  on public.receipt_template_versions (admin_id, created_at desc);

alter table public.receipt_template_versions enable row level security;

revoke all on table public.receipt_template_versions from public, anon, authenticated;
grant select on table public.receipt_template_versions to authenticated;
grant all on table public.receipt_template_versions to service_role;

drop policy if exists receipt_template_versions_select_tenant
  on public.receipt_template_versions;
create policy receipt_template_versions_select_tenant
  on public.receipt_template_versions
  for select
  to authenticated
  using (
    admin_id = private.current_admin_id()
    and private.current_role() = 'admin'
    and (select auth.uid()) = admin_id
  );

create or replace function private.capture_receipt_template_version()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_snapshot jsonb;
  v_kind text := 'save';
  v_restored_from integer;
begin
  v_snapshot := to_jsonb(new) - 'created_at' - 'updated_at';
  if tg_op = 'INSERT' then
    v_kind := 'initial';
  elsif coalesce(current_setting('zhirox.receipt_restore_from', true), '') <> '' then
    v_kind := 'restore';
    v_restored_from := current_setting('zhirox.receipt_restore_from', true)::integer;
  end if;

  insert into public.receipt_template_versions (
    admin_id,
    version_no,
    settings_snapshot,
    change_kind,
    restored_from_version,
    created_by
  ) values (
    new.admin_id,
    new.template_version,
    v_snapshot,
    v_kind,
    v_restored_from,
    (select auth.uid())
  )
  on conflict (admin_id, version_no) do nothing;

  return new;
end;
$function$;

drop trigger if exists trg_capture_receipt_template_version
  on public.market_receipt_settings;
create trigger trg_capture_receipt_template_version
after insert or update on public.market_receipt_settings
for each row execute function private.capture_receipt_template_version();

-- Seed history for tenants that already configured receipts before this feature.
insert into public.receipt_template_versions (
  admin_id,
  version_no,
  settings_snapshot,
  change_kind,
  created_by,
  created_at
)
select
  settings.admin_id,
  settings.template_version,
  to_jsonb(settings) - 'created_at' - 'updated_at',
  'initial',
  settings.admin_id,
  settings.updated_at
from public.market_receipt_settings settings
on conflict (admin_id, version_no) do nothing;

-- The active configuration must always exist. Admins restore an older snapshot
-- by saving it as a new version; history and issued receipt snapshots stay intact.
revoke delete on table public.market_receipt_settings from authenticated;
drop policy if exists market_receipt_settings_delete_admin
  on public.market_receipt_settings;

-- Prefixes affect future numbers only. The full generated number remains
-- server-owned and cannot be supplied or edited by the client.
create or replace function private.assign_receipt_identity()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $function$
declare
  v_year integer := extract(year from current_timestamp)::integer;
  v_number bigint;
  v_prefix text;
begin
  insert into private.receipt_counters (admin_id, receipt_year, next_number)
  values (new.admin_id, v_year, 2)
  on conflict (admin_id, receipt_year)
  do update set next_number = private.receipt_counters.next_number + 1
  returning next_number - 1 into v_number;

  v_prefix := upper(coalesce(
    nullif(btrim(new.settings_snapshot ->> 'receipt_prefix'), ''),
    'INV'
  ));
  if v_prefix !~ '^[A-Z0-9_-]{1,12}$' then
    v_prefix := 'INV';
  end if;

  -- Always overwrite client input: receipt identity is database-owned.
  new.receipt_number :=
    v_prefix || '-' || v_year::text || '-' || lpad(v_number::text, 6, '0');
  return new;
end;
$function$;

drop trigger if exists trg_receipt_documents_identity on public.receipt_documents;
create trigger trg_receipt_documents_identity
before insert on public.receipt_documents
for each row execute function private.assign_receipt_identity();

revoke all on function private.capture_receipt_template_version() from public, anon, authenticated;
revoke all on function private.assign_receipt_identity() from public, anon, authenticated;
