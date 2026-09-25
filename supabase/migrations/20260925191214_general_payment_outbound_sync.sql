-- Keep customer-wide/general repayments synchronized with the official
-- Daftar transaction feed without allocating them across local debt rows.
--
-- Daftar models PAYMENT at the customer/contact level. ZHIROX keeps general
-- repayments in a separate ledger so the local per-debt remaining values stay
-- unchanged. This migration bridges those two representations safely.

create or replace function public.enqueue_daftar_outbound_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
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
  v_source_fingerprint text;
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
      'created_at', v_row->>'created_at',
      'payment_scope', 'debt',
      'source_table', 'payments'
    );
  elsif tg_table_name = 'customer_general_payments' then
    v_admin_id := (v_row->>'admin_id')::uuid;
    v_customer_id := (v_row->>'customer_id')::uuid;

    if not exists (
      select 1
      from public.profiles p
      where p.id = v_customer_id
        and p.role = 'customer'
        and p.admin_id = v_admin_id
    ) then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    if tg_op = 'UPDATE'
       and (new.customer_id, new.amount, new.note, new.created_at)
           is not distinct from
           (old.customer_id, old.amount, old.note, old.created_at) then
      return new;
    end if;

    v_entity_kind := 'payment';
    v_entity_id := (v_row->>'id')::uuid;
    v_payload := jsonb_build_object(
      'id', v_row->>'id',
      'customer_id', v_row->>'customer_id',
      'amount', v_row->'amount',
      'currency', 'IQD',
      'note', coalesce(v_row->>'note', ''),
      'transaction_date', v_row->>'created_at',
      'created_at', v_row->>'created_at',
      'payment_scope', 'general',
      'source_table', 'customer_general_payments'
    );
  else
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select s.id, s.source_fingerprint
    into v_source_id, v_source_fingerprint
  from public.daftar_sync_sources s
  where s.admin_id = v_admin_id
    and s.enabled = true
    and s.sync_mode = 'zhirox_primary'
    and s.outbound_sync_enabled = true
    and s.outbound_write_contract_status = 'verified'
  order by s.created_at
  limit 1;

  if v_source_id is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select split_part(l.source_id, ':', 1) into v_remote_id
  from public.legacy_import_links l
  where l.admin_id = v_admin_id
    and l.source_fingerprint = v_source_fingerprint
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
    'zhirox:' || v_source_id::text || ':' || v_entity_kind || ':' ||
      v_entity_id::text || ':' || v_operation || ':' ||
      md5(coalesce(v_payload::text, '{}')),
    coalesce(v_payload, '{}'::jsonb),
    v_remote_id,
    now() + interval '5 seconds'
  )
  on conflict (idempotency_key) do update
  set payload_snapshot = excluded.payload_snapshot,
      remote_id_snapshot = coalesce(
        excluded.remote_id_snapshot,
        public.daftar_outbound_events.remote_id_snapshot
      ),
      status = case
        when public.daftar_outbound_events.status in ('sent', 'skipped')
          then public.daftar_outbound_events.status
        else 'pending'
      end,
      next_attempt_at = least(
        public.daftar_outbound_events.next_attempt_at,
        excluded.next_attempt_at
      ),
      updated_at = now();

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function public.enqueue_daftar_outbound_mutation()
  from public, anon, authenticated;

drop trigger if exists daftar_outbound_general_payment_mutation
  on public.customer_general_payments;
create trigger daftar_outbound_general_payment_mutation
after insert or update or delete on public.customer_general_payments
for each row execute function public.enqueue_daftar_outbound_mutation();

create or replace function public.apply_daftar_inbound_general_payment_update(
  p_admin_id uuid,
  p_source_id uuid,
  p_remote_transaction_id text,
  p_customer_id uuid,
  p_amount numeric,
  p_note text,
  p_occurred_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_source_fingerprint text;
  v_target_id uuid;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select s.source_fingerprint into v_source_fingerprint
  from public.daftar_sync_sources s
  where s.id = p_source_id
    and s.admin_id = p_admin_id
  limit 1;

  if v_source_fingerprint is null then
    return false;
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_customer_id
      and p.role = 'customer'
      and p.admin_id = p_admin_id
  ) then
    return false;
  end if;

  select l.target_id into v_target_id
  from public.legacy_import_links l
  join public.customer_general_payments g on g.id = l.target_id
  where l.admin_id = p_admin_id
    and l.source_fingerprint = v_source_fingerprint
    and l.entity_kind = 'payment'
    and l.source_id like p_remote_transaction_id || ':%'
    and g.admin_id = p_admin_id
  order by l.created_at desc
  limit 1;

  if v_target_id is null then
    return false;
  end if;

  perform set_config('zhirox.daftar_inbound', 'on', true);

  update public.customer_general_payments
  set customer_id = p_customer_id,
      amount = p_amount,
      note = coalesce(p_note, ''),
      created_at = coalesce(p_occurred_at, created_at),
      reference_kind = null,
      reference_id = null,
      reference_snapshot = '{}'::jsonb
  where id = v_target_id
    and admin_id = p_admin_id;

  return found;
