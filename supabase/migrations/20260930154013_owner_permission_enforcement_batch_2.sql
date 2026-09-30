-- Owner permission enforcement batch 2: Subscription, Security, Support.
-- Preserves current Owner behavior while routing authorization through the
-- central 200-action permission governance layer.

create or replace function public.get_system_owner_subscription_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total integer := 0;
  v_active integer := 0;
  v_expiring_7 integer := 0;
  v_expired integer := 0;
  v_pending integer := 0;
  v_failed integer := 0;
  v_revenue numeric := 0;
begin
  perform private.assert_system_owner_permission('owner_view_subscription', 'market', null);
  perform private.assert_system_owner_permission('owner_view_billing_history', 'market', null);

  select
    count(*)::integer,
    count(*) filter (where a.subscription_end is null or a.subscription_end >= now())::integer,
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
    count(*) filter (where lower(coalesce(s.status, '')) in ('pending','created','unpaid'))::integer,
    count(*) filter (where lower(coalesce(s.status, '')) in ('failed','declined','cancelled','canceled'))::integer,
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
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 20), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission('owner_view_subscription', 'market', null);
  perform private.assert_system_owner_permission('owner_view_billing_history', 'market', null);

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
  v_uid uuid;
  v_end timestamptz;
  v_market_name text := '';
  v_current_plan text := '';
  v_permission_keys jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

  if p_plan not in ('monthly','quarterly','semiannual','annual','custom')
     or p_extend_days < 0
     or p_extend_days > 3650 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select coalesce(a.market_name, ''), coalesce(a.subscription_plan, 'custom')
    into v_market_name, v_current_plan
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  if p_plan is distinct from v_current_plan then
    perform private.assert_system_owner_permission(
      'owner_change_subscription_plan', 'market', p_admin_id
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_change_subscription_plan');
  end if;

  if p_extend_days > 0 then
    perform private.assert_system_owner_permission(
      'owner_extend_subscription_days', 'market', p_admin_id
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_extend_subscription_days');
  end if;

  if jsonb_array_length(v_permission_keys) = 0 then
    perform private.assert_system_owner_permission(
      'owner_view_subscription', 'market', p_admin_id
    );
    v_permission_keys := jsonb_build_array('owner_view_subscription');
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
      'permission_keys', v_permission_keys,
      'subscription_plan', p_plan,
      'previous_subscription_plan', v_current_plan,
      'extend_days', p_extend_days,
      'subscription_end', v_end,
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'subscription_plan', p_plan,
    'subscription_end', v_end,
    'extend_days', p_extend_days,
    'permission_keys', v_permission_keys
  );
end;
$$;

create or replace function public.get_system_owner_security_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_total integer := 0;
  v_locked integer := 0;
  v_active_sessions integer := 0;
  v_review integer := 0;
begin
  perform private.assert_system_owner_permission(
    'owner_view_security_dashboard', 'market', null
  );

  with tenant_security as (
    select
      a.id,
      (a.active = false or coalesce(au.banned_until > now(), false)) as locked,
      coalesce(c.device_limit, 5) as device_limit,
      count(distinct s.id) filter (
        where exists (
          select 1
          from auth.refresh_tokens rt
          where rt.session_id = s.id
            and rt.revoked = false
        )
      )::integer as active_sessions,
      count(distinct s.ip) filter (
        where s.ip is not null
          and s.updated_at >= now() - interval '24 hours'
      )::integer as recent_ip_count_24h,
      count(distinct s.user_agent) filter (
        where coalesce(s.user_agent, '') <> ''
          and s.updated_at >= now() - interval '30 days'
      )::integer as recent_device_count_30d
    from public.profiles a
    left join auth.users au on au.id = a.id
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join auth.sessions s on s.user_id = a.id
    where a.role = 'admin'
      and a.is_system_owner = false
    group by a.id, a.active, au.banned_until, c.device_limit
  )
  select
    count(*)::integer,
    count(*) filter (where locked)::integer,
    coalesce(sum(active_sessions), 0)::integer,
    count(*) filter (
      where not locked
        and (
          recent_ip_count_24h >= 3
          or recent_device_count_30d > device_limit
        )
    )::integer
  into v_total, v_locked, v_active_sessions, v_review
  from tenant_security;

  return jsonb_build_object(
    'total_admin_accounts', coalesce(v_total, 0),
    'locked_admin_accounts', coalesce(v_locked, 0),
    'active_sessions', coalesce(v_active_sessions, 0),
    'accounts_needing_review', coalesce(v_review, 0),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_security_page(
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
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 20), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_security_dashboard', 'market', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_active_sessions', 'market', null
  );
  perform private.assert_system_owner_permission(
    'owner_view_devices', 'market', null
  );

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
        'locked', (a.active = false or coalesce(au.banned_until > now(), false)),
        'last_sign_in_at', au.last_sign_in_at,
        'banned_until', au.banned_until,
        'active_sessions', coalesce(sec.active_sessions, 0),
        'aal2_sessions', coalesce(sec.aal2_sessions, 0),
        'recent_ip_count_24h', coalesce(sec.recent_ip_count_24h, 0),
        'recent_device_count_30d', coalesce(sec.recent_device_count_30d, 0),
        'last_session_at', sec.last_session_at,
        'device_limit', coalesce(c.device_limit, 5),
        'security_state',
          case
            when a.active = false or coalesce(au.banned_until > now(), false) then 'locked'
            when coalesce(sec.recent_ip_count_24h, 0) >= 3
              or coalesce(sec.recent_device_count_30d, 0) > coalesce(c.device_limit, 5)
              then 'review'
            else 'normal'
          end
      ) as item
    from public.profiles a
    left join auth.users au on au.id = a.id
    left join public.owner_tenant_controls c on c.admin_id = a.id
    left join lateral (
      select
        count(distinct s.id) filter (
          where exists (
            select 1
            from auth.refresh_tokens rt
            where rt.session_id = s.id
              and rt.revoked = false
          )
        )::integer as active_sessions,
        count(distinct s.id) filter (
          where s.aal::text = 'aal2'
            and exists (
              select 1
              from auth.refresh_tokens rt
              where rt.session_id = s.id
                and rt.revoked = false
            )
        )::integer as aal2_sessions,
        count(distinct s.ip) filter (
          where s.ip is not null
            and s.updated_at >= now() - interval '24 hours'
        )::integer as recent_ip_count_24h,
        count(distinct s.user_agent) filter (
          where coalesce(s.user_agent, '') <> ''
            and s.updated_at >= now() - interval '30 days'
        )::integer as recent_device_count_30d,
        max(s.updated_at) as last_session_at
      from auth.sessions s
      where s.user_id = a.id
    ) sec on true
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

