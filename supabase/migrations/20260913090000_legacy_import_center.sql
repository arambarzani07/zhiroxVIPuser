-- Zhirox legacy import center (tenant-scoped, resumable, auditable)

alter table public.profiles
  add column if not exists can_import_data boolean not null default false;

create table if not exists public.legacy_import_jobs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  source_fingerprint text not null,
  source_name text not null default '',
  source_market_name text not null default '',
  status text not null default 'pending'
    check (status in ('pending','running','completed','failed','cancelled')),
  expected_customers integer not null default 0,
  expected_debts integer not null default 0,
  expected_payments integer not null default 0,
  expected_balance_iqd numeric(18,2) not null default 0,
  imported_customers integer not null default 0,
  imported_debts integer not null default 0,
  imported_payments integer not null default 0,
  verified_balance_iqd numeric(18,2),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(admin_id, source_fingerprint)
);

create table if not exists public.legacy_import_links (
  admin_id uuid not null references public.profiles(id) on delete cascade,
  source_fingerprint text not null,
  entity_kind text not null check (entity_kind in ('customer','debt','payment')),
  source_id text not null,
  target_id uuid not null,
  created_at timestamptz not null default now(),
  primary key(admin_id, source_fingerprint, entity_kind, source_id)
);

create index if not exists legacy_import_jobs_admin_created_idx
  on public.legacy_import_jobs(admin_id, created_at desc);
create index if not exists legacy_import_links_target_idx
  on public.legacy_import_links(target_id);

alter table public.legacy_import_jobs enable row level security;
alter table public.legacy_import_links enable row level security;

revoke all on public.legacy_import_jobs from anon, authenticated;
revoke all on public.legacy_import_links from anon, authenticated;

grant select on public.legacy_import_jobs to authenticated;
grant select on public.legacy_import_links to authenticated;

create policy legacy_import_jobs_admin_select
on public.legacy_import_jobs
for select to authenticated
using (admin_id = auth.uid());

create policy legacy_import_links_admin_select
on public.legacy_import_links
for select to authenticated
using (admin_id = auth.uid());

create or replace function public.legacy_import_apply_payment(
  p_admin_id uuid,
  p_debt_id uuid,
  p_payment_id uuid,
  p_amount numeric,
  p_note text,
  p_created_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_debt public.debts%rowtype;
  v_customer_admin uuid;
  v_new_remaining numeric;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount';
  end if;

  select d.*
    into v_debt
  from public.debts d
  where d.id = p_debt_id
    and coalesce(d.is_deleted, false) = false
  for update;

  if not found then
    raise exception 'debt_not_found';
  end if;

  select p.admin_id
    into v_customer_admin
  from public.profiles p
  where p.id = v_debt.customer_id;

  if v_customer_admin is distinct from p_admin_id then
    raise exception 'cross_tenant_forbidden';
  end if;

  if exists(select 1 from public.payments where id = p_payment_id) then
    return;
  end if;
  if p_amount > v_debt.remaining then
    raise exception 'payment_exceeds_remaining';
  end if;

  insert into public.payments(id, debt_id, amount, note, created_by, created_at)
  values (p_payment_id, p_debt_id, p_amount, coalesce(p_note, ''), p_admin_id, p_created_at);

  v_new_remaining := v_debt.remaining - p_amount;
  perform set_config('zhirox.payment_rpc', 'on', true);

  update public.debts
  set remaining = v_new_remaining,
      status = case when v_new_remaining = 0 then 'paid' else 'partial' end,
      updated_at = greatest(coalesce(updated_at, p_created_at), p_created_at)
  where id = p_debt_id;
end;
$$;

revoke all on function public.legacy_import_apply_payment(uuid,uuid,uuid,numeric,text,timestamptz)
  from public, anon, authenticated;
grant execute on function public.legacy_import_apply_payment(uuid,uuid,uuid,numeric,text,timestamptz)
  to service_role;

create or replace function public.owner_set_admin_import_permission(
  p_admin_id uuid,
  p_allowed boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid()
      and is_system_owner = true
      and active = true
  ) then
    raise exception 'system_owner_required';
  end if;

  update public.profiles
  set can_import_data = coalesce(p_allowed, false),
      updated_at = now()
  where id = p_admin_id and role = 'admin' and is_system_owner = false;

  return found;
end;
$$;

revoke all on function public.owner_set_admin_import_permission(uuid,boolean)
  from public, anon;
grant execute on function public.owner_set_admin_import_permission(uuid,boolean)
  to authenticated;
