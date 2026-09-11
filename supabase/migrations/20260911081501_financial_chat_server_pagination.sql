create index if not exists idx_debts_customer_timeline
  on public.debts (customer_id, (coalesce(custom_date, created_at)) desc, id desc);

create index if not exists idx_payments_debt_timeline
  on public.payments (debt_id, created_at desc, id desc);

create index if not exists idx_financial_events_customer_timeline_v2
  on public.financial_events (customer_id, created_at desc, id desc);

create or replace function public.get_customer_finance_snapshot(
  p_customer_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with debt_rows as (
    select d.* from public.debts d where d.customer_id = p_customer_id
  ),
  summary as (
    select
      coalesce(sum(d.amount), 0)::numeric as total_debt_iqd,
      coalesce(sum(d.remaining), 0)::numeric as total_remaining_iqd,
      coalesce(sum(d.amount - d.remaining), 0)::numeric as total_paid_iqd,
      count(*) filter (where d.remaining > 0)::bigint as open_debt_count
    from debt_rows d
  ),
  open_debts as (
    select coalesce(
      jsonb_agg(to_jsonb(d) order by coalesce(d.custom_date, d.created_at) desc, d.id desc),
      '[]'::jsonb
    ) as items
    from debt_rows d
    where d.remaining > 0
  )
  select jsonb_build_object(
    'total_debt_iqd', s.total_debt_iqd,
    'total_remaining_iqd', s.total_remaining_iqd,
    'total_paid_iqd', s.total_paid_iqd,
    'open_debt_count', s.open_debt_count,
    'open_debts', o.items,
    'complete', true
  )
  from summary s cross join open_debts o;
$$;

create or replace function public.get_customer_financial_timeline_page(
  p_customer_id uuid,
  p_limit integer default 50,
  p_cursor_at timestamptz default null,
  p_cursor_kind smallint default null,
  p_cursor_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with params as (
    select greatest(1, least(coalesce(p_limit, 50), 100))::integer as lim
  ),
  debt_source as (
    select 'debt'::text as kind, 3::smallint as kind_rank, d.id as record_id,
      coalesce(d.custom_date, d.created_at) as event_at,
      to_jsonb(d) as record, null::jsonb as related_debt
    from public.debts d
    where d.customer_id = p_customer_id
      and (p_cursor_at is null or p_cursor_kind is null or p_cursor_id is null
        or (coalesce(d.custom_date, d.created_at), 3::smallint, d.id)
           < (p_cursor_at, p_cursor_kind, p_cursor_id))
    order by coalesce(d.custom_date, d.created_at) desc, d.id desc
    limit (select lim + 1 from params)
  ),
  payment_source as (
    select 'payment'::text as kind, 2::smallint as kind_rank, p.id as record_id,
      p.created_at as event_at, to_jsonb(p) as record, to_jsonb(d) as related_debt
    from public.payments p
    join public.debts d on d.id = p.debt_id
    where d.customer_id = p_customer_id
      and (p_cursor_at is null or p_cursor_kind is null or p_cursor_id is null
        or (p.created_at, 2::smallint, p.id)
           < (p_cursor_at, p_cursor_kind, p_cursor_id))
    order by p.created_at desc, p.id desc
    limit (select lim + 1 from params)
  ),
  event_source as (
    select 'system'::text as kind, 1::smallint as kind_rank, e.id as record_id,
      e.created_at as event_at, to_jsonb(e) as record, null::jsonb as related_debt
    from public.financial_events e
    where e.customer_id = p_customer_id
      and e.event_type in ('debt_updated','debt_deleted','payment_updated','payment_deleted')
      and (p_cursor_at is null or p_cursor_kind is null or p_cursor_id is null
        or (e.created_at, 1::smallint, e.id)
           < (p_cursor_at, p_cursor_kind, p_cursor_id))
    order by e.created_at desc, e.id desc
    limit (select lim + 1 from params)
  ),
  combined as (
    select * from debt_source union all
    select * from payment_source union all
    select * from event_source
  ),
  page_plus_one as (
    select c.* from combined c
    order by c.event_at desc, c.kind_rank desc, c.record_id desc
    limit (select lim + 1 from params)
  ),
  visible as (
    select p.* from page_plus_one p
    order by p.event_at desc, p.kind_rank desc, p.record_id desc
    limit (select lim from params)
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', v.kind, 'kind_rank', v.kind_rank, 'id', v.record_id,
        'event_at', v.event_at, 'record', v.record, 'related_debt', v.related_debt
      ) order by v.event_at desc, v.kind_rank desc, v.record_id desc)
      from visible v
    ), '[]'::jsonb),
    'has_more', (select count(*) from page_plus_one) > (select lim from params),
    'next_cursor', case
      when (select count(*) from page_plus_one) > (select lim from params)
      then (select jsonb_build_object('at', v.event_at, 'kind_rank', v.kind_rank, 'id', v.record_id)
            from visible v order by v.event_at asc, v.kind_rank asc, v.record_id asc limit 1)
      else null
    end
  );
$$;

revoke all on function public.get_customer_finance_snapshot(uuid) from public;
revoke all on function public.get_customer_financial_timeline_page(uuid, integer, timestamptz, smallint, uuid) from public;
grant execute on function public.get_customer_finance_snapshot(uuid) to authenticated;
grant execute on function public.get_customer_financial_timeline_page(uuid, integer, timestamptz, smallint, uuid) to authenticated;
