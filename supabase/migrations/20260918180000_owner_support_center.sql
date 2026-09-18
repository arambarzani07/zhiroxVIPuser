-- Owner Support / SLA Center.
-- Privacy boundary: this stores only platform-support content deliberately submitted
-- by an Admin plus technical metadata. It never queries market business data.

create table if not exists public.platform_support_tickets (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  category text not null
    check (category in ('account','subscription','security','update','backup','notification','performance','other')),
  subject text not null check (char_length(subject) between 3 and 160),
  message text not null check (char_length(message) between 3 and 2500),
  priority text not null default 'normal'
    check (priority in ('low','normal','high','urgent')),
  status text not null default 'open'
    check (status in ('open','in_progress','waiting_admin','resolved','closed')),
  support_tier text not null default 'standard'
    check (support_tier in ('standard','priority','vip')),
  app_version text not null default '',
  platform text not null default '',
  response_due_at timestamptz not null,
  resolution_due_at timestamptz not null,
  responded_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  owner_response text not null default ''
    check (char_length(owner_response) <= 3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_platform_support_tickets_admin_created
  on public.platform_support_tickets(admin_id, created_at desc);
create index if not exists idx_platform_support_tickets_status_due
  on public.platform_support_tickets(status, response_due_at, resolution_due_at);

alter table public.platform_support_tickets enable row level security;
revoke all privileges on table public.platform_support_tickets
  from public, anon, authenticated;
grant select, insert, update, delete on table public.platform_support_tickets
  to service_role;

create or replace function public.create_platform_support_ticket(
  p_category text,
  p_subject text,
  p_message text,
  p_priority text default 'normal',
  p_app_version text default '',
  p_platform text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_tier text := 'standard';
  v_response_minutes integer := 1440;
  v_resolution_minutes integer := 4320;
  v_ticket public.platform_support_tickets%rowtype;
begin
  if v_uid is null or not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.role = 'admin'
      and p.is_system_owner = false
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  if p_category not in ('account','subscription','security','update','backup','notification','performance','other')
     or p_priority not in ('low','normal','high','urgent')
     or char_length(trim(coalesce(p_subject, ''))) not between 3 and 160
     or char_length(trim(coalesce(p_message, ''))) not between 3 and 2500
     or char_length(coalesce(p_app_version, '')) > 80
     or char_length(coalesce(p_platform, '')) > 80 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select coalesce(c.support_tier, 'standard')
    into v_tier
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id = a.id
  where a.id = v_uid;

  if v_tier = 'vip' then
    v_response_minutes := 120;
    v_resolution_minutes := 720;
  elsif v_tier = 'priority' then
    v_response_minutes := 480;
    v_resolution_minutes := 2160;
  end if;

  if p_priority = 'urgent' then
    v_response_minutes := greatest(30, v_response_minutes / 4);
    v_resolution_minutes := greatest(120, v_resolution_minutes / 4);
  elsif p_priority = 'high' then
    v_response_minutes := greatest(60, v_response_minutes / 2);
    v_resolution_minutes := greatest(240, v_resolution_minutes / 2);
  elsif p_priority = 'low' then
    v_response_minutes := v_response_minutes * 2;
    v_resolution_minutes := v_resolution_minutes * 2;
  end if;

  insert into public.platform_support_tickets (
    admin_id,
    category,
    subject,
    message,
    priority,
    status,
    support_tier,
    app_version,
    platform,
    response_due_at,
    resolution_due_at
  ) values (
    v_uid,
    p_category,
    trim(p_subject),
    trim(p_message),
    p_priority,
    'open',
    v_tier,
    left(coalesce(p_app_version, ''), 80),
    left(coalesce(p_platform, ''), 80),
    now() + make_interval(mins => v_response_minutes),
    now() + make_interval(mins => v_resolution_minutes)
  )
  returning * into v_ticket;

  return jsonb_build_object(
    'id', v_ticket.id,
    'status', v_ticket.status,
    'priority', v_ticket.priority,
    'support_tier', v_ticket.support_tier,
    'response_due_at', v_ticket.response_due_at,
    'resolution_due_at', v_ticket.resolution_due_at,
    'created_at', v_ticket.created_at
  );
end;
$$;

create or replace function public.get_my_platform_support_tickets_page(
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
      and p.role = 'admin'
      and p.is_system_owner = false
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  select count(*)::integer
    into v_total
  from public.platform_support_tickets t
  where t.admin_id = v_uid;

  select coalesce(jsonb_agg(item order by sort_created desc, sort_id desc), '[]'::jsonb)
    into v_items
  from (
    select
      t.created_at as sort_created,
      t.id as sort_id,
      jsonb_build_object(
        'id', t.id,
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
        'created_at', t.created_at,
        'updated_at', t.updated_at
      ) as item
    from public.platform_support_tickets t
    where t.admin_id = v_uid
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

create or replace function public.get_system_owner_support_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_open integer := 0;
  v_in_progress integer := 0;
  v_waiting integer := 0;
  v_overdue_response integer := 0;
  v_overdue_resolution integer := 0;
  v_resolved_30d integer := 0;
  v_avg_response_hours numeric := 0;
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
  v_uid uuid := auth.uid();
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 30), 1), 100);
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
  v_uid uuid := auth.uid();
  v_admin_id uuid;
  v_market_name text := '';
  v_current public.platform_support_tickets%rowtype;
  v_result public.platform_support_tickets%rowtype;
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
             and trim(coalesce(p_owner_response, '')) <> ''
             then now()
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
      'ticket_id', p_ticket_id,
      'status', p_status,
      'priority', p_priority,
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
    'updated_at', v_result.updated_at
  );
end;
$$;

revoke all on function public.create_platform_support_ticket(text,text,text,text,text,text)
  from public, anon;
revoke all on function public.get_my_platform_support_tickets_page(integer,integer)
  from public, anon;
revoke all on function public.get_system_owner_support_overview()
  from public, anon;
revoke all on function public.get_system_owner_support_tickets_page(integer,integer)
  from public, anon;
revoke all on function public.update_system_owner_support_ticket(uuid,text,text,text)
  from public, anon;

grant execute on function public.create_platform_support_ticket(text,text,text,text,text,text)
  to authenticated;
grant execute on function public.get_my_platform_support_tickets_page(integer,integer)
  to authenticated;
grant execute on function public.get_system_owner_support_overview()
  to authenticated;
grant execute on function public.get_system_owner_support_tickets_page(integer,integer)
  to authenticated;
grant execute on function public.update_system_owner_support_ticket(uuid,text,text,text)
  to authenticated;
