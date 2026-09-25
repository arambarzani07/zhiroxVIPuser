
-- Make the Daftar-compatible projection authoritative for current Daftar rows.
--
-- Current mirrored rows appear exactly once. Local records with any historical
-- Daftar/remote mapping are not re-emitted when the current mirror no longer
-- contains them; those rows remain in the local audit ledger but are excluded
-- from the current Daftar-compatible read model.
--
-- Truly native ZHIROX rows (no remote mapping at all) remain visible with
-- synthetic zhirox:* IDs until outbound sync assigns a remote ID.

create or replace view private.zhirox_daftar_transactions_v1 as
with source_for_admin as (
  select distinct on (s.admin_id)
    s.admin_id,
    s.id as sync_source_id,
    s.legacy_user_id,
    s.source_fingerprint
  from public.daftar_sync_sources s
  where s.enabled=true
  order by
    s.admin_id,
    (s.sync_mode='zhirox_primary') desc,
    s.created_at
),
mirror_rows as (
  select
    src.admin_id,
    customer.local_customer_id,
    coalesce(nullif(m.payload->>'id',''),m.source_id)::text as id,
    coalesce(nullif(m.payload->>'user_id',''),src.legacy_user_id::text)::text as user_id,
    coalesce(customer.id,nullif(m.payload->>'contact_id',''))::text as contact_id,
    upper(coalesce(nullif(m.payload->>'transaction_type',''),'LOAN'))::text as transaction_type,
    coalesce(nullif(m.payload->>'amount','')::numeric,0)::numeric as amount,
    upper(coalesce(nullif(m.payload->>'currency',''),'IQD'))::text as currency,
    coalesce(
      nullif(m.payload->>'transaction_date','')::timestamptz,
      nullif(m.payload->>'created_at','')::timestamptz,
      m.first_mirrored_at
    ) as transaction_date,
    coalesce(m.payload->>'note','')::text as note,
    coalesce(
      nullif(m.payload->>'created_at','')::timestamptz,
      nullif(m.payload->>'transaction_date','')::timestamptz,
      m.first_mirrored_at
    ) as created_at,
    coalesce(
      nullif(m.payload->>'updated_at','')::timestamptz,
      m.last_mirrored_at,
      nullif(m.payload->>'created_at','')::timestamptz,
      m.first_mirrored_at
    ) as updated_at,
    1::smallint as priority
  from public.daftar_mirror_transactions m
  join source_for_admin src
    on src.sync_source_id=m.sync_source_id
  left join private.zhirox_daftar_contacts_v1 customer
    on customer.admin_id=src.admin_id
   and customer.id=nullif(m.payload->>'contact_id','')
  where upper(coalesce(m.payload->>'transaction_type','')) in ('LOAN','PAYMENT')
),
native_loan_rows as (
  select
    customer.admin_id,
    d.customer_id as local_customer_id,
    ('zhirox:loan:' || d.id::text)::text as id,
    customer.user_id,
    customer.id as contact_id,
    'LOAN'::text as transaction_type,
    d.amount::numeric as amount,
    upper(coalesce(nullif(d.currency,''),'IQD'))::text as currency,
    coalesce(d.custom_date,d.created_at) as transaction_date,
    coalesce(d.description,'')::text as note,
    d.created_at,
    d.updated_at,
    20::smallint as priority
  from public.debts d
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id=d.customer_id
  where d.is_deleted=false
    and not exists (
      select 1
      from public.legacy_import_links l
      where l.admin_id=customer.admin_id
        and l.entity_kind='debt'
        and l.target_id=d.id
    )
),
native_payment_rows as (
  select
    customer.admin_id,
    d.customer_id as local_customer_id,
    ('zhirox:payment:' || pay.id::text)::text as id,
    customer.user_id,
    customer.id as contact_id,
    'PAYMENT'::text as transaction_type,
    pay.amount::numeric as amount,
    upper(coalesce(nullif(d.currency,''),'IQD'))::text as currency,
    pay.created_at as transaction_date,
    coalesce(pay.note,'')::text as note,
    pay.created_at,
    pay.created_at as updated_at,
    20::smallint as priority
  from public.payments pay
  join public.debts d on d.id=pay.debt_id
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id=d.customer_id
  where not exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id=customer.admin_id
      and l.entity_kind='payment'
      and l.target_id=pay.id
  )
),
native_general_payment_rows as (
  select
    customer.admin_id,
    g.customer_id as local_customer_id,
    ('zhirox:general-payment:' || g.id::text)::text as id,
    customer.user_id,
    customer.id as contact_id,
    'PAYMENT'::text as transaction_type,
    g.amount::numeric as amount,
    'IQD'::text as currency,
    g.created_at as transaction_date,
    coalesce(g.note,'')::text as note,
    g.created_at,
    g.created_at as updated_at,
    20::smallint as priority
  from public.customer_general_payments g
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id=g.customer_id
   and customer.admin_id=g.admin_id
  where not exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id=g.admin_id
      and l.entity_kind='payment'
      and l.target_id=g.id
  )
),
all_rows as (
  select * from mirror_rows
  union all
  select * from native_loan_rows
  union all
  select * from native_payment_rows
  union all
  select * from native_general_payment_rows
)
select distinct on (r.admin_id,r.id)
  r.admin_id,
  r.local_customer_id,
  r.id,
  r.user_id,
  r.contact_id,
  r.transaction_type,
  r.amount,
  r.currency,
  r.transaction_date,
  r.note,
  r.created_at,
  r.updated_at
