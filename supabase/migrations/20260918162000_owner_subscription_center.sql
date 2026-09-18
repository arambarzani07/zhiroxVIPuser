-- Owner subscription center.
-- Privacy boundary: platform billing/account metadata only.
-- No customer, debt, payment-ledger, receipt, note, or market business content.

create or replace function public.get_system_owner_subscription_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_total integer := 0;
  v_active integer := 0;
  v_expiring_7 integer := 0;
  v_expired integer := 0;
  v_pending integer := 0;
  v_failed integer := 0;
  v_revenue numeric := 0;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where a.subscription_end is null or a.subscription_end >= now()
    )::integer,
    count(*) filter (
      where a.subscription_end is not null
        and a.subscription_end >= now()
        and a.subscription_end < now() + interval '7 days'
    )::integer,
    count(*) filter (
      where a.subscription_end is not null
        and a.subscription_end < now()
    )::integer
  into v_total, v_active, v_expiring_7, v_expired
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

  select
    count(*) filter (
      where lower(coalesce(s.status, '')) in ('pending','created','unpaid')
    )::integer,
    count(*) filter (
      where lower(coalesce(s.status, '')) in ('failed','declined','cancelled','canceled')
    )::integer,
    coalesce(sum(s.amount_iqd) filter (
      where lower(coalesce(s.status, '')) in ('paid','completed','success')
    ), 0)::numeric
  into v_pending, v_failed, v_revenue
  from public.subscription_payments s
  where s.created_at >= now() - interval '30 days';

  return jsonb_build_object(
    'total_tenants', v_total,
    'active_subscriptions', v_active,
    'expiring_7_days', v_expiring_7,
    'expired_subscriptions', v_expired,
    'pending_payments_30d', coalesce(v_pending, 0),
    'failed_payments_30d', coalesce(v_failed, 0),
    'platform_revenue_30d_iqd', coalesce(v_revenue, 0)
  );
end;
$$;

create or replace function public.get_system_owner_subscriptions_page(
  p_page integer default 1,
  p_per_page integer default 20
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
  v_per_page integer := least(greatest(coalesce(p_per_page, 20), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  select count(*)::integer
    into v_total
  from public.profiles a
  where a.role = 'admin'
    and a.is_system_owner = false;

  select coalesce(jsonb_agg(item order by sort_created desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      a.created_at as sort_created,
      a.id as sort_id,
      jsonb_build_object(
        'id', a.id,
        'market_name', coalesce(a.market_name, ''),
        'admin_name', coalesce(a.name, ''),
        'phone', coalesce(a.phone, ''),
        'active', a.active,
        'approved', a.approved,
        'subscription_plan', coalesce(a.subscription_plan, 'custom'),
        'subscription_end', a.subscription_end,
        'lifecycle_status', coalesce(c.lifecycle_status, case when a.active then 'active' else 'suspended' end),
        'latest_payment_status', coalesce(lp.status, ''),
        'latest_payment_amount_iqd', coalesce(lp.amount_iqd, 0),
        'latest_payment_at', coalesce(lp.paid_at, lp.created_at)
      ) as item
    from public.profiles a
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join lateral (
      select s.status, s.amount_iqd, s.paid_at, s.created_at
      from public.subscription_payments s
      where s.admin_id = a.id
      order by s.created_at desc, s.id desc
      limit 1
    ) lp on true
    where a.role = 'admin'
      and a.is_system_owner = false
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

create or replace function public.set_system_owner_subscription(
  p_admin_id uuid,
  p_plan text,
  p_extend_days integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_end timestamptz;
  v_market_name text := '';
begin
  if v_uid is null or not exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'system_owner_required' using errcode = '42501';
  end if;

  if p_plan not in ('monthly','quarterly','semiannual','annual','custom')
     or p_extend_days < 0
     or p_extend_days > 3650 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select coalesce(a.market_name, '')
    into v_market_name
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  update public.profiles a
     set subscription_plan = p_plan,
         subscription_end = case
           when p_extend_days = 0 then a.subscription_end
           else greatest(coalesce(a.subscription_end, now()), now())
                + make_interval(days => p_extend_days)
         end,
         updated_at = now()
   where a.id = p_admin_id
  returning a.subscription_end into v_end;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'subscription_changed',
    jsonb_build_object(
      'subscription_plan', p_plan,
      'extend_days', p_extend_days,
      'subscription_end', v_end,
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'subscription_plan', p_plan,
    'subscription_end', v_end,
    'extend_days', p_extend_days
  );
end;
$$;

revoke all on function public.get_system_owner_subscription_overview()
  from public, anon;
revoke all on function public.get_system_owner_subscriptions_page(integer, integer)
  from public, anon;
revoke all on function public.set_system_owner_subscription(uuid, text, integer)
  from public, anon;

grant execute on function public.get_system_owner_subscription_overview()
  to authenticated;
grant execute on function public.get_system_owner_subscriptions_page(integer, integer)
  to authenticated;
grant execute on function public.set_system_owner_subscription(uuid, text, integer)
  to authenticated;