end;
$function$;

revoke all on function public.apply_daftar_inbound_general_payment_update(
  uuid,uuid,text,uuid,numeric,text,timestamptz
) from public, anon, authenticated;
grant execute on function public.apply_daftar_inbound_general_payment_update(
  uuid,uuid,text,uuid,numeric,text,timestamptz
) to service_role;

create or replace function public.remove_daftar_inbound_payment(
  p_admin_id uuid,
  p_source_id uuid,
  p_remote_transaction_id text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row record;
  v_general record;
  v_count integer := 0;
  v_source_fingerprint text;
begin
  perform set_config('zhirox.daftar_inbound', 'on', true);
  perform set_config('zhirox.payment_rpc', 'on', true);

  select s.source_fingerprint into v_source_fingerprint
  from public.daftar_sync_sources s
  where s.id = p_source_id
    and s.admin_id = p_admin_id
  limit 1;

  if v_source_fingerprint is null then
    return 0;
  end if;

  for v_general in
    select g.id
    from public.legacy_import_links l
    join public.customer_general_payments g on g.id = l.target_id
    where l.admin_id = p_admin_id
      and l.source_fingerprint = v_source_fingerprint
      and l.entity_kind = 'payment'
      and l.source_id like p_remote_transaction_id || ':%'
      and g.admin_id = p_admin_id
    order by l.source_id
  loop
    delete from public.customer_general_payments
    where id = v_general.id
      and admin_id = p_admin_id;
    v_count := v_count + 1;
  end loop;

  for v_row in
    select pay.id, pay.debt_id, pay.amount
    from public.legacy_import_links l
    join public.payments pay on pay.id = l.target_id
    join public.debts d on d.id = pay.debt_id
    join public.profiles p on p.id = d.customer_id
    where l.admin_id = p_admin_id
      and l.source_fingerprint = v_source_fingerprint
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
    and source_fingerprint = v_source_fingerprint
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
$function$;

revoke all on function public.remove_daftar_inbound_payment(uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function public.remove_daftar_inbound_payment(uuid,uuid,text)
  to service_role;

-- Backfill only unsynchronized general repayments. Existing remote mappings or
-- already queued/sent events are left untouched.
insert into public.daftar_outbound_events(
  sync_source_id,
  entity_kind,
  entity_id,
  operation,
  idempotency_key,
  payload_snapshot,
  remote_id_snapshot,
  next_attempt_at
)
select
  s.id,
  'payment',
  g.id,
  'create',
  'zhirox:' || s.id::text || ':payment:' || g.id::text || ':create:' ||
    md5(
      jsonb_build_object(
        'id', g.id,
        'customer_id', g.customer_id,
        'amount', g.amount,
        'currency', 'IQD',
        'note', coalesce(g.note, ''),
        'transaction_date', g.created_at,
        'created_at', g.created_at,
        'payment_scope', 'general',
        'source_table', 'customer_general_payments'
      )::text
    ),
  jsonb_build_object(
    'id', g.id,
    'customer_id', g.customer_id,
    'amount', g.amount,
    'currency', 'IQD',
    'note', coalesce(g.note, ''),
    'transaction_date', g.created_at,
    'created_at', g.created_at,
    'payment_scope', 'general',
    'source_table', 'customer_general_payments'
  ),
  null,
  now()
from public.customer_general_payments g
join public.daftar_sync_sources s
  on s.admin_id = g.admin_id
 and s.enabled = true
 and s.sync_mode = 'zhirox_primary'
 and s.outbound_sync_enabled = true
 and s.outbound_write_contract_status = 'verified'
where not exists (
  select 1
  from public.legacy_import_links l
  where l.admin_id = g.admin_id
    and l.source_fingerprint = s.source_fingerprint
    and l.entity_kind = 'payment'
    and l.target_id = g.id
)
and not exists (
  select 1
  from public.daftar_outbound_events e
  where e.sync_source_id = s.id
    and e.entity_kind = 'payment'
    and e.entity_id = g.id
    and e.operation = 'create'
    and e.status in ('pending','processing','sent','failed','blocked')
)
on conflict (idempotency_key) do nothing;