create or replace function public.revoke_system_owner_admin_sessions(
  p_admin_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_market_name text := '';
  v_sessions integer := 0;
begin
  v_uid := private.require_system_owner();
  perform private.assert_system_owner_permission(
    'owner_revoke_all_sessions', 'admin', p_admin_id
  );

  select coalesce(a.market_name, '')
    into v_market_name
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  select count(*)::integer
    into v_sessions
  from auth.sessions s
  where s.user_id = p_admin_id;

  update auth.refresh_tokens
     set revoked = true,
         updated_at = now()
   where user_id = p_admin_id::text
     and revoked = false;

  delete from auth.sessions
   where user_id = p_admin_id;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    'admin_sessions_revoked',
    jsonb_build_object(
      'permission_key', 'owner_revoke_all_sessions',
      'revoked_session_count', v_sessions,
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'revoked_session_count', v_sessions,
    'permission_key', 'owner_revoke_all_sessions'
  );
end;
$$;

create or replace function public.set_system_owner_admin_lock(
  p_admin_id uuid,
  p_locked boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_market_name text := '';
  v_sessions integer := 0;
  v_permission_key text;
begin
  v_uid := private.require_system_owner();
  v_permission_key := case
    when p_locked then 'owner_lock_suspicious_account'
    else 'owner_unlock_suspicious_account'
  end;

  perform private.assert_system_owner_permission(
    v_permission_key, 'admin', p_admin_id
  );

  select coalesce(a.market_name, '')
    into v_market_name
  from public.profiles a
  where a.id = p_admin_id
    and a.role = 'admin'
    and a.is_system_owner = false;

  if not found then
    raise exception 'admin_not_found' using errcode = 'P0002';
  end if;

  update public.profiles
     set active = not p_locked,
         updated_at = now()
   where id = p_admin_id;

  update auth.users
     set banned_until = case
           when p_locked then now() + interval '100 years'
           else null
         end,
         updated_at = now()
   where id = p_admin_id;

  insert into public.owner_tenant_controls (
    admin_id, lifecycle_status, updated_at, updated_by
  ) values (
    p_admin_id,
    case when p_locked then 'suspended' else 'active' end,
    now(),
    v_uid
  )
  on conflict (admin_id) do update
    set lifecycle_status = excluded.lifecycle_status,
        updated_at = now(),
        updated_by = v_uid;

  if p_locked then
    select count(*)::integer
      into v_sessions
    from auth.sessions s
    where s.user_id = p_admin_id;

    update auth.refresh_tokens
       set revoked = true,
           updated_at = now()
     where user_id = p_admin_id::text
       and revoked = false;

    delete from auth.sessions
     where user_id = p_admin_id;
  end if;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    p_admin_id,
    case when p_locked then 'admin_account_locked' else 'admin_account_unlocked' end,
    jsonb_build_object(
      'permission_key', v_permission_key,
      'locked', p_locked,
      'revoked_session_count', v_sessions,
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'admin_id', p_admin_id,
    'locked', p_locked,
    'active', not p_locked,
    'revoked_session_count', v_sessions,
    'permission_key', v_permission_key
  );
end;
$$;

create or replace function public.get_system_owner_support_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_open integer := 0;
  v_in_progress integer := 0;
  v_waiting integer := 0;
  v_overdue_response integer := 0;
  v_overdue_resolution integer := 0;
  v_resolved_30d integer := 0;
  v_avg_response_hours numeric := 0;
begin
  perform private.assert_system_owner_permission(
    'owner_view_support_history', 'market', null
  );

  select
    count(*) filter (where t.status = 'open')::integer,
    count(*) filter (where t.status = 'in_progress')::integer,
    count(*) filter (where t.status = 'waiting_admin')::integer,
    count(*) filter (
      where t.responded_at is null
        and t.status not in ('resolved','closed')
        and t.response_due_at < now()
    )::integer,
    count(*) filter (
      where t.resolved_at is null
        and t.status <> 'closed'
        and t.resolution_due_at < now()
    )::integer,
    count(*) filter (
      where t.resolved_at >= now() - interval '30 days'
    )::integer,
    coalesce(avg(extract(epoch from (t.responded_at - t.created_at)) / 3600)
      filter (where t.responded_at is not null), 0)::numeric
  into
    v_open,
    v_in_progress,
    v_waiting,
    v_overdue_response,
    v_overdue_resolution,
    v_resolved_30d,
    v_avg_response_hours
  from public.platform_support_tickets t;

  return jsonb_build_object(
    'open_tickets', coalesce(v_open, 0),
    'in_progress_tickets', coalesce(v_in_progress, 0),
    'waiting_admin_tickets', coalesce(v_waiting, 0),
    'overdue_response_tickets', coalesce(v_overdue_response, 0),
    'overdue_resolution_tickets', coalesce(v_overdue_resolution, 0),
    'resolved_30d', coalesce(v_resolved_30d, 0),
    'avg_first_response_hours', round(coalesce(v_avg_response_hours, 0), 2),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_support_tickets_page(
  p_page integer default 1,
  p_per_page integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 30), 1), 100);
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  perform private.assert_system_owner_permission(
    'owner_view_support_history', 'market', null
  );

  select count(*)::integer
    into v_total
  from public.platform_support_tickets;

  select coalesce(jsonb_agg(item order by sort_created desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      t.created_at as sort_created,
      t.id as sort_id,
      jsonb_build_object(
        'id', t.id,
        'admin_id', t.admin_id,
        'market_name', coalesce(a.market_name, ''),
        'admin_name', coalesce(a.name, ''),
        'phone', coalesce(a.phone, ''),
        'category', t.category,
        'subject', t.subject,
        'message', t.message,
        'priority', t.priority,
        'status', t.status,
        'support_tier', t.support_tier,
        'app_version', t.app_version,
        'platform', t.platform,
        'response_due_at', t.response_due_at,
        'resolution_due_at', t.resolution_due_at,
        'responded_at', t.responded_at,
        'resolved_at', t.resolved_at,
        'closed_at', t.closed_at,
        'owner_response', t.owner_response,
        'response_overdue',
          (t.responded_at is null
           and t.status not in ('resolved','closed')
           and t.response_due_at < now()),
        'resolution_overdue',
          (t.resolved_at is null
           and t.status <> 'closed'
           and t.resolution_due_at < now()),
        'created_at', t.created_at,
        'updated_at', t.updated_at
      ) as item
    from public.platform_support_tickets t
    join public.profiles a
      on a.id = t.admin_id
     and a.role = 'admin'
     and a.is_system_owner = false
    order by t.created_at desc, t.id desc
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

create or replace function public.update_system_owner_support_ticket(
  p_ticket_id uuid,
  p_status text,
  p_priority text,
  p_owner_response text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_admin_id uuid;
  v_market_name text := '';
  v_current public.platform_support_tickets%rowtype;
  v_result public.platform_support_tickets%rowtype;
  v_permission_keys jsonb := '[]'::jsonb;
begin
  v_uid := private.require_system_owner();

  if p_status not in ('open','in_progress','waiting_admin','resolved','closed')
     or p_priority not in ('low','normal','high','urgent')
     or char_length(coalesce(p_owner_response, '')) > 3000 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select t.*
    into v_current
  from public.platform_support_tickets t
  where t.id = p_ticket_id
  for update;

  if not found then
    raise exception 'ticket_not_found' using errcode = 'P0002';
  end if;

  v_admin_id := v_current.admin_id;

  perform private.assert_system_owner_permission(
    'owner_view_support_history', 'market', v_admin_id
  );
  v_permission_keys := jsonb_build_array('owner_view_support_history');

  if trim(coalesce(p_owner_response, '')) <> ''
     and trim(p_owner_response) is distinct from v_current.owner_response then
    perform private.assert_system_owner_permission(
      'owner_add_internal_support_note', 'market', v_admin_id
    );
    v_permission_keys := v_permission_keys || jsonb_build_array('owner_add_internal_support_note');
  end if;

  if p_status is distinct from v_current.status then
    if p_status = 'closed' then
      perform private.assert_system_owner_permission(
        'owner_close_support_case', 'market', v_admin_id
      );
      v_permission_keys := v_permission_keys || jsonb_build_array('owner_close_support_case');
    else
      perform private.assert_system_owner_permission(
        'owner_open_support_case', 'market', v_admin_id
      );
      v_permission_keys := v_permission_keys || jsonb_build_array('owner_open_support_case');
    end if;
  end if;

  if p_priority is distinct from v_current.priority then
    perform private.assert_system_owner_permission(
      'owner_open_support_case', 'market', v_admin_id
    );
    if not (v_permission_keys @> jsonb_build_array('owner_open_support_case')) then
      v_permission_keys := v_permission_keys || jsonb_build_array('owner_open_support_case');
    end if;
  end if;

  select coalesce(a.market_name, '')
    into v_market_name
  from public.profiles a
  where a.id = v_admin_id;

  update public.platform_support_tickets t
     set status = p_status,
         priority = p_priority,
         owner_response = case
           when trim(coalesce(p_owner_response, '')) = '' then t.owner_response
           else trim(p_owner_response)
         end,
         responded_at = case
           when t.responded_at is null
             and trim(coalesce(p_owner_response, '')) <> '' then now()
           else t.responded_at
         end,
         resolved_at = case
           when p_status = 'resolved' and t.resolved_at is null then now()
           when p_status not in ('resolved','closed') then null
           else t.resolved_at
         end,
         closed_at = case
           when p_status = 'closed' and t.closed_at is null then now()
           when p_status <> 'closed' then null
           else t.closed_at
         end,
         updated_at = now()
   where t.id = p_ticket_id
  returning * into v_result;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    v_admin_id,
    'support_ticket_updated',
    jsonb_build_object(
      'permission_keys', v_permission_keys,
      'ticket_id', p_ticket_id,
      'status', p_status,
      'previous_status', v_current.status,
      'priority', p_priority,
      'previous_priority', v_current.priority,
      'support_tier', v_result.support_tier,
      'market_name', v_market_name
    )
  );

  return jsonb_build_object(
    'id', v_result.id,
    'status', v_result.status,
    'priority', v_result.priority,
    'responded_at', v_result.responded_at,
    'resolved_at', v_result.resolved_at,
    'closed_at', v_result.closed_at,
    'updated_at', v_result.updated_at,
    'permission_keys', v_permission_keys
  );
end;
$$;

-- Keep the RPC surface authenticated-only.
revoke all on function public.get_system_owner_subscription_overview() from public, anon;
revoke all on function public.get_system_owner_subscriptions_page(integer, integer) from public, anon;
revoke all on function public.set_system_owner_subscription(uuid, text, integer) from public, anon;
revoke all on function public.get_system_owner_security_overview() from public, anon;
revoke all on function public.get_system_owner_security_page(integer, integer) from public, anon;
revoke all on function public.revoke_system_owner_admin_sessions(uuid) from public, anon;
revoke all on function public.set_system_owner_admin_lock(uuid, boolean) from public, anon;
revoke all on function public.get_system_owner_support_overview() from public, anon;
revoke all on function public.get_system_owner_support_tickets_page(integer, integer) from public, anon;
revoke all on function public.update_system_owner_support_ticket(uuid, text, text, text) from public, anon;

grant execute on function public.get_system_owner_subscription_overview() to authenticated;
grant execute on function public.get_system_owner_subscriptions_page(integer, integer) to authenticated;
grant execute on function public.set_system_owner_subscription(uuid, text, integer) to authenticated;
grant execute on function public.get_system_owner_security_overview() to authenticated;
grant execute on function public.get_system_owner_security_page(integer, integer) to authenticated;
grant execute on function public.revoke_system_owner_admin_sessions(uuid) to authenticated;
grant execute on function public.set_system_owner_admin_lock(uuid, boolean) to authenticated;
grant execute on function public.get_system_owner_support_overview() to authenticated;
grant execute on function public.get_system_owner_support_tickets_page(integer, integer) to authenticated;
grant execute on function public.update_system_owner_support_ticket(uuid, text, text, text) to authenticated;
