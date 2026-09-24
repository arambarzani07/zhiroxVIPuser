
-- ZHIROX customer notification and portal upgrade.
-- Reminder schedules, preferences, read/ack state, installment reminders,
-- monthly statements, debt-limit notifications, and transaction deep links.

alter table public.notification_outbox
  add column if not exists read_at timestamptz,
  add column if not exists acknowledged_at timestamptz,
  add column if not exists deep_link text,
  add column if not exists requires_ack boolean not null default false,
  add column if not exists receipt_id uuid references public.receipt_documents(id) on delete set null;

alter table public.notification_outbox
  drop constraint if exists notification_outbox_event_type_check;
alter table public.notification_outbox
  add constraint notification_outbox_event_type_check
  check (
    event_type in (
      'debt_created',
      'payment_created',
      'due_reminder',
      'manual',
      'debt_limit_changed',
      'installment_reminder',
      'monthly_statement'
    )
  );

create index if not exists notification_outbox_unread_customer_idx
  on public.notification_outbox (market_id, customer_id, created_at desc)
  where read_at is null;

create index if not exists notification_outbox_receipt_idx
  on public.notification_outbox (receipt_id)
  where receipt_id is not null;

alter table public.audit_logs
  drop constraint if exists audit_logs_action_check;
alter table public.audit_logs
  add constraint audit_logs_action_check
  check (
    action in (
      'insert','update','delete','restore','permission_change',
      'backup','backup_restore','receipt_acknowledged'
    )
  );

create table if not exists public.customer_notification_preferences (
  customer_id uuid primary key references public.profiles(id) on delete cascade,
  market_id uuid not null references public.profiles(id) on delete cascade,
  due_reminders boolean not null default true,
  installment_reminders boolean not null default true,
  monthly_statements boolean not null default true,
  manual_messages boolean not null default true,
  updated_at timestamptz not null default now(),
  constraint customer_notification_preferences_tenant_check
    check (customer_id <> market_id)
);

create index if not exists customer_notification_preferences_market_idx
  on public.customer_notification_preferences (market_id, customer_id);

alter table public.customer_notification_preferences enable row level security;
revoke all on table public.customer_notification_preferences from public, anon, authenticated;
grant select, insert, update, delete on table public.customer_notification_preferences to service_role;

create table if not exists public.debt_installments (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  debt_id uuid not null references public.debts(id) on delete cascade,
  installment_no integer not null check (installment_no > 0),
  amount numeric not null check (amount > 0),
  due_date date not null,
  status text not null default 'pending'
    check (status in ('pending','paid','cancelled')),
  paid_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (debt_id, installment_no)
);

create index if not exists debt_installments_due_idx
  on public.debt_installments (admin_id, status, due_date, customer_id);
create index if not exists debt_installments_customer_idx
  on public.debt_installments (customer_id, due_date, installment_no);

alter table public.debt_installments enable row level security;

drop policy if exists debt_installments_tenant_read on public.debt_installments;
create policy debt_installments_tenant_read
  on public.debt_installments
  for select
  to authenticated
  using (
    admin_id = private.current_admin_id()
    and (
      private."current_role"() = 'admin'
      or private.employee_has_permission('view_debts')
    )
  );

drop policy if exists debt_installments_tenant_insert on public.debt_installments;
create policy debt_installments_tenant_insert
  on public.debt_installments
  for insert
  to authenticated
  with check (
    admin_id = private.current_admin_id()
    and created_by = (select auth.uid())
    and (
      private."current_role"() = 'admin'
      or private.employee_has_permission('edit_debts')
    )
    and exists (
      select 1
      from public.debts d
      join public.profiles c on c.id = d.customer_id
      where d.id = debt_id
        and d.customer_id = customer_id
        and c.admin_id = private.current_admin_id()
        and c.role = 'customer'
    )
  );

