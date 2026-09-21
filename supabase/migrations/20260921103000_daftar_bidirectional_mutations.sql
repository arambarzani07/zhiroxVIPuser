-- Complete mutation transport for Daftar Qarz account 28 <-> ZHIROX.
--
-- The original outbound queue handled inserts only. This migration adds
-- update/delete snapshots, preserves remote mappings after local deletion,
-- and exposes service-only inbound helpers which suppress echo events inside
-- the same database transaction.

alter table public.daftar_outbound_events
  add column if not exists payload_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists remote_id_snapshot text;

alter table public.daftar_sync_runs
  add column if not exists updated_customers integer not null default 0,
  add column if not exists updated_debts integer not null default 0,
  add column if not exists updated_payments integer not null default 0,
  add column if not exists deleted_customers integer not null default 0,
  add column if not exists deleted_debts integer not null default 0,
  add column if not exists deleted_payments integer not null default 0;

do $$
declare
  v_constraint text;
begin
  select conname into v_constraint
  from pg_constraint
  where conrelid = 'public.daftar_outbound_events'::regclass
    and contype = 'c'
    and pg_get_constraintdef(oid) ilike '%operation%';

  if v_constraint is not null then
    execute format(
      'alter table public.daftar_outbound_events drop constraint %I',
      v_constraint
    );
  end if;

  alter table public.daftar_outbound_events
    add constraint daftar_outbound_events_operation_check
    check (operation in ('create', 'update', 'delete'));
end;
$$;

create table if not exists public.daftar_inbound_missing_candidates (
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  entity_kind text not null check (entity_kind in ('customer', 'debt', 'payment')),
  source_id text not null,
  missing_count integer not null default 1 check (missing_count > 0),
  first_missing_at timestamptz not null default now(),
  last_missing_at timestamptz not null default now(),
  primary key (sync_source_id, entity_kind, source_id)
);

alter table public.daftar_inbound_missing_candidates enable row level security;
revoke all on public.daftar_inbound_missing_candidates from public, anon, authenticated;
grant select, insert, update, delete on public.daftar_inbound_missing_candidates to service_role;

create or replace function public.enqueue_daftar_outbound_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_admin_id uuid;
  v_entity_kind text;
  v_entity_id uuid;
  v_operation text := case tg_op
    when 'INSERT' then 'create'
    when 'UPDATE' then 'update'
    else 'delete'
  end;
  v_source_id uuid;
  v_remote_id text;
  v_payload jsonb;
  v_customer_id uuid;
  v_currency text;