from all_rows r
order by r.admin_id,r.id,r.priority,r.updated_at desc nulls last;

revoke all on private.zhirox_daftar_transactions_v1
  from public,anon,authenticated;
grant select on private.zhirox_daftar_transactions_v1 to service_role;

-- Backfill active ZHIROX-native debts that predate outbound sync.
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
  'debt',
  d.id,
  'create',
  'zhirox:' || s.id::text || ':debt:' || d.id::text || ':create:' ||
    md5(jsonb_build_object(
      'id',d.id,
      'customer_id',d.customer_id,
      'amount',d.amount,
      'currency',coalesce(d.currency,'IQD'),
      'description',coalesce(d.description,''),
      'transaction_date',coalesce(d.custom_date,d.created_at),
      'created_at',d.created_at,
      'updated_at',coalesce(d.updated_at,d.created_at),
      'is_deleted',coalesce(d.is_deleted,false)
    )::text),
  jsonb_build_object(
    'id',d.id,
    'customer_id',d.customer_id,
    'amount',d.amount,
    'currency',coalesce(d.currency,'IQD'),
    'description',coalesce(d.description,''),
    'transaction_date',coalesce(d.custom_date,d.created_at),
    'created_at',d.created_at,
    'updated_at',coalesce(d.updated_at,d.created_at),
    'is_deleted',coalesce(d.is_deleted,false)
  ),
  null,
  now()
from public.debts d
join public.profiles c
  on c.id=d.customer_id
 and c.role='customer'
join public.daftar_sync_sources s
  on s.admin_id=c.admin_id
 and s.enabled=true
 and s.sync_mode='zhirox_primary'
 and s.outbound_sync_enabled=true
 and s.outbound_write_contract_status='verified'
where d.is_deleted=false
  and not exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id=s.admin_id
      and l.entity_kind='debt'
      and l.target_id=d.id
  )
  and not exists (
    select 1
    from public.daftar_outbound_events e
    where e.sync_source_id=s.id
      and e.entity_kind='debt'
      and e.entity_id=d.id
      and e.operation='create'
      and e.status in ('sent','skipped')
  )
on conflict(idempotency_key) do update
set payload_snapshot=excluded.payload_snapshot,
    status=case
      when public.daftar_outbound_events.status in ('sent','skipped')
        then public.daftar_outbound_events.status
      else 'pending'
    end,
    next_attempt_at=least(
      public.daftar_outbound_events.next_attempt_at,
      excluded.next_attempt_at
    ),
    updated_at=now();

-- Backfill active ZHIROX-native per-debt payments that predate outbound sync.
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
  pay.id,
  'create',
  'zhirox:' || s.id::text || ':payment:' || pay.id::text || ':create:' ||
    md5(jsonb_build_object(
      'id',pay.id,
      'debt_id',pay.debt_id,
      'customer_id',d.customer_id,
      'amount',pay.amount,
      'currency',coalesce(d.currency,'IQD'),
      'note',coalesce(pay.note,''),
      'transaction_date',pay.created_at,
      'created_at',pay.created_at,
      'payment_scope','debt',
      'source_table','payments'
    )::text),
  jsonb_build_object(
    'id',pay.id,
    'debt_id',pay.debt_id,
    'customer_id',d.customer_id,
    'amount',pay.amount,
    'currency',coalesce(d.currency,'IQD'),
    'note',coalesce(pay.note,''),
    'transaction_date',pay.created_at,
    'created_at',pay.created_at,
    'payment_scope','debt',
    'source_table','payments'
  ),
  null,
  now()
from public.payments pay
join public.debts d on d.id=pay.debt_id
join public.profiles c
  on c.id=d.customer_id
 and c.role='customer'
join public.daftar_sync_sources s
  on s.admin_id=c.admin_id
 and s.enabled=true
 and s.sync_mode='zhirox_primary'
 and s.outbound_sync_enabled=true
 and s.outbound_write_contract_status='verified'
where not exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id=s.admin_id
      and l.entity_kind='payment'
      and l.target_id=pay.id
  )
  and not exists (
    select 1
    from public.daftar_outbound_events e
    where e.sync_source_id=s.id
      and e.entity_kind='payment'
      and e.entity_id=pay.id
      and e.operation='create'
      and e.status in ('sent','skipped')
  )
on conflict(idempotency_key) do update
set payload_snapshot=excluded.payload_snapshot,
    status=case
      when public.daftar_outbound_events.status in ('sent','skipped')
        then public.daftar_outbound_events.status
      else 'pending'
    end,
    next_attempt_at=least(
      public.daftar_outbound_events.next_attempt_at,
      excluded.next_attempt_at
    ),
    updated_at=now();
