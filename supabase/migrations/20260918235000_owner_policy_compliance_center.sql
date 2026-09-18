-- Owner Policy & Compliance Center.
-- Platform/account metadata only. No market business content is read.

create table if not exists public.platform_policy_documents (
  id uuid primary key default gen_random_uuid(),
  policy_key text not null,
  version integer not null,
  title text not null,
  body_markdown text not null default '',
  requires_reacceptance boolean not null default true,
  active boolean not null default true,
  published_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null,
  constraint platform_policy_documents_key_check
    check (policy_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  constraint platform_policy_documents_version_check
    check (version > 0),
  constraint platform_policy_documents_title_check
    check (char_length(title) between 1 and 160),
  constraint platform_policy_documents_body_check
    check (char_length(body_markdown) <= 50000),
  unique (policy_key, version)
);

create unique index if not exists platform_policy_documents_one_active_key
  on public.platform_policy_documents(policy_key)
  where active = true;

create table if not exists public.platform_policy_acceptances (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  policy_key text not null,
  version integer not null,
  accepted_at timestamptz not null default now(),
  app_build text null,
  primary key (profile_id, policy_key, version),
  foreign key (policy_key, version)
    references public.platform_policy_documents(policy_key, version)
    on delete cascade
);

create table if not exists public.platform_retention_policy (
  singleton boolean primary key default true check (singleton = true),
  technical_log_days integer not null default 90
    check (technical_log_days between 7 and 3650),
  audit_log_days integer not null default 365
    check (audit_log_days between 30 and 3650),
  auth_session_days integer not null default 30
    check (auth_session_days between 1 and 365),
  updated_at timestamptz not null default now(),
  updated_by uuid null references public.profiles(id) on delete set null
);

insert into public.platform_retention_policy(singleton)
values (true)
on conflict (singleton) do nothing;

alter table public.platform_policy_documents enable row level security;
alter table public.platform_policy_acceptances enable row level security;
alter table public.platform_retention_policy enable row level security;

revoke all on table public.platform_policy_documents from public, anon, authenticated;
revoke all on table public.platform_policy_acceptances from public, anon, authenticated;
revoke all on table public.platform_retention_policy from public, anon, authenticated;

create or replace function public.get_system_owner_policy_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_active_policies integer := 0;
  v_admin_accounts integer := 0;
  v_pending_admins integer := 0;
  v_retention jsonb := '{}'::jsonb;
begin
  v_uid := private.require_system_owner();

  select count(*)::integer
    into v_active_policies
  from public.platform_policy_documents d
  where d.active = true;

  select count(*)::integer
    into v_admin_accounts
  from public.profiles p
  where p.role = 'admin'
    and p.is_system_owner = false;

  select count(*)::integer
    into v_pending_admins
  from public.profiles p
  where p.role = 'admin'
    and p.is_system_owner = false
    and exists (
      select 1
      from public.platform_policy_documents d
      where d.active = true
        and d.requires_reacceptance = true
        and not exists (
          select 1
          from public.platform_policy_acceptances a
          where a.profile_id = p.id
            and a.policy_key = d.policy_key
            and a.version = d.version
        )
    );

  select jsonb_build_object(
    'technical_log_days', r.technical_log_days,
    'audit_log_days', r.audit_log_days,
    'auth_session_days', r.auth_session_days,
    'updated_at', r.updated_at
  )
  into v_retention
  from public.platform_retention_policy r
  where r.singleton = true;

  return jsonb_build_object(
    'active_policy_count', coalesce(v_active_policies, 0),
    'admin_account_count', coalesce(v_admin_accounts, 0),
    'pending_admin_count', coalesce(v_pending_admins, 0),
    'compliant_admin_count', greatest(coalesce(v_admin_accounts, 0) - coalesce(v_pending_admins, 0), 0),
    'retention', coalesce(v_retention, '{}'::jsonb),
    'checked_at', now()
  );
end;
$$;

create or replace function public.get_system_owner_policy_page(
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
  v_uid uuid;
  v_page integer := greatest(coalesce(p_page, 1), 1);
  v_per_page integer := least(greatest(coalesce(p_per_page, 50), 1), 100);
  v_total integer := 0;
  v_documents jsonb := '[]'::jsonb;
  v_admins jsonb := '[]'::jsonb;
  v_retention jsonb := '{}'::jsonb;
begin
  v_uid := private.require_system_owner();

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'policy_key', d.policy_key,
        'version', d.version,
        'title', d.title,
        'body_markdown', d.body_markdown,
        'requires_reacceptance', d.requires_reacceptance,
        'published_at', d.published_at
      )
      order by d.policy_key
    ),
    '[]'::jsonb
  )
  into v_documents
  from public.platform_policy_documents d
  where d.active = true;

  select count(*)::integer
    into v_total
  from public.profiles p
  where p.role = 'admin'
    and p.is_system_owner = false;

  select coalesce(jsonb_agg(item order by sort_created desc, sort_id desc), '[]'::jsonb)
    into v_admins
  from (
    select
      p.created_at as sort_created,
      p.id as sort_id,
      jsonb_build_object(
        'id', p.id,
        'market_name', coalesce(p.market_name, ''),
        'admin_name', coalesce(p.name, ''),
        'phone', coalesce(p.phone, ''),
        'pending_required_count', coalesce(c.pending_required_count, 0),
        'accepted_current_count', coalesce(c.accepted_current_count, 0),
        'active_policy_count', coalesce(c.active_policy_count, 0),
        'last_acceptance_at', c.last_acceptance_at,
        'compliant', coalesce(c.pending_required_count, 0) = 0
      ) as item
    from public.profiles p
    left join lateral (
      select
        count(*) filter (
          where d.active = true
            and d.requires_reacceptance = true
            and a.profile_id is null
        )::integer as pending_required_count,
        count(*) filter (
          where d.active = true
            and a.profile_id is not null
        )::integer as accepted_current_count,
        count(*) filter (where d.active = true)::integer as active_policy_count,
        max(a.accepted_at) as last_acceptance_at
      from public.platform_policy_documents d
      left join public.platform_policy_acceptances a
        on a.profile_id = p.id
       and a.policy_key = d.policy_key
       and a.version = d.version
    ) c on true
    where p.role = 'admin'
      and p.is_system_owner = false
    order by p.created_at desc, p.id desc
    offset (v_page - 1) * v_per_page
    limit v_per_page
  ) rows;

  select jsonb_build_object(
    'technical_log_days', r.technical_log_days,
    'audit_log_days', r.audit_log_days,
    'auth_session_days', r.auth_session_days,
    'updated_at', r.updated_at
  )
  into v_retention
  from public.platform_retention_policy r
  where r.singleton = true;

  return jsonb_build_object(
    'documents', v_documents,
    'admins', v_admins,
    'retention', coalesce(v_retention, '{}'::jsonb),
    'total_items', v_total,
    'total_pages', greatest(1, ceil(v_total::numeric / v_per_page)::integer),
    'page', v_page
  );
