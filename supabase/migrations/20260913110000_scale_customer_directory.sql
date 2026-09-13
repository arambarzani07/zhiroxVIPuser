create extension if not exists pg_trgm with schema extensions;

create index if not exists profiles_customer_directory_page_idx
  on public.profiles (admin_id, created_at desc, id desc)
  where role = 'customer';

create index if not exists profiles_customer_directory_search_idx
  on public.profiles using gin (
    (lower(
      coalesce(name, '') || ' ' ||
      coalesce(father_name, '') || ' ' ||
      coalesce(grandfather_name, '') || ' ' ||
      coalesce(phone, '')
    )) extensions.gin_trgm_ops
  )
  where role = 'customer';

create index if not exists debts_customer_open_summary_idx
  on public.debts (customer_id)
  include (remaining)
  where is_deleted = false and remaining > 0;

create or replace function public.get_customer_directory_page(
  p_search text default '',
  p_limit integer default 60,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null
)
returns jsonb
language sql
stable
set search_path to ''
as $function$
  with settings as (
    select
      greatest(1, least(coalesce(p_limit, 60), 100)) as page_size,
      nullif(trim(coalesce(p_search, '')), '') as search_text,
      (select private.current_admin_id()) as tenant_id
  ),
  viewer_baseline as (
    select greatest(
      coalesce(
        (
          select p.created_at
          from public.profiles p
          where p.id = (select auth.uid())
        ),
        '2026-09-11 09:08:54+00'::timestamptz
      ),
      '2026-09-11 09:08:54+00'::timestamptz
    ) as baseline_at
  ),
  matching as materialized (
    select p.*
    from public.profiles p
    cross join settings s
    where s.tenant_id is not null
      and (select private."current_role"()) in ('admin', 'employee')
      and p.admin_id = s.tenant_id
      and p.role = 'customer'
      and (
        s.search_text is null
        or lower(
          coalesce(p.name, '') || ' ' ||
          coalesce(p.father_name, '') || ' ' ||
          coalesce(p.grandfather_name, '') || ' ' ||
          coalesce(p.phone, '')
        ) like '%' || lower(s.search_text) || '%'
      )
  ),
  page_profiles as (
    select p.*
    from matching p
    cross join settings s
    where p_cursor_created_at is null
       or (p.created_at, p.id) < (p_cursor_created_at, p_cursor_id)
    order by p.created_at desc, p.id desc
    limit (select page_size + 1 from settings)
  ),
  visible_profiles as (
    select p.*
    from page_profiles p
    order by p.created_at desc, p.id desc
    limit (select page_size from settings)
  ),
  rows_with_stats as (
    select
      p.*,
      coalesce(ds.remaining, 0)::numeric as remaining,
      coalesce(ds.open_debt_count, 0)::bigint as open_debt_count,
      la.event_at as last_activity_at,
      la.kind as last_kind,
      la.amount as last_amount,
      coalesce(la.preview, '') as last_preview,
      coalesce(la.event_type, '') as last_event_type,
      case
        when la.event_at is null then false
        when fr.last_read_at is not null then la.event_at > fr.last_read_at
        else la.event_at > vb.baseline_at
      end as unread
    from visible_profiles p
    left join lateral (
      select
        coalesce(sum(d.remaining), 0)::numeric as remaining,
        count(*)::bigint as open_debt_count
      from public.debts d
      where d.customer_id = p.id
        and d.is_deleted = false
        and d.remaining > 0
    ) ds on true
    left join lateral (
      select event_at, kind, amount, preview, event_type
      from (
        (
          select
            e.created_at as event_at,
            4::smallint as kind_rank,
            e.id as record_id,
            'system'::text as kind,
            e.amount::numeric as amount,
            nullif(e.description, '')::text as preview,
            e.event_type::text as event_type
          from public.financial_events e
          where e.customer_id = p.id
          order by e.created_at desc, e.id desc
          limit 1
        )
        union all
        (
          select
            coalesce(d.custom_date, d.created_at) as event_at,
            3::smallint as kind_rank,
            d.id as record_id,
            'debt'::text as kind,
            d.amount::numeric as amount,
            d.description::text as preview,
            null::text as event_type
          from public.debts d
          where d.customer_id = p.id
            and d.is_deleted = false
          order by coalesce(d.custom_date, d.created_at) desc, d.id desc
          limit 1
        )
        union all
        (
          select
            pay.created_at as event_at,
            2::smallint as kind_rank,
            pay.id as record_id,
            'payment'::text as kind,
            pay.amount::numeric as amount,
            nullif(pay.note, '')::text as preview,
            null::text as event_type
          from public.payments pay
          join public.debts d on d.id = pay.debt_id
          where d.customer_id = p.id
            and d.is_deleted = false
          order by pay.created_at desc, pay.id desc
          limit 1
        )
      ) candidates
      order by event_at desc, kind_rank desc, record_id desc
      limit 1
    ) la on true
    left join public.financial_chat_reads fr
      on fr.viewer_id = (select auth.uid())
     and fr.customer_id = p.id
    cross join viewer_baseline vb
  ),
  page_meta as (
    select
      count(*)::bigint as total_count,
      (select count(*) > (select page_size from settings) from page_profiles) as has_more
    from matching
  )
  select jsonb_build_object(
    'items', coalesce(
      (
        select jsonb_agg(to_jsonb(r) order by r.created_at desc, r.id desc)
        from rows_with_stats r
      ),
      '[]'::jsonb
    ),
    'total_count', m.total_count,
    'has_more', m.has_more,
    'next_cursor', case
      when m.has_more then (
        select jsonb_build_object('created_at', r.created_at, 'id', r.id)
        from rows_with_stats r
        order by r.created_at asc, r.id asc
        limit 1
      )
      else null
    end
  )
  from page_meta m;
