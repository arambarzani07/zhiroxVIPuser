-- System Owner health and audit center.
-- Strict privacy boundary: only platform/account metadata is returned.
-- No customer, debt, payment-ledger, receipt, note, or market business content
-- is queried or exposed by these functions.

create or replace function public.get_system_owner_health_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_active_tenants integer := 0;
  v_backup_fresh integer := 0;
  v_backup_stale integer := 0;
  v_billing_pending integer := 0;
  v_billing_failed integer := 0;
  v_revenue_30d numeric := 0;
  v_latest_backup timestamptz;
  v_latest_update timestamptz;
  v_latest_owner_action timestamptz;
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  select count(*)::integer
    into v_active_tenants
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  where a.role = 'admin'
    and a.is_system_owner = false
    and a.active = true
    and coalesce(c.lifecycle_status, 'active') not in ('suspended', 'archived');

  select count(distinct b.admin_id)::integer, max(b.created_at)
    into v_backup_fresh, v_latest_backup
  from public.tenant_backups b
  join public.profiles a
    on a.id = b.admin_id
   and a.role = 'admin'
   and a.is_system_owner = false
   and a.active = true
  where b.created_at >= now() - interval '48 hours';

  v_backup_stale := greatest(v_active_tenants - coalesce(v_backup_fresh, 0), 0);

  select
    count(*) filter (
      where lower(coalesce(s.status, '')) in ('pending', 'created', 'unpaid')
    )::integer,
    count(*) filter (
      where lower(coalesce(s.status, '')) in ('failed', 'declined', 'cancelled', 'canceled')
    )::integer,
    coalesce(sum(s.amount_iqd) filter (
      where lower(coalesce(s.status, '')) in ('paid', 'completed', 'success')
    ), 0)::numeric
  into v_billing_pending, v_billing_failed, v_revenue_30d
  from public.subscription_payments s
  where s.created_at >= now() - interval '30 days';

  select max(u.updated_at)
    into v_latest_update
  from public.app_update_settings u;

  select max(a.created_at)
    into v_latest_owner_action
  from public.owner_platform_audit a;

  return jsonb_build_object(
    'database_ok', true,
    'checked_at', now(),
    'active_tenants', v_active_tenants,
    'backup_fresh_tenants', coalesce(v_backup_fresh, 0),
    'backup_stale_tenants', v_backup_stale,
    'latest_backup_at', v_latest_backup,
    'billing_pending_30d', coalesce(v_billing_pending, 0),
    'billing_failed_30d', coalesce(v_billing_failed, 0),
    'platform_revenue_30d_iqd', coalesce(v_revenue_30d, 0),
    'latest_update_config_at', v_latest_update,
    'latest_owner_action_at', v_latest_owner_action
  );
end;
$$;

create or replace function public.get_system_owner_platform_audit_page(
  p_page integer default 1,
  p_per_page integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 50), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  select count(*)::integer
    into v_total
  from public.owner_platform_audit;

  select coalesce(jsonb_agg(row_item order by created_at desc, id desc), '[]'::jsonb)
    into v_items
  from (
    select
      a.id,
      a.created_at,
      jsonb_build_object(
        'id', a.id,
        'action', a.action,
        'market_name', coalesce(p.market_name, ''),
        'created_at', a.created_at,
        'metadata',
          case a.action
            when 'tenant_lifecycle_changed' then jsonb_build_object(
              'status', coalesce(a.metadata ->> 'status', ''),
              'reason', left(coalesce(a.metadata ->> 'reason', ''), 500)
            )
            when 'tenant_limits_changed' then jsonb_build_object(
              'device_limit', coalesce(a.metadata ->> 'device_limit', ''),
              'staff_limit', coalesce(a.metadata ->> 'staff_limit', ''),
              'support_tier', coalesce(a.metadata ->> 'support_tier', '')
            )
            else '{}'::jsonb
          end
      ) as row_item
    from public.owner_platform_audit a
    left join public.profiles p on p.id = a.target_admin_id
    order by a.created_at desc, a.id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) rows;

  return jsonb_build_object(
    'items', v_items,
    'total_items', v_total,
    'total_pages', greatest(1, ceil(v_total::numeric / v_per_page)::integer),
    'page', v_page
  );
end;
$$;

revoke all on function public.get_system_owner_health_overview()
  from public, anon;
revoke all on function public.get_system_owner_platform_audit_page(integer, integer)
  from public, anon;

grant execute on function public.get_system_owner_health_overview()
  to authenticated;
grant execute on function public.get_system_owner_platform_audit_page(integer, integer)
  to authenticated;
