-- Reconcile the active Kanichnar dataset with Daftar account 28 without
-- physically deleting any pre-sync records. Every archived row remains fully
-- recoverable from this table and debts use the existing trash/restore flow.

create table if not exists public.reconciliation_archives (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  batch_key text not null,
  entity_kind text not null check (entity_kind in ('customer', 'debt', 'payment')),
  entity_id uuid not null,
  snapshot jsonb not null,
  reason text not null,
  archived_at timestamptz not null default now(),
  restored_at timestamptz,
  unique (batch_key, entity_kind, entity_id)
);

alter table public.reconciliation_archives enable row level security;
revoke all on public.reconciliation_archives from anon, authenticated;

create policy "reconciliation_archives_no_client_access"
on public.reconciliation_archives
for all to anon, authenticated
using (false)
with check (false);

create index if not exists reconciliation_archives_admin_batch_idx
  on public.reconciliation_archives(admin_id, batch_key, archived_at desc);

do $$
declare
  v_admin_id uuid;
  v_sync_source_id uuid;
  v_debt_count integer;
  v_customer_count integer;
  v_payment_count integer;
  v_batch_key constant text := 'daftar-28-pre-sync-reconciliation-20260913';
begin
  select s.admin_id, s.id
    into v_admin_id, v_sync_source_id
  from public.daftar_sync_sources s
  join public.profiles admin_profile on admin_profile.id = s.admin_id
  where s.legacy_user_id = 28
    and admin_profile.market_name = 'سوپەرمارکێتی کانی چنار'
  limit 1;

  if v_admin_id is null or v_sync_source_id is null then
    raise notice 'Daftar account 28 target absent; skipping production reconciliation on fresh install';
    return;
  end if;

  select count(*) into v_debt_count
  from public.debts d
  join public.profiles customer on customer.id = d.customer_id
  where customer.admin_id = v_admin_id
    and d.is_deleted = false
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'debt'
        and seen.target_id = d.id
    );

  select count(*) into v_customer_count
  from public.profiles customer
  where customer.admin_id = v_admin_id
    and customer.role = 'customer'
    and customer.active = true
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'customer'
        and seen.target_id = customer.id
    );

  select count(*) into v_payment_count
  from public.payments payment
  join public.debts debt on debt.id = payment.debt_id
  join public.profiles customer on customer.id = debt.customer_id
  where customer.admin_id = v_admin_id
    and debt.is_deleted = false
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'debt'
        and seen.target_id = debt.id
    );

  if v_debt_count <> 3 or v_customer_count <> 1 or v_payment_count <> 1 then
    raise exception 'Reconciliation guard failed: debts %, customers %, payments %',
      v_debt_count, v_customer_count, v_payment_count;
  end if;

  insert into public.reconciliation_archives
    (admin_id, batch_key, entity_kind, entity_id, snapshot, reason)
  select v_admin_id, v_batch_key, 'payment', payment.id, to_jsonb(payment),
    'Pre-sync record preserved while aligning the active dataset with Daftar account 28'
  from public.payments payment
  join public.debts debt on debt.id = payment.debt_id
  join public.profiles customer on customer.id = debt.customer_id
  where customer.admin_id = v_admin_id
    and debt.is_deleted = false
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'debt'
        and seen.target_id = debt.id
    )
  on conflict (batch_key, entity_kind, entity_id) do nothing;

  insert into public.reconciliation_archives
    (admin_id, batch_key, entity_kind, entity_id, snapshot, reason)
  select v_admin_id, v_batch_key, 'debt', debt.id, to_jsonb(debt),
    'Pre-sync record preserved while aligning the active dataset with Daftar account 28'
  from public.debts debt
  join public.profiles customer on customer.id = debt.customer_id
  where customer.admin_id = v_admin_id
    and debt.is_deleted = false
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'debt'
        and seen.target_id = debt.id
    )
  on conflict (batch_key, entity_kind, entity_id) do nothing;

  insert into public.reconciliation_archives
    (admin_id, batch_key, entity_kind, entity_id, snapshot, reason)
  select v_admin_id, v_batch_key, 'customer', customer.id, to_jsonb(customer),
    'Pre-sync record preserved while aligning the active dataset with Daftar account 28'
  from public.profiles customer
  where customer.admin_id = v_admin_id
    and customer.role = 'customer'
    and customer.active = true
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'customer'
        and seen.target_id = customer.id
    )
  on conflict (batch_key, entity_kind, entity_id) do nothing;

  update public.debts debt
  set is_deleted = true,
      deleted_at = now(),
      deleted_by = v_admin_id,
      updated_at = now()
  from public.profiles customer
  where debt.customer_id = customer.id
    and customer.admin_id = v_admin_id
    and debt.is_deleted = false
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'debt'
        and seen.target_id = debt.id
    );

  update public.profiles customer
  set active = false,
      approved = false,
      updated_at = now()
  where customer.admin_id = v_admin_id
    and customer.role = 'customer'
    and customer.active = true
    and not exists (
      select 1 from public.daftar_sync_seen seen
      where seen.sync_source_id = v_sync_source_id
        and seen.entity_kind = 'customer'
        and seen.target_id = customer.id
    );
