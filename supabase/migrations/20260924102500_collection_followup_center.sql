create table if not exists public.customer_followups (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  next_followup_date date not null,
  note text not null default '',
  status text not null default 'pending'
    check (status in ('pending', 'completed')),
  created_by uuid references public.profiles(id) on delete set null,
  completed_by uuid references public.profiles(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists customer_followups_one_pending_idx
  on public.customer_followups (admin_id, customer_id)
  where status = 'pending';

create index if not exists customer_followups_due_idx
  on public.customer_followups (admin_id, status, next_followup_date, customer_id);

alter table public.customer_followups enable row level security;

drop policy if exists customer_followups_select_tenant on public.customer_followups;
create policy customer_followups_select_tenant
on public.customer_followups
for select
to authenticated
using (
  admin_id = (select private.current_admin_id())
  and (select private."current_role"()) in ('admin', 'employee')
);

drop policy if exists customer_followups_insert_admin on public.customer_followups;
create policy customer_followups_insert_admin
on public.customer_followups
for insert
to authenticated
with check (
  admin_id = (select private.current_admin_id())
  and (select private."current_role"()) = 'admin'
  and exists (
    select 1
    from public.profiles p
    where p.id = customer_id
      and p.role = 'customer'
      and p.admin_id = (select private.current_admin_id())
  )
);

drop policy if exists customer_followups_update_admin on public.customer_followups;
create policy customer_followups_update_admin
on public.customer_followups
for update
to authenticated
using (
  admin_id = (select private.current_admin_id())
  and (select private."current_role"()) = 'admin'
)
with check (
  admin_id = (select private.current_admin_id())
  and (select private."current_role"()) = 'admin'
  and exists (
    select 1
    from public.profiles p
    where p.id = customer_id
      and p.role = 'customer'
      and p.admin_id = (select private.current_admin_id())
  )
);

revoke all on table public.customer_followups from public, anon;
grant select, insert, update on table public.customer_followups to authenticated;

create or replace function public.set_customer_followup(
  p_customer_id uuid,
  p_next_followup_date date,
  p_note text default ''
)
returns uuid
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_admin_id uuid := (select private.current_admin_id());
  v_actor_id uuid := auth.uid();
  v_id uuid;
begin
  if v_admin_id is null or (select private."current_role"()) <> 'admin' then
    raise exception 'forbidden';
  end if;

  if p_next_followup_date is null then
    raise exception 'invalid_followup_date';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_customer_id
      and p.role = 'customer'
      and p.admin_id = v_admin_id
  ) then
    raise exception 'customer_not_found';
  end if;

  insert into public.customer_followups (
    admin_id,
    customer_id,
    next_followup_date,
    note,
    status,
    created_by,
    updated_at
  )
  values (
    v_admin_id,
    p_customer_id,
    p_next_followup_date,
    left(coalesce(p_note, ''), 1000),
    'pending',
    v_actor_id,
    now()
  )
  on conflict (admin_id, customer_id) where status = 'pending'
  do update set
    next_followup_date = excluded.next_followup_date,
    note = excluded.note,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.complete_customer_followup(
  p_customer_id uuid
)
returns boolean
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_admin_id uuid := (select private.current_admin_id());
  v_actor_id uuid := auth.uid();
  v_count integer;
begin
  if v_admin_id is null or (select private."current_role"()) <> 'admin' then
    raise exception 'forbidden';
  end if;

  update public.customer_followups f
  set
    status = 'completed',
    completed_by = v_actor_id,
    completed_at = now(),
    updated_at = now()
  where f.admin_id = v_admin_id
    and f.customer_id = p_customer_id
    and f.status = 'pending';

  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

create or replace function public.get_collection_center(
  p_filter text default 'all',
  p_limit integer default 100
)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
with ctx as (
  select
    (select private.current_admin_id()) as admin_id,
    (select private."current_role"()) as role_name,
    greatest(1, least(coalesce(p_limit, 100), 200)) as row_limit,
    case
      when p_filter in (
        'all', 'overdue', '1_7', '8_30', '31_60', '60_plus', 'followup_due'
      ) then p_filter
      else 'all'
    end as selected_filter
),
debt_rollup as (
  select
    p.id as customer_id,
    p.name,
    p.father_name,
    p.grandfather_name,
    p.phone,
    p.is_vip,
    p.is_pinned,
    count(d.id) filter (where d.remaining > 0)::integer as open_debt_count,
    count(d.id) filter (
      where d.remaining > 0
        and d.due_date is not null
        and d.due_date < current_date
    )::integer as overdue_debt_count,
    coalesce(sum(
      case
        when d.remaining > 0 and upper(coalesce(d.currency, 'IQD')) = 'USD'
          then d.remaining
        else 0
      end
    ), 0)::numeric as balance_usd,
    coalesce(sum(
      case
        when d.remaining > 0 and upper(coalesce(d.currency, 'IQD')) <> 'USD'
          then d.remaining
        else 0
      end
    ), 0)::numeric as balance_iqd,
    coalesce(sum(
      case
        when d.remaining > 0
          and d.due_date is not null
          and d.due_date < current_date
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
          then d.remaining
        else 0
      end
    ), 0)::numeric as overdue_usd,
    coalesce(sum(
      case
        when d.remaining > 0
          and d.due_date is not null
          and d.due_date < current_date
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
          then d.remaining
        else 0
      end
    ), 0)::numeric as overdue_iqd,
    min(d.due_date) filter (
      where d.remaining > 0
        and d.due_date is not null
        and d.due_date < current_date
    ) as oldest_due_date,
    count(d.id) filter (
      where d.remaining > 0 and d.due_date = current_date
    )::integer as due_today_count
  from public.profiles p
  cross join ctx
  left join public.debts d
    on d.customer_id = p.id
   and coalesce(d.is_deleted, false) = false
  where ctx.admin_id is not null
    and ctx.role_name in ('admin', 'employee')
    and p.admin_id = ctx.admin_id
    and p.role = 'customer'
    and p.active is true
  group by
    p.id, p.name, p.father_name, p.grandfather_name, p.phone,
    p.is_vip, p.is_pinned
),
with_followup as (
  select
    r.*,
    f.id as followup_id,
    f.next_followup_date,
    f.note as followup_note,
    case
      when r.oldest_due_date is null then 0
      else greatest(current_date - r.oldest_due_date, 0)
    end::integer as overdue_days
  from debt_rollup r
  left join lateral (
    select cf.id, cf.next_followup_date, cf.note
    from public.customer_followups cf
    cross join ctx
    where cf.admin_id = ctx.admin_id
      and cf.customer_id = r.customer_id
      and cf.status = 'pending'
    order by cf.updated_at desc, cf.id desc
    limit 1
  ) f on true
  where r.open_debt_count > 0
),
scored as (
  select
    w.*,
    case
      when w.overdue_days = 0 then 'current'
      when w.overdue_days <= 7 then '1_7'
      when w.overdue_days <= 30 then '8_30'
      when w.overdue_days <= 60 then '31_60'
      else '60_plus'
    end as aging_bucket,
    least(
      100,
      (case when w.is_vip then 15 else 0 end) +
      (case when w.is_pinned then 10 else 0 end) +
      least(w.overdue_days, 50) +
      least(w.overdue_debt_count * 5, 20) +
      (case
        when w.next_followup_date is not null
          and w.next_followup_date <= current_date then 10
        else 0
      end)
    )::integer as priority_score
  from with_followup w
),
filtered as (
  select s.*
  from scored s
  cross join ctx
  where
    ctx.selected_filter = 'all'
    or (ctx.selected_filter = 'overdue' and s.overdue_days > 0)
    or (ctx.selected_filter = '1_7' and s.aging_bucket = '1_7')
    or (ctx.selected_filter = '8_30' and s.aging_bucket = '8_30')
    or (ctx.selected_filter = '31_60' and s.aging_bucket = '31_60')
    or (ctx.selected_filter = '60_plus' and s.aging_bucket = '60_plus')
    or (
      ctx.selected_filter = 'followup_due'
      and s.next_followup_date is not null
      and s.next_followup_date <= current_date
    )
),
limited as (
  select f.*
  from filtered f
  cross join ctx
  order by
    (f.next_followup_date is not null and f.next_followup_date <= current_date) desc,
    f.priority_score desc,
    f.overdue_days desc,
    f.is_vip desc,
    f.is_pinned desc,
    f.name asc
  limit (select row_limit from ctx)
),
summary as (
  select
    count(*) filter (where overdue_days > 0)::integer as overdue_customers,
    count(*) filter (where due_today_count > 0)::integer as due_today_customers,
    count(*) filter (
      where next_followup_date is not null
        and next_followup_date <= current_date
    )::integer as followups_due,
    coalesce(sum(overdue_iqd), 0)::numeric as overdue_iqd,
    coalesce(sum(overdue_usd), 0)::numeric as overdue_usd
  from scored
)
select jsonb_build_object(
  'summary', jsonb_build_object(
    'overdue_customers', summary.overdue_customers,
    'due_today_customers', summary.due_today_customers,
    'followups_due', summary.followups_due,
    'overdue_iqd', summary.overdue_iqd,
    'overdue_usd', summary.overdue_usd
  ),
  'items', coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'customer_id', l.customer_id,
          'name', l.name,
          'father_name', l.father_name,
          'grandfather_name', l.grandfather_name,
          'phone', l.phone,
          'is_vip', l.is_vip,
          'is_pinned', l.is_pinned,
          'open_debt_count', l.open_debt_count,
          'overdue_debt_count', l.overdue_debt_count,
          'balance_iqd', l.balance_iqd,
          'balance_usd', l.balance_usd,
          'overdue_iqd', l.overdue_iqd,
          'overdue_usd', l.overdue_usd,
          'oldest_due_date', l.oldest_due_date,
          'overdue_days', l.overdue_days,
          'due_today_count', l.due_today_count,
          'aging_bucket', l.aging_bucket,
          'priority_score', l.priority_score,
          'followup_id', l.followup_id,
          'next_followup_date', l.next_followup_date,
          'followup_note', l.followup_note
        )
        order by
          (l.next_followup_date is not null and l.next_followup_date <= current_date) desc,
          l.priority_score desc,
          l.overdue_days desc,
          l.name asc
      )
      from limited l
    ),
    '[]'::jsonb
  )
)
from summary;
$function$;

revoke all on function public.set_customer_followup(uuid, date, text)
  from public, anon;
grant execute on function public.set_customer_followup(uuid, date, text)
  to authenticated;

revoke all on function public.complete_customer_followup(uuid)
  from public, anon;
grant execute on function public.complete_customer_followup(uuid)
  to authenticated;

revoke all on function public.get_collection_center(text, integer)
  from public, anon;
grant execute on function public.get_collection_center(text, integer)
  to authenticated;
