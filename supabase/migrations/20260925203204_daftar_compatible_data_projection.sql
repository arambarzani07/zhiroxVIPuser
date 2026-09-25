-- Daftar-compatible canonical read model for ZHIROX.
--
-- ZHIROX keeps richer internal accounting tables (debts, per-debt payments,
-- customer-wide payments). Daftar Qarz exposes a simpler contact + transaction
-- model. These private projections preserve ZHIROX accounting semantics while
-- presenting the same field vocabulary and one logical PAYMENT row per Daftar
-- transaction, including inbound payments that were split into allocations.

create or replace view private.zhirox_daftar_contacts_v1 as
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
)
select
  p.admin_id,
  p.id as local_customer_id,
  coalesce(link.source_id, 'zhirox:contact:' || p.id::text) as id,
  coalesce(src.legacy_user_id::text, 'zhirox:user:' || p.admin_id::text) as user_id,
  coalesce(p.name, '')::text as name,
  coalesce(p.phone, '')::text as phone,
  p.created_at,
  p.updated_at
from public.profiles p
left join source_for_admin src
  on src.admin_id = p.admin_id
left join lateral (
  select l.source_id
  from public.legacy_import_links l
  where l.admin_id = p.admin_id
    and l.entity_kind = 'customer'
    and l.target_id = p.id
    and (
      src.source_fingerprint is null
      or l.source_fingerprint = src.source_fingerprint
    )
  order by l.created_at desc
  limit 1
) link on true
where p.role = 'customer'
  and p.admin_id is not null;

revoke all on private.zhirox_daftar_contacts_v1
  from public, anon, authenticated;
grant select on private.zhirox_daftar_contacts_v1 to service_role;

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

create or replace function public.get_my_daftar_compatible_contacts(
  p_limit integer default 200,
  p_offset integer default 0
)
returns table(
  id text,
  user_id text,
  name text,
  phone text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    c.id,
    c.user_id,
    c.name,
    c.phone,
    c.created_at,
    c.updated_at
  from private.zhirox_daftar_contacts_v1 c
  where auth.uid() is not null
    and private."current_role"() in ('admin', 'employee')
    and c.admin_id = private.current_admin_id()
  order by c.created_at, c.id
  limit greatest(1, least(coalesce(p_limit, 200), 1000))
  offset greatest(coalesce(p_offset, 0), 0);
$function$;

revoke all on function public.get_my_daftar_compatible_contacts(integer,integer)
  from public, anon;
grant execute on function public.get_my_daftar_compatible_contacts(integer,integer)
  to authenticated, service_role;

create or replace function public.get_my_daftar_compatible_transactions(
  p_contact_id text default null,
  p_limit integer default 500,
  p_offset integer default 0
)
returns table(
  id text,
  user_id text,
  contact_id text,
  transaction_type text,
  amount numeric,
  currency text,
  transaction_date timestamptz,
  note text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    t.id,
    t.user_id,
    t.contact_id,
    t.transaction_type,
    t.amount,
    t.currency,
    t.transaction_date,
    t.note,
    t.created_at,
    t.updated_at
  from private.zhirox_daftar_transactions_v1 t
  where auth.uid() is not null
    and private."current_role"() in ('admin', 'employee')
    and t.admin_id = private.current_admin_id()
    and (
      nullif(trim(coalesce(p_contact_id, '')), '') is null
      or t.contact_id = trim(p_contact_id)
    )
  order by t.transaction_date, t.created_at, t.id
  limit greatest(1, least(coalesce(p_limit, 500), 2000))
  offset greatest(coalesce(p_offset, 0), 0);
$function$;

revoke all on function public.get_my_daftar_compatible_transactions(text,integer,integer)
  from public, anon;
grant execute on function public.get_my_daftar_compatible_transactions(text,integer,integer)
  to authenticated, service_role;

create or replace function public.get_my_daftar_compatible_summary()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  with tenant as (
    select private.current_admin_id() as admin_id
    where auth.uid() is not null
      and private."current_role"() in ('admin', 'employee')
  ),
  contacts as (
    select count(*)::bigint as total_customers
    from private.zhirox_daftar_contacts_v1 c
    where c.admin_id = (select admin_id from tenant)
  ),
  totals as (
    select
      t.currency,
      coalesce(sum(t.amount) filter (where t.transaction_type = 'LOAN'), 0)::numeric
        as total_loan,
      coalesce(sum(t.amount) filter (where t.transaction_type = 'PAYMENT'), 0)::numeric
        as total_payment
    from private.zhirox_daftar_transactions_v1 t
    where t.admin_id = (select admin_id from tenant)
    group by t.currency
  )
  select jsonb_build_object(
    'total_customers', coalesce((select total_customers from contacts), 0),
    'currencies', coalesce(
      (
        select jsonb_object_agg(
          totals.currency,
          jsonb_build_object(
            'total_loan', totals.total_loan,
            'total_payment', totals.total_payment,
            'balance', totals.total_loan - totals.total_payment
          )
          order by totals.currency
        )
        from totals
      ),
      '{}'::jsonb
    )
  );
$function$;

revoke all on function public.get_my_daftar_compatible_summary()
  from public, anon;
grant execute on function public.get_my_daftar_compatible_summary()
  to authenticated, service_role;