drop policy if exists debt_installments_tenant_update on public.debt_installments;
create policy debt_installments_tenant_update
  on public.debt_installments
  for update
  to authenticated
  using (
    admin_id = private.current_admin_id()
    and (
      private."current_role"() = 'admin'
      or private.employee_has_permission('edit_debts')
    )
  )
  with check (
    admin_id = private.current_admin_id()
    and (
      private."current_role"() = 'admin'
      or private.employee_has_permission('edit_debts')
    )
  );

revoke all on table public.debt_installments from public, anon, authenticated;
grant select, insert, update on table public.debt_installments to authenticated;
grant all on table public.debt_installments to service_role;

create or replace function private.resolve_customer_push_identity(
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null
)
returns table(customer_id uuid, market_id uuid)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_token_hash is not null and p_token_hash ~ '^[a-f0-9]{64}$' then
    return query
      select link.customer_id, link.market_id
      from public.customer_push_link_tokens link
      where link.token_hash = p_token_hash
        and link.revoked_at is null
        and (link.expires_at is null or link.expires_at > now())
      limit 1;
    return;
  end if;

  if nullif(trim(coalesce(p_endpoint, '')), '') is not null
     and p_device_secret_hash is not null
     and p_device_secret_hash ~ '^[a-f0-9]{64}$' then
    return query
      select subscription.customer_id, subscription.market_id
      from public.customer_push_subscriptions subscription
      where subscription.endpoint = p_endpoint
        and subscription.device_secret_hash = p_device_secret_hash
        and subscription.active = true
      limit 1;
  end if;
end;
$function$;

revoke all on function private.resolve_customer_push_identity(text,text,text)
  from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.resolve_customer_push_identity(text,text,text)
  to service_role;