end;
$$;

create or replace function public.publish_system_owner_policy_document(
  p_policy_key text,
  p_title text,
  p_body_markdown text,
  p_requires_reacceptance boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_key text := lower(trim(coalesce(p_policy_key, '')));
  v_title text := trim(coalesce(p_title, ''));
  v_body text := coalesce(p_body_markdown, '');
  v_version integer := 1;
  v_id uuid;
begin
  v_uid := private.require_system_owner();

  if v_key !~ '^[a-z][a-z0-9_]{1,63}$' then
    raise exception 'invalid_policy_key' using errcode = '22023';
  end if;
  if char_length(v_title) < 1 or char_length(v_title) > 160 then
    raise exception 'invalid_policy_title' using errcode = '22023';
  end if;
  if char_length(v_body) > 50000 then
    raise exception 'policy_body_too_large' using errcode = '22023';
  end if;

  select coalesce(max(d.version), 0) + 1
    into v_version
  from public.platform_policy_documents d
  where d.policy_key = v_key;

  update public.platform_policy_documents
     set active = false
   where policy_key = v_key
     and active = true;

  insert into public.platform_policy_documents (
    policy_key, version, title, body_markdown,
    requires_reacceptance, active, published_at, updated_by
  ) values (
    v_key, v_version, v_title, v_body,
    coalesce(p_requires_reacceptance, true), true, now(), v_uid
  )
  returning id into v_id;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    null,
    'platform_policy_published',
    jsonb_build_object(
      'policy_key', v_key,
      'version', v_version,
      'requires_reacceptance', coalesce(p_requires_reacceptance, true)
    )
  );

  return jsonb_build_object(
    'id', v_id,
    'policy_key', v_key,
    'version', v_version,
    'requires_reacceptance', coalesce(p_requires_reacceptance, true)
  );
