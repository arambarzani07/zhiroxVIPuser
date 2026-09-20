-- Restore authenticated dashboard/customer reads after exact Daftar
-- projection. Keep operational sync tables private and expose only safe,
-- tenant-scoped projection data through SECURITY DEFINER helpers.

create or replace function private.get_daftar_projection_summary()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with tenant as (
    select private.current_admin_id() as admin_id
  )
  select coalesce((
    select jsonb_build_object(
      'source_id', s.id,
      'admin_id', s.admin_id,
      'official_total_customers', coalesce(s.official_total_customers, 0),
      'official_total_loan_iqd', coalesce(s.official_total_loan_iqd, 0),
      'official_total_payment_iqd', coalesce(s.official_total_payment_iqd, 0),
      'official_balance_iqd', coalesce(s.official_balance_iqd, 0),
      'official_total_loan_usd', coalesce(s.official_total_loan_usd, 0),
      'official_total_payment_usd', coalesce(s.official_total_payment_usd, 0),
      'official_balance_usd', coalesce(s.official_balance_usd, 0),
      'official_totals_at', s.official_totals_at
    )
    from public.daftar_sync_sources s
    cross join tenant t
    where t.admin_id is not null
      and s.admin_id = t.admin_id
      and s.legacy_user_id = 28
      and s.source_fingerprint = 'daftar-live-account-28-v1'
      and s.sync_mode = 'zhirox_primary'
      and coalesce(s.inbound_sync_enabled, false)
      and s.official_totals_at is not null
    order by s.created_at
    limit 1
  ), '{}'::jsonb);
$$;

revoke all on function private.get_daftar_projection_summary()
  from public, anon;
grant execute on function private.get_daftar_projection_summary()
  to authenticated, service_role;

