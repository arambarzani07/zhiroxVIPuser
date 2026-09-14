create or replace function public.get_customer_directory_page_filtered(
  p_search text default '',
  p_filter text default 'all',
  p_limit integer default 60,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
  with settings as (
    select
      greatest(1, least(coalesce(p_limit, 60), 100)) as page_size,
      nullif(trim(coalesce(p_search, '')), '') as search_text,
      case
        when lower(trim(coalesce(p_filter, ''))) in (
          'with_debt', 'debt_free', 'active', 'inactive'
        ) then lower(trim(coalesce(p_filter, '')))
        else 'all'
      end as filter_key,
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
      and (
        s.filter_key = 'all'
        or (s.filter_key = 'active' and p.active is true)
        or (s.filter_key = 'inactive' and p.active is false)
        or (
          s.filter_key = 'with_debt'
          and exists (
            select 1
            from public.debts d
            where d.customer_id = p.id
              and d.is_deleted = false
              and d.remaining > 0
          )
        )
        or (
          s.filter_key = 'debt_free'
          and not exists (
            select 1
            from public.debts d
            where d.customer_id = p.id
              and d.is_deleted = false
              and d.remaining > 0
          )
        )
      )
  ),
  page_profiles as (
    select p.*
    from matching p
    cross join settings s
    where p_cursor_created_at is null
       or p_cursor_id is null
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

revoke all on function public.get_customer_directory_page_filtered(text, text, integer, timestamptz, uuid)
  from public, anon;
grant execute on function public.get_customer_directory_page_filtered(text, text, integer, timestamptz, uuid)
  to authenticated;