end;
$$;

create or replace function public.set_system_owner_retention_policy(
  p_technical_log_days integer,
  p_audit_log_days integer,
  p_auth_session_days integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  v_uid := private.require_system_owner();

  if p_technical_log_days not between 7 and 3650
     or p_audit_log_days not between 30 and 3650
     or p_auth_session_days not between 1 and 365 then
    raise exception 'invalid_retention_window' using errcode = '22023';
  end if;

  insert into public.platform_retention_policy (
    singleton, technical_log_days, audit_log_days, auth_session_days,
    updated_at, updated_by
  ) values (
    true, p_technical_log_days, p_audit_log_days, p_auth_session_days,
    now(), v_uid
  )
  on conflict (singleton) do update
    set technical_log_days = excluded.technical_log_days,
        audit_log_days = excluded.audit_log_days,
        auth_session_days = excluded.auth_session_days,
        updated_at = now(),
        updated_by = v_uid;

  insert into public.owner_platform_audit (
    actor_id, target_admin_id, action, metadata
  ) values (
    v_uid,
    null,
    'platform_retention_policy_changed',
    jsonb_build_object(
      'technical_log_days', p_technical_log_days,
      'audit_log_days', p_audit_log_days,
      'auth_session_days', p_auth_session_days
    )
  );

  return jsonb_build_object(
    'technical_log_days', p_technical_log_days,
    'audit_log_days', p_audit_log_days,
    'auth_session_days', p_auth_session_days
  );
end;
$$;

create or replace function public.get_platform_policy_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_docs jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'profile_not_available' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'policy_key', d.policy_key,
        'version', d.version,
        'title', d.title,
        'body_markdown', d.body_markdown,
        'requires_reacceptance', d.requires_reacceptance,
        'published_at', d.published_at,
        'accepted', a.profile_id is not null,
        'acceptance_required',
          d.requires_reacceptance = true and a.profile_id is null,
        'accepted_at', a.accepted_at
      )
      order by d.policy_key
    ),
    '[]'::jsonb
  )
  into v_docs
  from public.platform_policy_documents d
  left join public.platform_policy_acceptances a
    on a.profile_id = v_uid
   and a.policy_key = d.policy_key
   and a.version = d.version
  where d.active = true;

  return jsonb_build_object(
    'documents', v_docs,
    'checked_at', now()
  );
end;
$$;

create or replace function public.accept_platform_policy(
  p_policy_key text,
  p_version integer,
  p_app_build text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_key text := lower(trim(coalesce(p_policy_key, '')));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = v_uid
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'profile_not_available' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.platform_policy_documents d
    where d.policy_key = v_key
      and d.version = p_version
      and d.active = true
  ) then
    raise exception 'policy_version_not_current' using errcode = '22023';
  end if;

  insert into public.platform_policy_acceptances (
    profile_id, policy_key, version, accepted_at, app_build
  ) values (
    v_uid, v_key, p_version, now(), nullif(trim(coalesce(p_app_build, '')), '')
  )
  on conflict (profile_id, policy_key, version) do update
    set accepted_at = now(),
        app_build = excluded.app_build;

  return jsonb_build_object(
    'policy_key', v_key,
    'version', p_version,
    'accepted', true,
    'accepted_at', now()
  );
end;
$$;

revoke all on function public.get_system_owner_policy_overview()
  from public, anon;
revoke all on function public.get_system_owner_policy_page(integer, integer)
  from public, anon;
revoke all on function public.publish_system_owner_policy_document(text, text, text, boolean)
  from public, anon;
revoke all on function public.set_system_owner_retention_policy(integer, integer, integer)
  from public, anon;
revoke all on function public.get_platform_policy_state()
  from public, anon;
revoke all on function public.accept_platform_policy(text, integer, text)
  from public, anon;

grant execute on function public.get_system_owner_policy_overview()
  to authenticated;
grant execute on function public.get_system_owner_policy_page(integer, integer)
  to authenticated;
grant execute on function public.publish_system_owner_policy_document(text, text, text, boolean)
  to authenticated;
grant execute on function public.set_system_owner_retention_policy(integer, integer, integer)
  to authenticated;
grant execute on function public.get_platform_policy_state()
  to authenticated;
grant execute on function public.accept_platform_policy(text, integer, text)
  to authenticated;
