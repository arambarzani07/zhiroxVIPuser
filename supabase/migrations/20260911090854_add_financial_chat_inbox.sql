create table if not exists public.financial_chat_reads (
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (viewer_id, customer_id)
);

alter table public.financial_chat_reads enable row level security;

drop policy if exists financial_chat_reads_select_own on public.financial_chat_reads;
create policy financial_chat_reads_select_own
on public.financial_chat_reads
for select
using (viewer_id = (select auth.uid()));

drop policy if exists financial_chat_reads_insert_own on public.financial_chat_reads;
create policy financial_chat_reads_insert_own
on public.financial_chat_reads
for insert
with check (
  viewer_id = (select auth.uid())
  and (
    customer_id = (select auth.uid())
    or (
      private.current_role() = any(array['admin'::text, 'employee'::text])
      and private.profile_tenant_id(customer_id) = private.current_admin_id()
    )
  )
);

drop policy if exists financial_chat_reads_update_own on public.financial_chat_reads;
create policy financial_chat_reads_update_own
on public.financial_chat_reads
for update
using (
  viewer_id = (select auth.uid())
  and (
    customer_id = (select auth.uid())
    or (
      private.current_role() = any(array['admin'::text, 'employee'::text])
      and private.profile_tenant_id(customer_id) = private.current_admin_id()
    )
  )
)
with check (
  viewer_id = (select auth.uid())
  and (
    customer_id = (select auth.uid())
    or (
      private.current_role() = any(array['admin'::text, 'employee'::text])
      and private.profile_tenant_id(customer_id) = private.current_admin_id()
    )
  )
);

create or replace function public.get_customer_inbox_rows(p_customer_ids uuid[])
returns jsonb
language sql
stable
set search_path to ''
as $function$
  with requested as (
    select p.id
    from public.profiles p
    where p.id = any(coalesce(p_customer_ids, array[]::uuid[]))
      and p.role = 'customer'
  ),
  debt_summary as (
    select
      r.id as customer_id,
      coalesce(sum(d.remaining), 0)::numeric as remaining,
      count(d.id) filter (where d.remaining > 0)::bigint as open_debt_count
    from requested r
    left join public.debts d on d.customer_id = r.id
    group by r.id
  ),
  activities as (
    select
      d.customer_id,
      coalesce(d.custom_date, d.created_at) as event_at,
      3::smallint as kind_rank,
      d.id as record_id,
      'debt'::text as kind,
      d.amount::numeric as amount,
      d.description::text as preview,
      null::text as event_type
    from public.debts d
    join requested r on r.id = d.customer_id

    union all

    select
      d.customer_id,
      p.created_at as event_at,
      2::smallint as kind_rank,
      p.id as record_id,
      'payment'::text as kind,
      p.amount::numeric as amount,
      nullif(p.note, '')::text as preview,
      null::text as event_type
    from public.payments p
    join public.debts d on d.id = p.debt_id
    join requested r on r.id = d.customer_id

    union all

    select
      e.customer_id,
      e.created_at as event_at,
      4::smallint as kind_rank,
      e.id as record_id,
      'system'::text as kind,
      e.amount::numeric as amount,
      nullif(e.description, '')::text as preview,
      e.event_type::text as event_type
    from public.financial_events e
    join requested r on r.id = e.customer_id
  ),
  latest as (
    select distinct on (a.customer_id)
      a.customer_id,
      a.event_at,
      a.kind,
      a.amount,
      a.preview,
      a.event_type
    from activities a
    order by a.customer_id, a.event_at desc, a.kind_rank desc, a.record_id desc
  ),
  reads as (
    select r.customer_id, r.last_read_at
    from public.financial_chat_reads r
    where r.viewer_id = (select auth.uid())
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'customer_id', s.customer_id,
        'remaining', s.remaining,
        'open_debt_count', s.open_debt_count,
        'last_activity_at', l.event_at,
        'last_kind', l.kind,
        'last_amount', l.amount,
        'last_preview', coalesce(l.preview, ''),
        'last_event_type', coalesce(l.event_type, ''),
        'unread', case
          when rd.last_read_at is null then false
          when l.event_at is null then false
          else l.event_at > rd.last_read_at
        end
      )
      order by l.event_at desc nulls last, s.customer_id
    ),
    '[]'::jsonb
  )
  from debt_summary s
  left join latest l on l.customer_id = s.customer_id
  left join reads rd on rd.customer_id = s.customer_id;
$function$;

create or replace function public.mark_financial_chat_read(p_customer_id uuid)
returns void
language sql
set search_path to ''
as $function$
  insert into public.financial_chat_reads(viewer_id, customer_id, last_read_at)
  values ((select auth.uid()), p_customer_id, now())
  on conflict (viewer_id, customer_id)
  do update set last_read_at = excluded.last_read_at;
$function$;
