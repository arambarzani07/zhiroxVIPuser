-- Make the Daftar mirror authoritative for remote transaction identities.
--
-- The first compatibility projection reconstructed remote PAYMENT rows from
-- current local allocation links. Historical link churn can leave old target
-- IDs behind, so not every mirrored PAYMENT necessarily has a live local
-- allocation target. This replacement includes every current mirror
-- transaction first, then merges native/local ZHIROX fallbacks on top. The
-- final DISTINCT ON keeps one row per Daftar transaction ID.

create or replace view private.zhirox_daftar_transactions_v1 as
with source_for_admin as (
  select distinct on (s.admin_id)
    s.admin_id,
    s.id as sync_source_id,
    s.legacy_user_id,
    s.source_fingerprint
  from public.daftar_sync_sources s
  where s.enabled = true
  order by
    s.admin_id,
    (s.sync_mode = 'zhirox_primary') desc,
    s.created_at
),
mirror_rows as (
  select
    src.admin_id,
    customer.local_customer_id,
    coalesce(nullif(m.payload->>'id', ''), m.source_id)::text as id,
    coalesce(
      nullif(m.payload->>'user_id', ''),
      src.legacy_user_id::text
    )::text as user_id,
    coalesce(
      customer.id,
      nullif(m.payload->>'contact_id', '')
    )::text as contact_id,
    upper(coalesce(
      nullif(m.payload->>'transaction_type', ''),
      'LOAN'
    ))::text as transaction_type,
    coalesce(nullif(m.payload->>'amount', '')::numeric, 0)::numeric as amount,
    upper(coalesce(
      nullif(m.payload->>'currency', ''),
      'IQD'
    ))::text as currency,
    coalesce(
      nullif(m.payload->>'transaction_date', '')::timestamptz,
      nullif(m.payload->>'created_at', '')::timestamptz,
      m.first_mirrored_at
    ) as transaction_date,
    coalesce(m.payload->>'note', '')::text as note,
    coalesce(
      nullif(m.payload->>'created_at', '')::timestamptz,
      nullif(m.payload->>'transaction_date', '')::timestamptz,
      m.first_mirrored_at
    ) as created_at,
    coalesce(
      nullif(m.payload->>'updated_at', '')::timestamptz,
      m.last_mirrored_at,
      nullif(m.payload->>'created_at', '')::timestamptz,
      m.first_mirrored_at
    ) as updated_at,
    1::smallint as priority
  from public.daftar_mirror_transactions m
  join source_for_admin src
    on src.sync_source_id = m.sync_source_id
  left join private.zhirox_daftar_contacts_v1 customer
    on customer.admin_id = src.admin_id
   and customer.id = nullif(m.payload->>'contact_id', '')
  where upper(coalesce(m.payload->>'transaction_type', '')) in ('LOAN', 'PAYMENT')
),
loan_rows as (
  select
    customer.admin_id,
    d.customer_id as local_customer_id,
    coalesce(link.source_id, 'zhirox:loan:' || d.id::text) as id,
    customer.user_id,
    customer.id as contact_id,
    'LOAN'::text as transaction_type,
    d.amount::numeric as amount,
    upper(coalesce(nullif(d.currency, ''), 'IQD'))::text as currency,
    coalesce(d.custom_date, d.created_at) as transaction_date,
    coalesce(d.description, '')::text as note,
    d.created_at,
    d.updated_at,
    10::smallint as priority
  from public.debts d
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id = d.customer_id
  left join source_for_admin src
    on src.admin_id = customer.admin_id
  left join lateral (
    select l.source_id
    from public.legacy_import_links l
    where l.admin_id = customer.admin_id
      and l.entity_kind = 'debt'
      and l.target_id = d.id
      and (
        src.source_fingerprint is null
        or l.source_fingerprint = src.source_fingerprint
      )
    order by l.created_at desc
    limit 1
  ) link on true
  where d.is_deleted = false
),
linked_payment_parts as (
  select
    l.admin_id,
    src.sync_source_id,
    src.legacy_user_id,
    l.source_fingerprint,
    split_part(l.source_id, ':', 1) as remote_id,
    d.customer_id,
    pay.amount::numeric as amount,
    upper(coalesce(nullif(d.currency, ''), 'IQD'))::text as currency,
    coalesce(pay.note, '')::text as note,
    pay.created_at,
    pay.created_at as updated_at
  from public.legacy_import_links l
  join source_for_admin src
    on src.admin_id = l.admin_id
   and src.source_fingerprint = l.source_fingerprint
  join public.payments pay
    on pay.id = l.target_id
  join public.debts d
    on d.id = pay.debt_id
  where l.entity_kind = 'payment'
    and l.source_id ~ '^[0-9]+:[0-9]+$'

  union all

  select
    l.admin_id,
    src.sync_source_id,
    src.legacy_user_id,
    l.source_fingerprint,
    split_part(l.source_id, ':', 1) as remote_id,
    g.customer_id,
    g.amount::numeric as amount,
    'IQD'::text as currency,
    coalesce(g.note, '')::text as note,
    g.created_at,
    g.created_at as updated_at
  from public.legacy_import_links l
  join source_for_admin src
    on src.admin_id = l.admin_id
   and src.source_fingerprint = l.source_fingerprint
  join public.customer_general_payments g
    on g.id = l.target_id
   and g.admin_id = l.admin_id
  where l.entity_kind = 'payment'
    and l.source_id ~ '^[0-9]+:[0-9]+$'
),
linked_payment_groups as (
  select
    p.admin_id,
    p.sync_source_id,
    p.legacy_user_id,
    p.source_fingerprint,
    p.remote_id,
    p.customer_id,
    sum(p.amount)::numeric as local_amount,
    min(p.currency)::text as local_currency,
    coalesce(
      max(nullif(p.note, '')) filter (where nullif(p.note, '') is not null),
      ''
    )::text as local_note,
    min(p.created_at) as local_created_at,
    max(p.updated_at) as local_updated_at
  from linked_payment_parts p
  group by
    p.admin_id,
    p.sync_source_id,
    p.legacy_user_id,
    p.source_fingerprint,
    p.remote_id,
    p.customer_id
),
linked_payment_rows as (
  select
    g.admin_id,
    g.customer_id as local_customer_id,
    g.remote_id::text as id,
    g.legacy_user_id::text as user_id,
    customer.id as contact_id,
    'PAYMENT'::text as transaction_type,
    coalesce(
      nullif(m.payload->>'amount', '')::numeric,
      g.local_amount
    )::numeric as amount,
    upper(coalesce(
      nullif(m.payload->>'currency', ''),
      g.local_currency,
      'IQD'
    ))::text as currency,
    coalesce(
      nullif(m.payload->>'transaction_date', '')::timestamptz,
      g.local_created_at
    ) as transaction_date,
    coalesce(m.payload->>'note', g.local_note, '')::text as note,
    coalesce(
      nullif(m.payload->>'created_at', '')::timestamptz,
      g.local_created_at
    ) as created_at,
    coalesce(
      nullif(m.payload->>'updated_at', '')::timestamptz,
      g.local_updated_at,
      g.local_created_at
    ) as updated_at,
    10::smallint as priority
  from linked_payment_groups g
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id = g.customer_id
  left join public.daftar_mirror_transactions m
    on m.sync_source_id = g.sync_source_id
   and m.source_id = g.remote_id
),
native_payment_rows as (
  select
    customer.admin_id,
    d.customer_id as local_customer_id,
    'zhirox:payment:' || pay.id::text as id,
    customer.user_id,
    customer.id as contact_id,
    'PAYMENT'::text as transaction_type,
    pay.amount::numeric as amount,
    upper(coalesce(nullif(d.currency, ''), 'IQD'))::text as currency,
    pay.created_at as transaction_date,
    coalesce(pay.note, '')::text as note,
    pay.created_at,
    pay.created_at as updated_at,
    20::smallint as priority
  from public.payments pay
  join public.debts d
    on d.id = pay.debt_id
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id = d.customer_id
  where not exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id = customer.admin_id
      and l.entity_kind = 'payment'
      and l.target_id = pay.id
  )
),
native_general_payment_rows as (
  select
    customer.admin_id,
    g.customer_id as local_customer_id,
    'zhirox:general-payment:' || g.id::text as id,
    customer.user_id,
    customer.id as contact_id,
    'PAYMENT'::text as transaction_type,
    g.amount::numeric as amount,
    'IQD'::text as currency,
    g.created_at as transaction_date,
    coalesce(g.note, '')::text as note,
    g.created_at,
    g.created_at as updated_at,
    20::smallint as priority
  from public.customer_general_payments g
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id = g.customer_id
   and customer.admin_id = g.admin_id
  where not exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id = g.admin_id
      and l.entity_kind = 'payment'
      and l.target_id = g.id
  )
),
zero_event_candidates as (
  select distinct on (
    customer.admin_id,
    nullif(e.metadata->>'legacy_transaction_id', '')
  )
    customer.admin_id,
    e.customer_id as local_customer_id,
    nullif(e.metadata->>'legacy_transaction_id', '') as id,
    customer.user_id,
    customer.id as contact_id,
    upper(coalesce(
      nullif(e.metadata->>'legacy_transaction_type', ''),
      case
        when e.event_type like 'payment_%' then 'PAYMENT'
        else 'LOAN'
      end
    ))::text as transaction_type,
    0::numeric as amount,
    upper(coalesce(nullif(e.currency, ''), 'IQD'))::text as currency,
    coalesce(
      nullif(e.metadata->>'source_created_at', '')::timestamptz,
      e.created_at
    ) as transaction_date,
    coalesce(e.description, '')::text as note,
    coalesce(
      nullif(e.metadata->>'source_created_at', '')::timestamptz,
      e.created_at
    ) as created_at,
    coalesce(
      nullif(e.metadata->>'source_updated_at', '')::timestamptz,
      e.created_at
    ) as updated_at,
    30::smallint as priority
  from public.financial_events e
  join private.zhirox_daftar_contacts_v1 customer
    on customer.local_customer_id = e.customer_id
  where coalesce((e.metadata->>'legacy_zero_amount')::boolean, false) = true
    and nullif(e.metadata->>'legacy_transaction_id', '') is not null
  order by
    customer.admin_id,
    nullif(e.metadata->>'legacy_transaction_id', ''),
    e.created_at desc,
    e.id desc
),
all_rows as (
  select * from mirror_rows
  union all
  select * from loan_rows
  union all
  select * from linked_payment_rows
  union all
  select * from native_payment_rows
  union all
  select * from native_general_payment_rows
  union all
  select * from zero_event_candidates
)
select distinct on (r.admin_id, r.id)
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
order by
  r.admin_id,
  r.id,
  r.priority,
  r.updated_at desc nulls last;


revoke all on private.zhirox_daftar_transactions_v1
  from public, anon, authenticated;
grant select on private.zhirox_daftar_transactions_v1 to service_role;