$function$;

revoke all on function public.get_customer_directory_page(text, integer, timestamptz, uuid)
  from public, anon;
grant execute on function public.get_customer_directory_page(text, integer, timestamptz, uuid)
  to authenticated;

create or replace function public.get_customer_inbox_rows(p_customer_ids uuid[])
returns jsonb
language sql
stable
set search_path to ''
as $function$
  with viewer_baseline as (
    select greatest(
      coalesce(
        (
          select p.created_at
          from public.profiles p
          where p.id = (select auth.uid())
        ),
        '2026-09-11 09:08:54+00'::timestamptz
      ),
      '2026-09-11 09:08:54+00'::timestamptz
    ) as baseline_at
  ),
  requested as (
    select p.id
    from public.profiles p
    where p.id = any(coalesce(p_customer_ids, array[]::uuid[]))
      and p.role = 'customer'
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'customer_id', r.id,
      'remaining', coalesce(ds.remaining, 0),
      'open_debt_count', coalesce(ds.open_debt_count, 0),
      'last_activity_at', la.event_at,
      'last_kind', la.kind,
      'last_amount', la.amount,
      'last_preview', coalesce(la.preview, ''),
      'last_event_type', coalesce(la.event_type, ''),
      'unread', case
        when la.event_at is null then false
        when fr.last_read_at is not null then la.event_at > fr.last_read_at
        else la.event_at > vb.baseline_at
      end
    ) order by la.event_at desc nulls last, r.id
  ), '[]'::jsonb)
  from requested r
  left join lateral (
    select coalesce(sum(d.remaining), 0)::numeric as remaining,
           count(*)::bigint as open_debt_count
    from public.debts d
    where d.customer_id = r.id
      and d.is_deleted = false
      and d.remaining > 0
  ) ds on true
  left join lateral (
    select event_at, kind, amount, preview, event_type
    from (
      (
        select e.created_at as event_at, 4::smallint as kind_rank,
               e.id as record_id, 'system'::text as kind,
               e.amount::numeric as amount, nullif(e.description, '')::text as preview,
               e.event_type::text as event_type
        from public.financial_events e
        where e.customer_id = r.id
        order by e.created_at desc, e.id desc
        limit 1
      )
      union all
      (
        select coalesce(d.custom_date, d.created_at), 3::smallint, d.id,
               'debt'::text, d.amount::numeric, d.description::text, null::text
        from public.debts d
        where d.customer_id = r.id and d.is_deleted = false
        order by coalesce(d.custom_date, d.created_at) desc, d.id desc
        limit 1
      )
      union all
      (
        select pay.created_at, 2::smallint, pay.id, 'payment'::text,
               pay.amount::numeric, nullif(pay.note, '')::text, null::text
        from public.payments pay
        join public.debts d on d.id = pay.debt_id
        where d.customer_id = r.id and d.is_deleted = false
        order by pay.created_at desc, pay.id desc
        limit 1
      )
    ) candidates
    order by event_at desc, kind_rank desc, record_id desc
    limit 1
  ) la on true
  left join public.financial_chat_reads fr
    on fr.viewer_id = (select auth.uid()) and fr.customer_id = r.id
  cross join viewer_baseline vb;
$function$;

revoke all on function public.get_customer_inbox_rows(uuid[]) from public, anon;
grant execute on function public.get_customer_inbox_rows(uuid[]) to authenticated;

create or replace function public.get_customer_finance_snapshot(p_customer_id uuid)
returns jsonb
language sql
stable
set search_path to ''
as $function$
  with debt_rows as materialized (
    select d.*
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
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
  from summary s
  cross join open_debts o;
$function$;

alter policy legacy_import_jobs_admin_select on public.legacy_import_jobs
  using (admin_id = (select auth.uid()));

alter policy legacy_import_links_admin_select on public.legacy_import_links
  using (admin_id = (select auth.uid()));
