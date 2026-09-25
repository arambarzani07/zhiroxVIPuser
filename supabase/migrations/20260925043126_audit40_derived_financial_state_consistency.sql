-- Mirrors production migration 20260925043126: audit40_derived_financial_state_consistency.
-- Customer lists, inbox rows, and dashboard pending counts use the same
-- general-credit-aware virtual balance projection without mutating debt rows.

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
  v_admin_id uuid := auth.uid();
  v_projection jsonb := private.get_daftar_projection_summary();
  v_use_daftar_projection boolean := v_projection <> '{}'::jsonb;
begin
  if private."current_role"() is distinct from 'admin' then
    raise insufficient_privilege using message = 'admin role required';
  end if;

  with official_customer_ids as materialized (
    select x.customer_id
    from private.get_daftar_official_customer_totals(null) x
  ),
  visible_customer_ids as materialized (
    select p.id
    from public.profiles p
    where p.admin_id = v_admin_id
      and p.role = 'customer'
      and (
        not v_use_daftar_projection
        or exists (
          select 1
          from official_customer_ids o
          where o.customer_id = p.id
        )
      )
  ),
  general_paid as materialized (
    select coalesce(sum(g.amount), 0)::numeric as amount
    from public.customer_general_payments g
    join visible_customer_ids visible on visible.id = g.customer_id
  ),
  recent_rows as materialized (
    select
      d.created_at,
      d.id::text as sort_id,
      jsonb_build_object(
        'id', d.id,
        'event_type', 'debt',
        'amount', d.amount,
        'currency', coalesce(d.currency, 'IQD'),
        'created_at', d.created_at,
        'customer_id', d.customer_id,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.debts d
    join visible_customer_ids visible on visible.id = d.customer_id
    join public.profiles customer on customer.id = d.customer_id
    left join public.profiles creator on creator.id = d.created_by
    where d.is_deleted = false
      and d.created_at >= now() - interval '24 hours'
      and d.created_at <= now()

    union all

    select
      pay.created_at,
      pay.id::text as sort_id,
      jsonb_build_object(
        'id', pay.id,
        'event_type', 'payment',
        'payment_scope', 'debt',
        'amount', pay.amount,
        'currency', coalesce(d.currency, 'IQD'),
        'created_at', pay.created_at,
        'customer_id', d.customer_id,
        'debt_id', pay.debt_id,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.payments pay
    join public.debts d on d.id = pay.debt_id
    join visible_customer_ids visible on visible.id = d.customer_id
    join public.profiles customer on customer.id = d.customer_id
    left join public.profiles creator on creator.id = pay.created_by
    where d.is_deleted = false
      and pay.created_at >= now() - interval '24 hours'
      and pay.created_at <= now()

    union all

    select
      g.created_at,
      g.id::text as sort_id,
      jsonb_build_object(
        'id', g.id,
        'event_type', 'payment',
        'payment_scope', 'general',
        'amount', g.amount,
        'currency', 'IQD',
        'created_at', g.created_at,
        'customer_id', g.customer_id,
        'debt_id', null,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.customer_general_payments g
    join visible_customer_ids visible on visible.id = g.customer_id
    join public.profiles customer on customer.id = g.customer_id
    left join public.profiles creator on creator.id = g.created_by
    where g.created_at >= now() - interval '24 hours'
      and g.created_at <= now()
  ),
  limited_recent_rows as materialized (
    select r.created_at, r.sort_id, r.payload
    from recent_rows r
    order by r.created_at desc, r.sort_id desc
    limit 250
  )
  select jsonb_build_object(
    'total_customers', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_customers')::integer, 0)
      else (select count(*) from visible_customer_ids)
    end,
    'pending_requests', (
      select count(*)
      from public.profiles p
      where p.admin_id = v_admin_id
        and p.role = 'customer'
        and p.approved = false
    ),
    'total_debt', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_iqd')::numeric, 0)
      else coalesce((
        select sum(d.amount)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ), 0)
    end,
    'total_remaining', greatest(
      case
        when v_use_daftar_projection
          then coalesce((v_projection->>'official_balance_iqd')::numeric, 0)
        else coalesce((
          select sum(d.remaining)
          from public.debts d
          join visible_customer_ids visible on visible.id = d.customer_id
          where d.is_deleted = false
            and upper(coalesce(d.currency, 'IQD')) <> 'USD'
        ), 0)
      end - (select amount from general_paid),
      0
    ),
    'total_payments', (
      case
        when v_use_daftar_projection
          then coalesce((v_projection->>'official_total_payment_iqd')::numeric, 0)
        else coalesce((
          select sum(pay.amount)
          from public.payments pay
          join public.debts d on d.id = pay.debt_id
          join visible_customer_ids visible on visible.id = d.customer_id
          where d.is_deleted = false
            and upper(coalesce(d.currency, 'IQD')) <> 'USD'
        ), 0)
      end + (select amount from general_paid)
    ),
    'total_debt_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_usd')::numeric, 0)
      else coalesce((
        select sum(d.amount)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'total_remaining_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_balance_usd')::numeric, 0)
      else coalesce((
        select sum(d.remaining)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'total_payments_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_payment_usd')::numeric, 0)
      else coalesce((
        select sum(pay.amount)
        from public.payments pay
        join public.debts d on d.id = pay.debt_id
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'pending_debts', (
      select count(*)
      from visible_customer_ids visible
      cross join lateral private.get_customer_virtual_debt_balances(visible.id) v
      where v.effective_remaining > 0
    ),
    'recent_activity', coalesce((
      select jsonb_agg(r.payload order by r.created_at desc, r.sort_id desc)
      from limited_recent_rows r
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_directory_page(p_search text DEFAULT ''::text, p_limit integer DEFAULT 60, p_cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with settings as (
    select
      greatest(1, least(coalesce(p_limit, 60), 100)) as page_size,
      nullif(trim(coalesce(p_search, '')), '') as search_text,
      (select private.current_admin_id()) as tenant_id
  ),
  projection as (
    select private.get_daftar_projection_summary() as j
  ),
  official_rows as materialized (
    select * from private.get_daftar_official_customer_totals(null)
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
    cross join projection pr
    where s.tenant_id is not null
      and (select private."current_role"()) in ('admin', 'employee')
      and p.admin_id = s.tenant_id
      and p.role = 'customer'
      and (
        pr.j = '{}'::jsonb
        or exists (
          select 1 from official_rows o where o.customer_id = p.id
        )
      )
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
      public.get_customer_effective_balance(p.id)::numeric as remaining,
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
    left join official_rows o on o.customer_id = p.id
    left join lateral (
      select count(*)::bigint as open_debt_count
      from private.get_customer_virtual_debt_balances(p.id) v
      where v.effective_remaining > 0
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
          where e.customer_id = p.id
          order by e.created_at desc, e.id desc
          limit 1
        )
        union all
        (
          select coalesce(d.custom_date, d.created_at), 3::smallint, d.id,
                 'debt'::text, d.amount::numeric, d.description::text, null::text
          from public.debts d
          where d.customer_id = p.id and d.is_deleted = false
          order by coalesce(d.custom_date, d.created_at) desc, d.id desc
          limit 1
        )
        union all
        (
          select pay.created_at, 2::smallint, pay.id, 'payment'::text,
                 pay.amount::numeric, nullif(pay.note, '')::text, null::text
          from public.payments pay
          join public.debts d on d.id = pay.debt_id
          where d.customer_id = p.id and d.is_deleted = false
          order by pay.created_at desc, pay.id desc
          limit 1
        )
        union all
        (
          select g.created_at, 2::smallint, g.id, 'payment'::text,
                 g.amount::numeric, nullif(g.note, '')::text, 'general_payment'::text
          from public.customer_general_payments g
          where g.customer_id = p.id
          order by g.created_at desc, g.id desc
          limit 1
        )
      ) candidates
      order by event_at desc, kind_rank desc, record_id desc
      limit 1
    ) la on true
    left join public.financial_chat_reads fr
      on fr.viewer_id = (select auth.uid()) and fr.customer_id = p.id
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

CREATE OR REPLACE FUNCTION public.get_customer_directory_page_filtered(p_search text DEFAULT ''::text, p_filter text DEFAULT 'all'::text, p_limit integer DEFAULT 60, p_cursor_created_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
          and public.get_customer_effective_balance(p.id) > 0
        )
        or (
          s.filter_key = 'debt_free'
          and public.get_customer_effective_balance(p.id) <= 0
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
      public.get_customer_effective_balance(p.id)::numeric as remaining,
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
      select count(*)::bigint as open_debt_count
      from private.get_customer_virtual_debt_balances(p.id) v
      where v.effective_remaining > 0
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
        union all
        (
          select
            g.created_at as event_at,
            2::smallint as kind_rank,
            g.id as record_id,
            'payment'::text as kind,
            g.amount::numeric as amount,
            nullif(g.note, '')::text as preview,
            'general_payment'::text as event_type
          from public.customer_general_payments g
          where g.customer_id = p.id
          order by g.created_at desc, g.id desc
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

CREATE OR REPLACE FUNCTION public.get_customer_inbox_rows(p_customer_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
      'remaining', public.get_customer_effective_balance(r.id),
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
    select count(*)::bigint as open_debt_count
    from private.get_customer_virtual_debt_balances(r.id) v
    where v.effective_remaining > 0
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
      union all
      (
        select g.created_at, 2::smallint, g.id, 'payment'::text,
               g.amount::numeric, nullif(g.note, '')::text, 'general_payment'::text
        from public.customer_general_payments g
        where g.customer_id = r.id
        order by g.created_at desc, g.id desc
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