begin
  if coalesce(current_setting('zhirox.daftar_inbound', true), '') = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_table_name = 'profiles' then
    if coalesce(v_row->>'role', '') <> 'customer'
       or nullif(v_row->>'admin_id', '') is null then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;
    if tg_op = 'UPDATE'
       and (new.name, new.phone) is not distinct from (old.name, old.phone) then
      return new;
    end if;
    v_admin_id := (v_row->>'admin_id')::uuid;
    v_entity_kind := 'customer';
    v_entity_id := (v_row->>'id')::uuid;
    v_payload := jsonb_build_object(
      'id', v_row->>'id',
      'name', coalesce(v_row->>'name', ''),
      'phone', coalesce(v_row->>'phone', ''),
      'created_at', v_row->>'created_at',
      'updated_at', coalesce(v_row->>'updated_at', v_row->>'created_at')
    );
  elsif tg_table_name = 'debts' then
    v_customer_id := (v_row->>'customer_id')::uuid;
    select p.admin_id into v_admin_id
    from public.profiles p
    where p.id = v_customer_id and p.role = 'customer';
    if v_admin_id is null then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    if tg_op = 'UPDATE' then
      if coalesce(old.is_deleted, false) = false
         and coalesce(new.is_deleted, false) = true then
        v_operation := 'delete';
      elsif coalesce(old.is_deleted, false) = true
            and coalesce(new.is_deleted, false) = false then
        v_operation := 'create';
      elsif (new.customer_id, new.amount, new.currency, new.description, new.custom_date)
            is not distinct from
            (old.customer_id, old.amount, old.currency, old.description, old.custom_date) then
        return new;
      else
        v_operation := 'update';
      end if;
    end if;

    v_entity_kind := 'debt';
    v_entity_id := (v_row->>'id')::uuid;
    v_payload := jsonb_build_object(
      'id', v_row->>'id',
      'customer_id', v_row->>'customer_id',
      'amount', v_row->'amount',
      'currency', coalesce(v_row->>'currency', 'IQD'),
      'description', coalesce(v_row->>'description', ''),
      'transaction_date', coalesce(v_row->>'custom_date', v_row->>'created_at'),
      'created_at', v_row->>'created_at',
      'updated_at', coalesce(v_row->>'updated_at', v_row->>'created_at'),
      'is_deleted', coalesce((v_row->>'is_deleted')::boolean, false)
    );
  elsif tg_table_name = 'payments' then
    select p.admin_id, d.customer_id, d.currency
      into v_admin_id, v_customer_id, v_currency
    from public.debts d
    join public.profiles p on p.id = d.customer_id and p.role = 'customer'
    where d.id = (v_row->>'debt_id')::uuid;
    if v_admin_id is null then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;
    if tg_op = 'UPDATE'
       and (new.debt_id, new.amount, new.note)
           is not distinct from (old.debt_id, old.amount, old.note) then
      return new;
    end if;
    v_entity_kind := 'payment';
    v_entity_id := (v_row->>'id')::uuid;
    v_payload := jsonb_build_object(
      'id', v_row->>'id',
      'debt_id', v_row->>'debt_id',
      'customer_id', v_customer_id,
      'amount', v_row->'amount',
      'currency', coalesce(v_currency, 'IQD'),
      'note', coalesce(v_row->>'note', ''),
      'transaction_date', v_row->>'created_at',
      'created_at', v_row->>'created_at'
    );
  else
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select s.id into v_source_id
  from public.daftar_sync_sources s
  where s.admin_id = v_admin_id
    and s.legacy_user_id = 28
    and s.source_fingerprint = 'daftar-live-account-28-v1'
    and s.sync_mode = 'zhirox_primary'
    and s.outbound_sync_enabled = true
  limit 1;

  if v_source_id is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select split_part(l.source_id, ':', 1) into v_remote_id
  from public.legacy_import_links l
  where l.admin_id = v_admin_id
    and l.source_fingerprint = 'daftar-live-account-28-v1'
    and l.entity_kind = v_entity_kind
    and l.target_id = v_entity_id
  order by l.created_at desc
  limit 1;

  insert into public.daftar_outbound_events(
    sync_source_id,
    entity_kind,
    entity_id,
    operation,
    idempotency_key,
    payload_snapshot,
    remote_id_snapshot,
    next_attempt_at
  ) values (
    v_source_id,
    v_entity_kind,
    v_entity_id,
    v_operation,
    'zhirox:' || v_entity_kind || ':' || v_entity_id::text || ':' ||
      v_operation || ':' || md5(coalesce(v_payload::text, '{}')),
    coalesce(v_payload, '{}'::jsonb),
    v_remote_id,
    now() + interval '5 seconds'
  )
  on conflict (idempotency_key) do update
  set payload_snapshot = excluded.payload_snapshot,
      remote_id_snapshot = coalesce(excluded.remote_id_snapshot,
                                    public.daftar_outbound_events.remote_id_snapshot),
      status = case
        when public.daftar_outbound_events.status in ('sent', 'skipped')
          then public.daftar_outbound_events.status
        else 'pending'
      end,
      next_attempt_at = least(public.daftar_outbound_events.next_attempt_at,
                              excluded.next_attempt_at),
      updated_at = now();

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.enqueue_daftar_outbound_mutation()
  from public, anon, authenticated;

drop trigger if exists daftar_outbound_profile_create on public.profiles;
drop trigger if exists daftar_outbound_debt_create on public.debts;
drop trigger if exists daftar_outbound_payment_create on public.payments;
drop trigger if exists daftar_outbound_profile_mutation on public.profiles;
drop trigger if exists daftar_outbound_debt_mutation on public.debts;
drop trigger if exists daftar_outbound_payment_mutation on public.payments;

create trigger daftar_outbound_profile_mutation
after insert or update or delete on public.profiles
for each row execute function public.enqueue_daftar_outbound_mutation();

create trigger daftar_outbound_debt_mutation
after insert or update or delete on public.debts
for each row execute function public.enqueue_daftar_outbound_mutation();

create trigger daftar_outbound_payment_mutation
after insert or update or delete on public.payments
for each row execute function public.enqueue_daftar_outbound_mutation();