end;
$$;

-- Inactive archived profiles are neither active customers nor pending requests.
create or replace function public.get_admin_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if private."current_role"() is distinct from 'admin' then
    raise insufficient_privilege using message = 'admin role required';
  end if;

  select jsonb_build_object(
    'total_customers', (select count(*) from public.profiles p where p.role = 'customer' and p.approved = true and p.active = true),
    'pending_requests', (select count(*) from public.profiles p where p.role = 'customer' and p.approved = false and p.active = true),
    'total_debt', coalesce((select sum(d.amount) from public.debts d where d.is_deleted = false and upper(coalesce(d.currency, 'IQD')) <> 'USD'), 0),
    'total_remaining', coalesce((select sum(d.remaining) from public.debts d where d.is_deleted = false and upper(coalesce(d.currency, 'IQD')) <> 'USD'), 0),
    'total_payments', coalesce((select sum(pay.amount) from public.payments pay join public.debts d on d.id = pay.debt_id where d.is_deleted = false and upper(coalesce(d.currency, 'IQD')) <> 'USD'), 0),
    'total_debt_usd', coalesce((select sum(d.amount) from public.debts d where d.is_deleted = false and upper(coalesce(d.currency, 'IQD')) = 'USD'), 0),
    'total_remaining_usd', coalesce((select sum(d.remaining) from public.debts d where d.is_deleted = false and upper(coalesce(d.currency, 'IQD')) = 'USD'), 0),
    'total_payments_usd', coalesce((select sum(pay.amount) from public.payments pay join public.debts d on d.id = pay.debt_id where d.is_deleted = false and upper(coalesce(d.currency, 'IQD')) = 'USD'), 0),
    'pending_debts', (select count(*) from public.debts d where d.is_deleted = false and d.status <> 'paid'),
    'recent_activity', coalesce((
      select jsonb_agg(recent_row.payload order by recent_row.created_at desc)
      from (
        select d.created_at,
          to_jsonb(d) || jsonb_build_object(
            'customer', jsonb_build_object('id', customer.id, 'name', customer.name, 'role', customer.role, 'created_at', customer.created_at, 'updated_at', customer.updated_at),
            'created_by', case when creator.id is null then null else jsonb_build_object('id', creator.id, 'name', creator.name, 'role', creator.role, 'created_at', creator.created_at, 'updated_at', creator.updated_at) end
          ) as payload
        from public.debts d
        join public.profiles customer on customer.id = d.customer_id
        left join public.profiles creator on creator.id = d.created_by
        where d.is_deleted = false
        order by d.created_at desc
        limit 5
      ) recent_row
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.get_admin_dashboard_snapshot() from public, anon;
grant execute on function public.get_admin_dashboard_snapshot() to authenticated;