create or replace function private.customer_portal_enabled(
  p_customer_id uuid,
  p_market_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    exists (
      select 1
      from public.customer_push_subscriptions s
      where s.customer_id = p_customer_id
        and s.market_id = p_market_id
        and s.active = true
    )
    or exists (
      select 1
      from public.customer_push_link_tokens l
      where l.customer_id = p_customer_id
        and l.market_id = p_market_id
        and l.revoked_at is null
        and (l.expires_at is null or l.expires_at > now())
    );
$function$;

revoke all on function private.customer_portal_enabled(uuid,uuid)
  from public, anon, authenticated, service_role;

create or replace function public.enqueue_customer_push_event_service(
  p_market_id uuid,
  p_customer_id uuid,
  p_event_type text,
  p_event_record_id uuid,
  p_idempotency_key text,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_id uuid;
  v_customer_market uuid;
  v_deep_link text;
  v_requires_ack boolean := false;
begin
  if p_event_type not in (
    'debt_created','payment_created','due_reminder','manual',
    'debt_limit_changed','installment_reminder','monthly_statement'
  ) then
    raise exception 'unsupported_push_event' using errcode='23514';
  end if;
  if p_event_record_id is null or nullif(trim(p_idempotency_key),'') is null then
    raise exception 'invalid_push_event' using errcode='22023';
  end if;

  select customer.admin_id
    into v_customer_market
  from public.profiles customer
  where customer.id = p_customer_id
    and customer.role = 'customer';

  if v_customer_market is null or v_customer_market <> p_market_id then
    raise exception 'push_customer_market_mismatch' using errcode='42501';
  end if;

  v_requires_ack := p_event_type in ('debt_created','payment_created');

  v_deep_link := case
    when p_event_type in ('debt_created','payment_created') then
      '/?view=transactions&event=' || p_event_record_id::text
    when p_event_type = 'installment_reminder'
      and nullif(p_payload ->> 'debt_id','') is not null then
      '/?view=transactions&event=' || (p_payload ->> 'debt_id')
    when p_event_type = 'monthly_statement'
      and nullif(p_payload ->> 'period','') is not null then
      '/?view=transactions&period=' || (p_payload ->> 'period')
    when p_event_type = 'manual' then
      '/?view=notifications'
    else
      '/?view=notifications'
  end;

  with inserted as (
    insert into public.notification_outbox(
      market_id,customer_id,event_type,event_record_id,
      idempotency_key,payload,deep_link,requires_ack
    )
    values(
      p_market_id,p_customer_id,p_event_type,p_event_record_id,
      p_idempotency_key,coalesce(p_payload,'{}'::jsonb),v_deep_link,v_requires_ack
    )
    on conflict(idempotency_key) do nothing
    returning id
  )
  select id into v_id
  from inserted
  union all
  select id from public.notification_outbox
  where idempotency_key = p_idempotency_key
  limit 1;

  return v_id;
end;
$function$;

revoke all on function public.enqueue_customer_push_event_service(uuid,uuid,text,uuid,text,jsonb)
  from public, anon, authenticated;
grant execute on function public.enqueue_customer_push_event_service(uuid,uuid,text,uuid,text,jsonb)
  to service_role;

create or replace function public.read_customer_notification_preferences_service(
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_pref public.customer_notification_preferences%rowtype;
begin
  select r.customer_id, r.market_id
    into v_customer_id, v_market_id
  from private.resolve_customer_push_identity(
    p_token_hash, p_endpoint, p_device_secret_hash
  ) r
  limit 1;

  if v_customer_id is null or v_market_id is null then
    raise no_data_found;
  end if;

  select *
    into v_pref
  from public.customer_notification_preferences p
  where p.customer_id = v_customer_id
    and p.market_id = v_market_id;

  return jsonb_build_object(
    'mandatory_financial', true,
    'due_reminders', coalesce(v_pref.due_reminders, true),
    'installment_reminders', coalesce(v_pref.installment_reminders, true),
    'monthly_statements', coalesce(v_pref.monthly_statements, true),
    'manual_messages', coalesce(v_pref.manual_messages, true)
  );
end;
$function$;

create or replace function public.update_customer_notification_preferences_service(
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null,
  p_due_reminders boolean default true,
  p_installment_reminders boolean default true,
  p_monthly_statements boolean default true,
  p_manual_messages boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
begin
  select r.customer_id, r.market_id
    into v_customer_id, v_market_id
  from private.resolve_customer_push_identity(
    p_token_hash, p_endpoint, p_device_secret_hash
  ) r
  limit 1;

  if v_customer_id is null or v_market_id is null then
    raise no_data_found;
  end if;

  insert into public.customer_notification_preferences(
    customer_id, market_id, due_reminders, installment_reminders,
    monthly_statements, manual_messages, updated_at
  )
  values(
    v_customer_id, v_market_id,
    coalesce(p_due_reminders,true),
    coalesce(p_installment_reminders,true),
    coalesce(p_monthly_statements,true),
    coalesce(p_manual_messages,true),
    now()
  )
  on conflict (customer_id) do update
  set
    market_id = excluded.market_id,
    due_reminders = excluded.due_reminders,
    installment_reminders = excluded.installment_reminders,
    monthly_statements = excluded.monthly_statements,
    manual_messages = excluded.manual_messages,
    updated_at = now();

  return public.read_customer_notification_preferences_service(
    p_token_hash, p_endpoint, p_device_secret_hash
  );
end;
$function$;

revoke all on function public.read_customer_notification_preferences_service(text,text,text)
  from public, anon, authenticated;
revoke all on function public.update_customer_notification_preferences_service(text,text,text,boolean,boolean,boolean,boolean)
  from public, anon, authenticated;
grant execute on function public.read_customer_notification_preferences_service(text,text,text)
  to service_role;
grant execute on function public.update_customer_notification_preferences_service(text,text,text,boolean,boolean,boolean,boolean)
  to service_role;

create or replace function public.mark_customer_push_notification_read_service(
  p_outbox_id uuid,
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null,
  p_acknowledge boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_event_type text;
  v_requires_ack boolean;
  v_ack_before timestamptz;
  v_read_at timestamptz;
  v_ack_at timestamptz;
begin
  select r.customer_id, r.market_id
    into v_customer_id, v_market_id
  from private.resolve_customer_push_identity(
    p_token_hash, p_endpoint, p_device_secret_hash
  ) r
  limit 1;

  if v_customer_id is null or v_market_id is null then
    raise no_data_found;
  end if;

  select o.event_type, o.requires_ack, o.acknowledged_at
    into v_event_type, v_requires_ack, v_ack_before
  from public.notification_outbox o
  where o.id = p_outbox_id
    and o.customer_id = v_customer_id
    and o.market_id = v_market_id
  for update;

  if not found then
    raise no_data_found;
  end if;

  update public.notification_outbox o
  set
    read_at = coalesce(o.read_at, now()),
    acknowledged_at = case
      when p_acknowledge and v_requires_ack
        then coalesce(o.acknowledged_at, now())
      else o.acknowledged_at
    end
  where o.id = p_outbox_id
  returning o.read_at, o.acknowledged_at
    into v_read_at, v_ack_at;

  if p_acknowledge and v_requires_ack and v_ack_before is null and v_ack_at is not null then
    insert into public.audit_logs(
      admin_id, actor_id, action, entity_type, entity_id, after_data
    )
    values(
      v_market_id,
      null,
      'receipt_acknowledged',
      'notification_outbox',
      p_outbox_id::text,
      jsonb_build_object(
        'customer_id', v_customer_id,
        'event_type', v_event_type,
        'acknowledged_at', v_ack_at
      )
    );
  end if;

  return jsonb_build_object(
    'id', p_outbox_id,
    'read_at', v_read_at,
    'acknowledged_at', v_ack_at,
    'requires_ack', v_requires_ack
  );
end;
$function$;

revoke all on function public.mark_customer_push_notification_read_service(uuid,text,text,text,boolean)
  from public, anon, authenticated;
grant execute on function public.mark_customer_push_notification_read_service(uuid,text,text,text,boolean)
  to service_role;

create or replace function public.read_customer_push_notification_history_service(
  p_token_hash text default null,
  p_endpoint text default null,
  p_device_secret_hash text default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  v_items jsonb := '[]'::jsonb;
begin
  select r.customer_id, r.market_id
    into v_customer_id, v_market_id
  from private.resolve_customer_push_identity(
    p_token_hash, p_endpoint, p_device_secret_hash
  ) r
  limit 1;

  perform 1
  from public.profiles customer
  join public.profiles tenant on tenant.id = v_market_id
  where customer.id = v_customer_id
    and customer.admin_id = v_market_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now());

  if not found then
    raise no_data_found;
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', row.id,
        'event_type', row.event_type,
        'event_record_id', row.event_record_id,
        'status', row.delivery_status,
        'created_at', row.created_at,
        'message', row.message,
        'amount', row.amount,
        'currency', row.currency,
        'read_at', row.read_at,
        'acknowledged_at', row.acknowledged_at,
        'requires_ack', row.requires_ack,
        'deep_link', row.deep_link,
        'receipt_id', row.receipt_id,
        'receipt_number', row.receipt_number,
        'period', row.period
      )
      order by row.created_at desc, row.id desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      o.id,
      o.event_type,
      o.event_record_id,
      o.created_at,
      o.read_at,
      o.acknowledged_at,
      o.requires_ack,
      o.receipt_id,
      coalesce(
        o.deep_link,
        case
          when o.event_type in ('debt_created','payment_created')
            then '/?view=transactions&event=' || o.event_record_id::text
          when o.event_type = 'monthly_statement'
            then '/?view=transactions&period=' || coalesce(o.payload ->> 'period','')
          else '/?view=notifications'
        end
      ) as deep_link,
      receipt.receipt_number,
      nullif(o.payload ->> 'period','') as period,
      nullif(o.payload ->> 'message', '') as message,
      case
        when (o.payload ->> 'amount') ~ '^-?[0-9]+([.][0-9]+)?$'
          then (o.payload ->> 'amount')::numeric
        else null
      end as amount,
      nullif(o.payload ->> 'currency', '') as currency,
      case
        when coalesce(del.device_count, 0) = 0 then 'no_device'
        when coalesce(del.pending_count, 0) > 0 then 'pending'
        when coalesce(del.sent_count, 0) > 0
             and coalesce(del.failed_count, 0) + coalesce(del.expired_count, 0) > 0
          then 'partial'
        when coalesce(del.sent_count, 0) > 0 then 'sent'
        when coalesce(del.failed_count, 0) + coalesce(del.expired_count, 0) > 0
          then 'failed'
        when o.status in ('pending', 'processing') then 'pending'
        when o.status = 'failed' then 'failed'
        else 'no_device'
      end as delivery_status
    from public.notification_outbox o
    left join public.receipt_documents receipt
      on receipt.id = o.receipt_id
    left join lateral (
      select
        count(*)::integer as device_count,
        count(*) filter (where d.status = 'sent')::integer as sent_count,
        count(*) filter (where d.status = 'failed')::integer as failed_count,
        count(*) filter (where d.status = 'expired')::integer as expired_count,
        count(*) filter (where d.status = 'pending')::integer as pending_count
      from public.notification_deliveries d
      where d.outbox_id = o.id
    ) del on true
    where o.market_id = v_market_id
      and o.customer_id = v_customer_id
    order by o.created_at desc, o.id desc
    limit v_limit
  ) row;

  return jsonb_build_object(
    'items', v_items,
    'limit', v_limit,
    'unread_count', (
      select count(*)::integer
      from public.notification_outbox o
      where o.market_id = v_market_id
        and o.customer_id = v_customer_id
        and o.read_at is null
    )
  );
end;
$function$;

revoke all on function public.read_customer_push_notification_history_service(text,text,text,integer)
  from public, anon, authenticated;
grant execute on function public.read_customer_push_notification_history_service(text,text,text,integer)
  to service_role;

create or replace function private.attach_receipt_to_customer_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_event_type text;
begin
  v_event_type := case new.source_type
    when 'debt' then 'debt_created'
    when 'payment' then 'payment_created'
    else null
  end;

  if v_event_type is null then
    return new;
  end if;

  update public.notification_outbox o
  set
    receipt_id = new.id,
    requires_ack = true,
    deep_link = '/?view=transactions&event=' || new.source_id::text ||
                '&receipt=' || new.id::text
  where o.market_id = new.admin_id
    and o.event_type = v_event_type
    and o.event_record_id = new.source_id;

  return new;
end;
$function$;

drop trigger if exists trg_attach_receipt_customer_notification
  on public.receipt_documents;
create trigger trg_attach_receipt_customer_notification
after insert on public.receipt_documents
for each row
execute function private.attach_receipt_to_customer_notification();

revoke all on function private.attach_receipt_to_customer_notification()
  from public, anon, authenticated;

with latest_receipt as (
  select distinct on (r.admin_id, r.source_type, r.source_id)
    r.id,
    r.admin_id,
    r.source_type,
    r.source_id
  from public.receipt_documents r
  where r.source_type in ('debt','payment')
  order by r.admin_id, r.source_type, r.source_id, r.version_no desc, r.created_at desc
)
update public.notification_outbox o
set
  receipt_id = r.id,
  requires_ack = true,
  deep_link = '/?view=transactions&event=' || r.source_id::text ||
              '&receipt=' || r.id::text
from latest_receipt r
where o.receipt_id is null
  and o.market_id = r.admin_id
  and o.event_record_id = r.source_id
  and (
    (o.event_type = 'debt_created' and r.source_type = 'debt')
    or (o.event_type = 'payment_created' and r.source_type = 'payment')
  );

create or replace function private.enqueue_customer_debt_limit_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_market_name text := '';
begin
  if new.role <> 'customer'
     or new.admin_id is null
     or new.debt_limit is not distinct from old.debt_limit then
    return new;
  end if;

  if not private.customer_portal_enabled(new.id, new.admin_id) then
    return new;
  end if;

  select coalesce(p.market_name,'')
    into v_market_name
  from public.profiles p
  where p.id = new.admin_id
    and p.role = 'admin';

  begin
    perform public.enqueue_customer_push_event_service(
      new.admin_id,
      new.id,
      'debt_limit_changed',
      new.id,
      'debt_limit_changed:' || new.id::text || ':' || txid_current()::text,
      jsonb_build_object(
        'old_limit', old.debt_limit,
        'new_limit', new.debt_limit,
        'market_name', v_market_name,
        'occurred_at', now()
      )
    );
  exception when others then
    raise warning 'customer debt limit push deferred for %: %', new.id, sqlerrm;
  end;

  return new;
end;
$function$;

drop trigger if exists trg_customer_debt_limit_push on public.profiles;
create trigger trg_customer_debt_limit_push
after update of debt_limit on public.profiles
for each row
execute function private.enqueue_customer_debt_limit_change();

revoke all on function private.enqueue_customer_debt_limit_change()
  from public, anon, authenticated;

create or replace function public.set_debt_installment_schedule(
  p_debt_id uuid,
  p_schedule jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_admin_id uuid := private.current_admin_id();
  v_customer_id uuid;
  v_item jsonb;
  v_no integer := 0;
  v_due date;
  v_amount numeric;
begin
  if v_admin_id is null
     or not (
       private."current_role"() = 'admin'
       or private.employee_has_permission('edit_debts')
     ) then
    raise exception 'forbidden' using errcode='42501';
  end if;

  if jsonb_typeof(p_schedule) <> 'array'
     or jsonb_array_length(p_schedule) < 1
     or jsonb_array_length(p_schedule) > 60 then
    raise exception 'invalid_installment_schedule' using errcode='22023';
  end if;

  select d.customer_id
    into v_customer_id
  from public.debts d
  join public.profiles c on c.id = d.customer_id
  where d.id = p_debt_id
    and d.is_deleted = false
    and c.role = 'customer'
    and c.admin_id = v_admin_id;

  if v_customer_id is null then
    raise exception 'debt_not_found_or_forbidden' using errcode='42501';
  end if;

  update public.debt_installments
  set status = 'cancelled', updated_at = now()
  where debt_id = p_debt_id
    and status = 'pending'
    and admin_id = v_admin_id;

  for v_item in select value from jsonb_array_elements(p_schedule)
  loop
    v_no := v_no + 1;
    begin
      v_due := (v_item ->> 'due_date')::date;
      v_amount := (v_item ->> 'amount')::numeric;
    exception when others then
      raise exception 'invalid_installment_schedule' using errcode='22023';
    end;

    if v_due is null or v_amount is null or v_amount <= 0 then
      raise exception 'invalid_installment_schedule' using errcode='22023';
    end if;

    insert into public.debt_installments(
      admin_id, customer_id, debt_id, installment_no,
      amount, due_date, status, created_by
    )
    values(
      v_admin_id, v_customer_id, p_debt_id, v_no,
      v_amount, v_due, 'pending', (select auth.uid())
    )
    on conflict (debt_id, installment_no)
    do update set
      amount = excluded.amount,
      due_date = excluded.due_date,
      status = 'pending',
      paid_at = null,
      created_by = excluded.created_by,
      updated_at = now();
  end loop;

  return (
    select coalesce(jsonb_agg(to_jsonb(i) order by i.installment_no),'[]'::jsonb)
    from public.debt_installments i
    where i.debt_id = p_debt_id
      and i.admin_id = v_admin_id
      and i.status = 'pending'
  );
end;
$function$;

revoke all on function public.set_debt_installment_schedule(uuid,jsonb)
  from public, anon;
grant execute on function public.set_debt_installment_schedule(uuid,jsonb)
  to authenticated;

create or replace function private.close_installments_when_debt_paid()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.remaining > 0 and new.remaining <= 0 then
    update public.debt_installments i
    set status = 'paid',
        paid_at = coalesce(i.paid_at, now()),
        updated_at = now()
    where i.debt_id = new.id
      and i.status = 'pending';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_close_installments_when_debt_paid on public.debts;
create trigger trg_close_installments_when_debt_paid
after update of remaining on public.debts
for each row
execute function private.close_installments_when_debt_paid();

revoke all on function private.close_installments_when_debt_paid()
  from public, anon, authenticated;

create or replace function public.enqueue_customer_due_reminders_service()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
begin
  insert into public.notification_outbox(
    market_id, customer_id, event_type, event_record_id,
    idempotency_key, payload, deep_link, requires_ack
  )
  select
    customer.admin_id,
    debt.customer_id,
    'due_reminder',
    debt.id,
    'due_reminder:' || debt.id::text || ':' ||
      case
        when debt.due_date - current_date = 3 then 'pre3'
        when debt.due_date - current_date = 1 then 'pre1'
        when debt.due_date = current_date then 'today'
        else 'overdue' || (current_date - debt.due_date)::text
      end || ':' || debt.due_date::text,
    jsonb_build_object(
      'amount',
        case
          when upper(coalesce(debt.currency,'IQD'))='USD'
               and coalesce(debt.dollar_rate,0) > 0
            then round((debt.remaining / debt.dollar_rate)::numeric,2)
          else debt.remaining
        end,
      'currency',
        case
          when upper(coalesce(debt.currency,'IQD'))='USD'
               and coalesce(debt.dollar_rate,0) > 0
            then 'USD'
          else 'IQD'
        end,
      'remaining_iqd', balances.remaining_iqd,
      'market_name', tenant.market_name,
      'occurred_at', now(),
      'due_date', debt.due_date,
      'overdue', debt.due_date < current_date,
      'days_until_due', greatest(debt.due_date - current_date,0),
      'days_overdue', greatest(current_date - debt.due_date,0)
    ),
    '/?view=transactions&event=' || debt.id::text,
    false
  from public.debts debt
  join public.profiles customer on customer.id = debt.customer_id
  join public.profiles tenant on tenant.id = customer.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id = debt.customer_id
   and pref.market_id = customer.admin_id
  join lateral (
    select coalesce(sum(item.remaining),0)::numeric as remaining_iqd
    from public.debts item
    where item.customer_id = debt.customer_id
      and item.is_deleted = false
      and item.remaining > 0
  ) balances on true
  where debt.is_deleted = false
    and debt.remaining > 0
    and debt.due_date is not null
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
    and coalesce(pref.due_reminders,true) = true
    and private.customer_portal_enabled(debt.customer_id, customer.admin_id)
    and (
      debt.due_date - current_date in (3,1,0)
      or (
        debt.due_date < current_date
        and (
          current_date - debt.due_date in (1,3,7,14,30)
          or (
            current_date - debt.due_date > 30
            and mod(current_date - debt.due_date,30) = 0
          )
        )
      )
    )
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

revoke all on function public.enqueue_customer_due_reminders_service()
  from public, anon, authenticated;
grant execute on function public.enqueue_customer_due_reminders_service()
  to service_role;

create or replace function public.enqueue_customer_installment_reminders_service()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
begin
  insert into public.notification_outbox(
    market_id, customer_id, event_type, event_record_id,
    idempotency_key, payload, deep_link, requires_ack
  )
  select
    i.admin_id,
    i.customer_id,
    'installment_reminder',
    i.id,
    'installment_reminder:' || i.id::text || ':' ||
      case
        when i.due_date - current_date = 3 then 'pre3'
        when i.due_date - current_date = 1 then 'pre1'
        when i.due_date = current_date then 'today'
        else 'overdue' || (current_date - i.due_date)::text
      end || ':' || i.due_date::text,
    jsonb_build_object(
      'amount', i.amount,
      'currency', case
        when upper(coalesce(d.currency,'IQD'))='USD'
             and coalesce(d.dollar_rate,0) > 0 then 'USD'
        else 'IQD'
      end,
      'market_name', tenant.market_name,
      'occurred_at', now(),
      'due_date', i.due_date,
      'overdue', i.due_date < current_date,
      'installment_no', i.installment_no,
      'debt_id', i.debt_id,
      'days_until_due', greatest(i.due_date - current_date,0),
      'days_overdue', greatest(current_date - i.due_date,0)
    ),
    '/?view=transactions&event=' || i.debt_id::text,
    false
  from public.debt_installments i
  join public.debts d on d.id = i.debt_id
  join public.profiles customer on customer.id = i.customer_id
  join public.profiles tenant on tenant.id = i.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id = i.customer_id
   and pref.market_id = i.admin_id
  where i.status = 'pending'
    and d.is_deleted = false
    and d.remaining > 0
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and coalesce(pref.installment_reminders,true) = true
    and private.customer_portal_enabled(i.customer_id,i.admin_id)
    and (
      i.due_date - current_date in (3,1,0)
      or (
        i.due_date < current_date
        and (
          current_date - i.due_date in (1,3,7,14,30)
          or (
            current_date - i.due_date > 30
            and mod(current_date - i.due_date,30) = 0
          )
        )
      )
    )
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

revoke all on function public.enqueue_customer_installment_reminders_service()
  from public, anon, authenticated;
grant execute on function public.enqueue_customer_installment_reminders_service()
  to service_role;

create or replace function public.enqueue_customer_monthly_statements_service()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_inserted integer := 0;
  v_start timestamptz := date_trunc('month', now()) - interval '1 month';
  v_end timestamptz := date_trunc('month', now());
  v_period text := to_char(date_trunc('month', now()) - interval '1 month','YYYY-MM');
begin
  insert into public.notification_outbox(
    market_id, customer_id, event_type, event_record_id,
    idempotency_key, payload, deep_link, requires_ack
  )
  select
    customer.admin_id,
    customer.id,
    'monthly_statement',
    customer.id,
    'monthly_statement:' || customer.id::text || ':' || v_period,
    jsonb_build_object(
      'market_name', tenant.market_name,
      'occurred_at', now(),
      'period', v_period,
      'total_debt', coalesce(monthly.total_debt,0),
      'total_paid', coalesce(monthly.total_paid,0),
      'remaining_iqd', coalesce(balance.remaining_iqd,0)
    ),
    '/?view=transactions&period=' || v_period,
    false
  from public.profiles customer
  join public.profiles tenant on tenant.id = customer.admin_id
  left join public.customer_notification_preferences pref
    on pref.customer_id = customer.id
   and pref.market_id = customer.admin_id
  left join lateral (
    select
      coalesce(sum(d.amount),0)::numeric as total_debt,
      coalesce((
        select sum(p.amount)
        from public.payments p
        join public.debts pd on pd.id = p.debt_id
        where pd.customer_id = customer.id
          and p.created_at >= v_start
          and p.created_at < v_end
      ),0)::numeric as total_paid
    from public.debts d
    where d.customer_id = customer.id
      and d.is_deleted = false
      and coalesce(d.custom_date,d.created_at) >= v_start
      and coalesce(d.custom_date,d.created_at) < v_end
  ) monthly on true
  left join lateral (
    select coalesce(sum(d.remaining),0)::numeric as remaining_iqd
    from public.debts d
    where d.customer_id = customer.id
      and d.is_deleted = false
      and d.remaining > 0
  ) balance on true
  where customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
    and tenant.role = 'admin'
    and tenant.active = true
    and tenant.approved = true
    and (tenant.is_system_owner or tenant.subscription_end is null or tenant.subscription_end >= now())
    and coalesce(pref.monthly_statements,true) = true
    and private.customer_portal_enabled(customer.id,customer.admin_id)
  on conflict (idempotency_key) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$function$;

revoke all on function public.enqueue_customer_monthly_statements_service()
  from public, anon, authenticated;
grant execute on function public.enqueue_customer_monthly_statements_service()
  to service_role;

do $block$
declare
  v_job record;
begin
  for v_job in
    select jobid from cron.job
    where jobname in (
      'zhirox_customer_due_reminders',
      'zhirox_customer_installment_reminders',
      'zhirox_customer_monthly_statements'
    )
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;

  perform cron.schedule(
    'zhirox_customer_due_reminders',
    '5 5 * * *',
    'select public.enqueue_customer_due_reminders_service();'
  );

  perform cron.schedule(
    'zhirox_customer_installment_reminders',
    '10 5 * * *',
    'select public.enqueue_customer_installment_reminders_service();'
  );

  perform cron.schedule(
    'zhirox_customer_monthly_statements',
    '20 5 1 * *',
    'select public.enqueue_customer_monthly_statements_service();'
  );
end;
$block$;