create or replace function public.apply_daftar_inbound_customer_update(
  p_admin_id uuid,
  p_target_id uuid,
  p_name text,
  p_phone text,
  p_updated_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('zhirox.daftar_inbound', 'on', true);
  update public.profiles
  set name = coalesce(nullif(btrim(p_name), ''), name),
      phone = coalesce(nullif(btrim(p_phone), ''), phone),
      updated_at = coalesce(p_updated_at, now())
  where id = p_target_id
    and role = 'customer'
    and admin_id = p_admin_id;
  return found;
end;
$$;

create or replace function public.apply_daftar_inbound_debt_update(
  p_admin_id uuid,
  p_target_id uuid,
  p_amount numeric,
  p_currency text,
  p_description text,
  p_occurred_at timestamptz,
  p_deleted boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_paid numeric;
  v_remaining numeric;
begin
  if p_amount is null or p_amount < 0 then
    raise exception 'invalid_amount';
  end if;
  if not exists (
    select 1
    from public.debts d
    join public.profiles p on p.id = d.customer_id
    where d.id = p_target_id and p.admin_id = p_admin_id
  ) then
    return false;
  end if;

  select coalesce(sum(pay.amount), 0) into v_paid
  from public.payments pay
  where pay.debt_id = p_target_id;
  if p_amount < v_paid then
    raise exception 'debt_amount_below_recorded_payments';
  end if;
  v_remaining := greatest(0, p_amount - v_paid);

  perform set_config('zhirox.daftar_inbound', 'on', true);
  perform set_config('zhirox.payment_rpc', 'on', true);
  update public.debts
  set amount = p_amount,
      remaining = v_remaining,
      currency = upper(coalesce(nullif(btrim(p_currency), ''), 'IQD')),
      amount_usd = case when upper(coalesce(p_currency, 'IQD')) = 'USD' then p_amount else 0 end,
      description = coalesce(p_description, ''),
      custom_date = coalesce(p_occurred_at, custom_date),
      is_deleted = coalesce(p_deleted, false),
      deleted_at = case when coalesce(p_deleted, false) then now() else null end,
      deleted_by = case when coalesce(p_deleted, false) then p_admin_id else null end,
      status = case
        when v_remaining <= 0 then 'paid'
        when v_remaining >= p_amount then 'pending'
        else 'partial'
      end,
      updated_at = now()
  where id = p_target_id;
  return found;
end;
$$;

create or replace function public.remove_daftar_inbound_payment(
  p_admin_id uuid,
  p_source_id uuid,
  p_remote_transaction_id text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  perform set_config('zhirox.daftar_inbound', 'on', true);
  perform set_config('zhirox.payment_rpc', 'on', true);

  for v_row in
    select pay.id, pay.debt_id, pay.amount
    from public.legacy_import_links l
    join public.payments pay on pay.id = l.target_id
    join public.debts d on d.id = pay.debt_id
    join public.profiles p on p.id = d.customer_id
    where l.admin_id = p_admin_id
      and l.source_fingerprint = 'daftar-live-account-28-v1'
      and l.entity_kind = 'payment'
      and l.source_id like p_remote_transaction_id || ':%'
      and p.admin_id = p_admin_id
    order by l.source_id
  loop
    update public.debts
    set remaining = least(amount, remaining + v_row.amount),
        status = case
          when least(amount, remaining + v_row.amount) >= amount then 'pending'
          else 'partial'
        end,
        updated_at = now()
    where id = v_row.debt_id;

    delete from public.payments where id = v_row.id;
    v_count := v_count + 1;
  end loop;

  delete from public.legacy_import_links
  where admin_id = p_admin_id
    and source_fingerprint = 'daftar-live-account-28-v1'
    and entity_kind = 'payment'
    and source_id like p_remote_transaction_id || ':%';

  delete from public.daftar_sync_seen
  where sync_source_id = p_source_id
    and (
      (entity_kind = 'payment' and source_id = p_remote_transaction_id)
      or
      (entity_kind = 'payment_allocation' and source_id like p_remote_transaction_id || ':%')
    );

  return v_count;
end;
$$;

create or replace function public.delete_daftar_inbound_debt(
  p_admin_id uuid,
  p_target_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('zhirox.daftar_inbound', 'on', true);
  update public.debts d
  set is_deleted = true,
      deleted_at = now(),
      deleted_by = p_admin_id,
      updated_at = now()
  from public.profiles p
  where d.id = p_target_id
    and p.id = d.customer_id
    and p.admin_id = p_admin_id
    and d.is_deleted = false;
  return found;
end;
$$;

create or replace function public.delete_daftar_inbound_customer(
  p_admin_id uuid,
  p_target_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = p_target_id
      and role = 'customer'
      and admin_id = p_admin_id
  ) then
    return false;
  end if;

  perform set_config('zhirox.daftar_inbound', 'on', true);
  -- Deleting auth.users uses the platform's existing FK cascade so the auth
  -- identity, profile, debts, payments and read-state disappear together.
  delete from auth.users where id = p_target_id;
  return found;
end;
$$;

revoke all on function public.apply_daftar_inbound_customer_update(uuid,uuid,text,text,timestamptz)
  from public, anon, authenticated;
revoke all on function public.apply_daftar_inbound_debt_update(uuid,uuid,numeric,text,text,timestamptz,boolean)
  from public, anon, authenticated;
revoke all on function public.remove_daftar_inbound_payment(uuid,uuid,text)
  from public, anon, authenticated;
revoke all on function public.delete_daftar_inbound_debt(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.delete_daftar_inbound_customer(uuid,uuid)
  from public, anon, authenticated;

grant execute on function public.apply_daftar_inbound_customer_update(uuid,uuid,text,text,timestamptz)
  to service_role;
grant execute on function public.apply_daftar_inbound_debt_update(uuid,uuid,numeric,text,text,timestamptz,boolean)
  to service_role;
grant execute on function public.remove_daftar_inbound_payment(uuid,uuid,text)
  to service_role;
grant execute on function public.delete_daftar_inbound_debt(uuid,uuid)
  to service_role;
grant execute on function public.delete_daftar_inbound_customer(uuid,uuid)
  to service_role;