create or replace function private.get_daftar_official_customer_totals(
  p_customer_id uuid default null
)
returns table (
  customer_id uuid,
  source_contact_id text,
  loan_iqd numeric,
  payment_iqd numeric,
  balance_iqd numeric,
  loan_usd numeric,
  payment_usd numeric,
  balance_usd numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  with tenant as (
    select private.current_admin_id() as admin_id
  ),
  source_row as (
    select s.id, s.admin_id
    from public.daftar_sync_sources s
    cross join tenant t
    where t.admin_id is not null
      and s.admin_id = t.admin_id
      and s.legacy_user_id = 28
      and s.source_fingerprint = 'daftar-live-account-28-v1'
      and s.sync_mode = 'zhirox_primary'
      and coalesce(s.inbound_sync_enabled, false)
      and s.official_totals_at is not null
    order by s.created_at
    limit 1
  )
  select
    l.target_id as customer_id,
    l.source_id as source_contact_id,
    oct.loan_iqd,
    oct.payment_iqd,
    oct.balance_iqd,
    oct.loan_usd,
    oct.payment_usd,
    oct.balance_usd
  from source_row sr
  join public.legacy_import_links l
    on l.admin_id = sr.admin_id
   and l.source_fingerprint = 'daftar-live-account-28-v1'
   and l.entity_kind = 'customer'
  join public.daftar_official_contact_totals oct
    on oct.sync_source_id = sr.id
   and oct.source_contact_id = l.source_id
  join public.profiles p
    on p.id = l.target_id
   and p.admin_id = sr.admin_id
   and p.role = 'customer'
  where p_customer_id is null or l.target_id = p_customer_id;
$$;

revoke all on function private.get_daftar_official_customer_totals(uuid)
  from public, anon;
grant execute on function private.get_daftar_official_customer_totals(uuid)
  to authenticated, service_role;

create or replace function public.get_admin_dashboard_snapshot()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_result jsonb;
  v_admin_id uuid := auth.uid();
  v_projection jsonb := private.get_daftar_projection_summary();
  v_use_daftar_projection boolean := v_projection <> '{}'::jsonb;
begin
  if private."current_role"() is distinct from 'admin' then
    raise insufficient_privilege using message = 'admin role required';
  end if;

  select jsonb_build_object(
    'total_customers', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_customers')::integer, 0)
      else (
        select count(*) from public.profiles p
        where p.role = 'customer' and p.approved = true
      )
    end,
    'pending_requests', (
      select count(*) from public.profiles p
      where p.role = 'customer' and p.approved = false
    ),
    'total_debt', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_iqd')::numeric, 0)
      else coalesce((
        select sum(d.amount) from public.debts d
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ), 0)
    end,
    'total_remaining', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_balance_iqd')::numeric, 0)
      else coalesce((
        select sum(d.remaining) from public.debts d
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ), 0)
    end,
    'total_payments', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_payment_iqd')::numeric, 0)
      else coalesce((
        select sum(pay.amount)
        from public.payments pay
        join public.debts d on d.id = pay.debt_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ), 0)
    end,
    'total_debt_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_usd')::numeric, 0)
      else coalesce((
        select sum(d.amount) from public.debts d
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'total_remaining_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_balance_usd')::numeric, 0)
      else coalesce((
        select sum(d.remaining) from public.debts d
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
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'pending_debts', (
      select count(*) from public.debts d
      where d.is_deleted = false
        and d.status <> 'paid'
        and (
          not v_use_daftar_projection
          or exists (
            select 1
            from private.get_daftar_official_customer_totals(d.customer_id) x
          )
        )
    ),
    'recent_activity', coalesce((
      select jsonb_agg(
        recent_row.payload
        order by recent_row.created_at desc, recent_row.id desc
      )
      from (
        select
          d.created_at,
          d.id::text as id,
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
        join public.profiles customer on customer.id = d.customer_id
        left join public.profiles creator on creator.id = d.created_by
        where d.is_deleted = false
          and d.created_at >= now() - interval '24 hours'
          and d.created_at <= now()
          and (
            not v_use_daftar_projection
            or exists (
              select 1
              from private.get_daftar_official_customer_totals(d.customer_id) x
            )
          )

        union all

        select
          pay.created_at,
          pay.id::text as id,
          jsonb_build_object(
            'id', pay.id,
            'event_type', 'payment',
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
        join public.profiles customer on customer.id = d.customer_id
        left join public.profiles creator on creator.id = pay.created_by
        where d.is_deleted = false
          and pay.created_at >= now() - interval '24 hours'
          and pay.created_at <= now()
          and (
            not v_use_daftar_projection
            or exists (
              select 1
              from private.get_daftar_official_customer_totals(d.customer_id) x
            )
          )
      ) recent_row
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_admin_dashboard_snapshot() from public, anon;
grant execute on function public.get_admin_dashboard_snapshot()
  to authenticated, service_role;

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
      coalesce(o.balance_iqd, ds.remaining, 0)::numeric as remaining,
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

revoke all on function public.get_customer_directory_page(text, integer, timestamptz, uuid)
  from public, anon;
grant execute on function public.get_customer_directory_page(text, integer, timestamptz, uuid)
  to authenticated, service_role;

create or replace function public.get_customer_finance_snapshot(p_customer_id uuid)
returns jsonb
language sql
stable
set search_path to ''
as $$
  with official as (
    select *
    from private.get_daftar_official_customer_totals(p_customer_id)
    limit 1
  ),
  debt_rows as materialized (
    select d.*
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
  ),
  summary as (
    select
      coalesce(sum(d.amount), 0)::numeric as local_total_debt_iqd,
      coalesce(sum(d.remaining), 0)::numeric as local_total_remaining_iqd,
      count(*) filter (where d.remaining > 0)::bigint as open_debt_count
    from debt_rows d
  ),
  local_paid as (
    select private.customer_lifetime_paid_total(p_customer_id)::numeric as total_paid_iqd
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
    'total_debt_iqd', coalesce((select loan_iqd from official), s.local_total_debt_iqd),
    'total_remaining_iqd', coalesce((select balance_iqd from official), s.local_total_remaining_iqd),
    'total_paid_iqd', coalesce((select payment_iqd from official), lp.total_paid_iqd),
    'open_debt_count', s.open_debt_count,
    'open_debts', o.items,
    'complete', true
  )
  from summary s
  cross join local_paid lp
  cross join open_debts o;
$$;

revoke all on function public.get_customer_finance_snapshot(uuid) from public, anon;
grant execute on function public.get_customer_finance_snapshot(uuid)
  to authenticated, service_role;
