create table if not exists public.platform_limit_catalog (
  limit_key text primary key,
  display_name text not null,
  description text not null default '',
  unit text not null default 'count',
  min_value bigint not null default 0,
  max_value bigint not null,
  zero_means_unlimited boolean not null default true,
  permission_key text not null,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint platform_limit_catalog_key_check check (limit_key ~ '^[a-z0-9_]+$'),
  constraint platform_limit_catalog_range_check check (min_value >= 0 and max_value >= min_value)
);

create table if not exists public.platform_plan_limits (
  plan_key text not null,
  limit_key text not null references public.platform_limit_catalog(limit_key) on delete cascade,
  limit_value bigint not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  primary key (plan_key, limit_key),
  constraint platform_plan_limits_plan_check check (plan_key in ('standard','pro','vip')),
  constraint platform_plan_limits_value_check check (limit_value >= 0)
);

create table if not exists public.owner_tenant_limit_overrides (
  admin_id uuid not null references public.profiles(id) on delete cascade,
  limit_key text not null references public.platform_limit_catalog(limit_key) on delete cascade,
  limit_value bigint not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  primary key (admin_id, limit_key),
  constraint owner_tenant_limit_overrides_value_check check (limit_value >= 0)
);

alter table public.platform_limit_catalog enable row level security;
alter table public.platform_plan_limits enable row level security;
alter table public.owner_tenant_limit_overrides enable row level security;
revoke all on public.platform_limit_catalog from anon, authenticated;
revoke all on public.platform_plan_limits from anon, authenticated;
revoke all on public.owner_tenant_limit_overrides from anon, authenticated;

insert into public.platform_limit_catalog(limit_key,display_name,description,unit,min_value,max_value,zero_means_unlimited,permission_key,sort_order)
values
  ('staff_limit','سنووری کارمەند','زۆرترین ژمارەی کارمەندی چالاک بۆ مارکێت','count',0,1000,true,'owner_set_employee_limit',10),
  ('customer_limit','سنووری کڕیار','زۆرترین ژمارەی کڕیار بۆ مارکێت','count',0,1000000,true,'owner_set_customer_limit',20),
  ('device_limit','سنووری ئامێر','زۆرترین ژمارەی ئامێری پەسەندکراوی بەڕێوەبەر','count',0,100,true,'owner_set_device_limit',30)
on conflict (limit_key) do update set
  display_name=excluded.display_name,
  description=excluded.description,
  unit=excluded.unit,
  min_value=excluded.min_value,
  max_value=excluded.max_value,
  zero_means_unlimited=excluded.zero_means_unlimited,
  permission_key=excluded.permission_key,
  sort_order=excluded.sort_order,
  active=true,
  updated_at=now();

insert into public.platform_plan_limits(plan_key,limit_key,limit_value)
values
  ('standard','staff_limit',3),('standard','customer_limit',0),('standard','device_limit',5),
  ('pro','staff_limit',10),('pro','customer_limit',0),('pro','device_limit',10),
  ('vip','staff_limit',50),('vip','customer_limit',0),('vip','device_limit',25)
on conflict (plan_key,limit_key) do nothing;

create or replace function private.get_effective_tenant_limit(p_admin_id uuid, p_limit_key text)
returns bigint
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_plan text;
  v_value bigint;
begin
  select coalesce(c.feature_plan,'standard') into v_plan
  from public.profiles a
  left join public.owner_tenant_controls c on c.admin_id=a.id
  where a.id=p_admin_id and a.role='admin' and a.is_system_owner=false;
  if not found then raise exception 'admin_not_found' using errcode='P0002'; end if;

  select o.limit_value into v_value
  from public.owner_tenant_limit_overrides o
  where o.admin_id=p_admin_id and o.limit_key=p_limit_key;
  if found then return v_value; end if;

  select pl.limit_value into v_value
  from public.platform_plan_limits pl
  where pl.plan_key=v_plan and pl.limit_key=p_limit_key;
  if found then return v_value; end if;

  raise exception 'limit_not_found:%', p_limit_key using errcode='P0002';
end;
$$;

create or replace function public.service_get_tenant_limit(p_admin_id uuid,p_limit_key text)
returns bigint
language sql
stable
security definer
set search_path=''
as $$ select private.get_effective_tenant_limit(p_admin_id,p_limit_key); $$;
revoke all on function public.service_get_tenant_limit(uuid,text) from public,anon,authenticated;
grant execute on function public.service_get_tenant_limit(uuid,text) to service_role;

create or replace function public.get_system_owner_plan_limits()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_catalog jsonb; v_plans jsonb;
begin
  perform private.assert_system_owner_permission('owner_view_feature_catalog','market',null);
  select coalesce(jsonb_agg(jsonb_build_object(
    'limit_key',c.limit_key,'display_name',c.display_name,'description',c.description,
    'unit',c.unit,'min_value',c.min_value,'max_value',c.max_value,
    'zero_means_unlimited',c.zero_means_unlimited,'permission_key',c.permission_key
  ) order by c.sort_order,c.limit_key),'[]'::jsonb) into v_catalog
  from public.platform_limit_catalog c where c.active=true;

  select coalesce(jsonb_object_agg(plan_key,limits),'{}'::jsonb) into v_plans
  from (
    select pl.plan_key,jsonb_object_agg(pl.limit_key,pl.limit_value order by pl.limit_key) limits
    from public.platform_plan_limits pl group by pl.plan_key
  ) s;
  return jsonb_build_object('catalog',v_catalog,'plans',v_plans);
end;
$$;

create or replace function public.set_system_owner_plan_limit(p_plan_key text,p_limit_key text,p_limit_value bigint)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid; v_plan text:=lower(trim(coalesce(p_plan_key,''))); v_max bigint; v_perm text; v_plan_perm text;
begin
  v_uid:=private.require_system_owner();
  if v_plan not in ('standard','pro','vip') then raise exception 'invalid_feature_plan' using errcode='22023'; end if;
  select c.max_value,c.permission_key into v_max,v_perm from public.platform_limit_catalog c where c.limit_key=p_limit_key and c.active=true;
  if not found or p_limit_value<0 or p_limit_value>v_max then raise exception 'invalid_limit_value' using errcode='22023'; end if;
  v_plan_perm:=case v_plan when 'standard' then 'owner_edit_standard_plan_features' when 'pro' then 'owner_edit_pro_plan_features' else 'owner_edit_vip_plan_features' end;
  perform private.assert_system_owner_permission(v_plan_perm,'market',null);
  perform private.assert_system_owner_permission(v_perm,'market',null);
  insert into public.platform_plan_limits(plan_key,limit_key,limit_value,updated_at,updated_by)
  values(v_plan,p_limit_key,p_limit_value,now(),v_uid)
  on conflict(plan_key,limit_key) do update set limit_value=excluded.limit_value,updated_at=now(),updated_by=v_uid;
  insert into public.owner_platform_audit(actor_id,target_admin_id,action,metadata)
  values(v_uid,null,'plan_resource_limit_changed',jsonb_build_object('plan_key',v_plan,'limit_key',p_limit_key,'limit_value',p_limit_value,'permission_keys',jsonb_build_array(v_plan_perm,v_perm)));
  return jsonb_build_object('plan_key',v_plan,'limit_key',p_limit_key,'limit_value',p_limit_value);
end;
$$;

create or replace function public.get_system_owner_tenant_limits(p_admin_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_plan text; v_items jsonb;
begin
  perform private.assert_system_owner_permission('owner_view_market_profile','market',p_admin_id);
  select coalesce(c.feature_plan,'standard') into v_plan
  from public.profiles a left join public.owner_tenant_controls c on c.admin_id=a.id
  where a.id=p_admin_id and a.role='admin' and a.is_system_owner=false;
  if not found then raise exception 'admin_not_found' using errcode='P0002'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'limit_key',lc.limit_key,'display_name',lc.display_name,'description',lc.description,
    'min_value',lc.min_value,'max_value',lc.max_value,'zero_means_unlimited',lc.zero_means_unlimited,
    'permission_key',lc.permission_key,'plan_value',pl.limit_value,'override_value',o.limit_value,
    'effective_value',coalesce(o.limit_value,pl.limit_value),'source',case when o.limit_key is not null then 'override' else 'plan' end
  ) order by lc.sort_order,lc.limit_key),'[]'::jsonb) into v_items
  from public.platform_limit_catalog lc
  left join public.platform_plan_limits pl on pl.plan_key=v_plan and pl.limit_key=lc.limit_key
  left join public.owner_tenant_limit_overrides o on o.admin_id=p_admin_id and o.limit_key=lc.limit_key
  where lc.active=true;
  return jsonb_build_object('admin_id',p_admin_id,'plan_key',v_plan,'limits',v_items);
end;
$$;

create or replace function public.set_system_owner_tenant_limit_override(p_admin_id uuid,p_limit_key text,p_limit_value bigint default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid; v_max bigint; v_perm text; v_effective bigint;
begin
  v_uid:=private.require_system_owner();
  if not exists(select 1 from public.profiles p where p.id=p_admin_id and p.role='admin' and p.is_system_owner=false) then raise exception 'admin_not_found' using errcode='P0002'; end if;
  select c.max_value,c.permission_key into v_max,v_perm from public.platform_limit_catalog c where c.limit_key=p_limit_key and c.active=true;
  if not found then raise exception 'limit_not_found' using errcode='P0002'; end if;
  perform private.assert_system_owner_permission(v_perm,'market',p_admin_id);
  if p_limit_value is null then
    delete from public.owner_tenant_limit_overrides where admin_id=p_admin_id and limit_key=p_limit_key;
  else
    if p_limit_value<0 or p_limit_value>v_max then raise exception 'invalid_limit_value' using errcode='22023'; end if;
    insert into public.owner_tenant_limit_overrides(admin_id,limit_key,limit_value,updated_at,updated_by)
    values(p_admin_id,p_limit_key,p_limit_value,now(),v_uid)
    on conflict(admin_id,limit_key) do update set limit_value=excluded.limit_value,updated_at=now(),updated_by=v_uid;
  end if;
  v_effective:=private.get_effective_tenant_limit(p_admin_id,p_limit_key);
  insert into public.owner_platform_audit(actor_id,target_admin_id,action,metadata)
  values(v_uid,p_admin_id,'tenant_resource_limit_override_changed',jsonb_build_object('limit_key',p_limit_key,'override_value',p_limit_value,'effective_value',v_effective,'permission_key',v_perm,'inherit',p_limit_value is null));
  return jsonb_build_object('admin_id',p_admin_id,'limit_key',p_limit_key,'override_value',p_limit_value,'effective_value',v_effective,'source',case when p_limit_value is null then 'plan' else 'override' end);
end;
$$;

revoke all on function public.get_system_owner_plan_limits() from public,anon;
revoke all on function public.set_system_owner_plan_limit(text,text,bigint) from public,anon;
revoke all on function public.get_system_owner_tenant_limits(uuid) from public,anon;
revoke all on function public.set_system_owner_tenant_limit_override(uuid,text,bigint) from public,anon;
grant execute on function public.get_system_owner_plan_limits() to authenticated;
grant execute on function public.set_system_owner_plan_limit(text,text,bigint) to authenticated;
grant execute on function public.get_system_owner_tenant_limits(uuid) to authenticated;
grant execute on function public.set_system_owner_tenant_limit_override(uuid,text,bigint) to authenticated;

create or replace function public.register_platform_admin_device(p_device_id text,p_platform text default 'unknown',p_device_label text default 'ZHIROX app',p_app_version text default 'unknown')
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid(); v_session_id uuid:=nullif(auth.jwt()->>'session_id','')::uuid; v_device_id text:=trim(coalesce(p_device_id,''));
  v_device_hash text; v_policy text:='observe'; v_device_limit integer:=5; v_existing_status text; v_status text; v_id uuid; v_approved_count integer:=0;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin' and p.is_system_owner=false and p.active=true and p.approved=true) then raise exception 'admin_account_required' using errcode='42501'; end if;
  if length(v_device_id)<16 or length(v_device_id)>256 then raise exception 'invalid_device_id' using errcode='22023'; end if;
  v_device_hash:=encode(extensions.digest(v_uid::text||':'||v_device_id,'sha256'),'hex');
  select coalesce(c.device_policy_mode,'observe') into v_policy from public.owner_tenant_controls c where c.admin_id=v_uid;
  v_policy:=coalesce(v_policy,'observe');
  v_device_limit:=private.get_effective_tenant_limit(v_uid,'device_limit')::integer;
  select d.status into v_existing_status from public.platform_admin_devices d where d.admin_id=v_uid and d.device_hash=v_device_hash;
  if found then v_status:=v_existing_status; else
    select count(*)::integer into v_approved_count from public.platform_admin_devices d where d.admin_id=v_uid and d.status='approved';
    v_status:=case when v_policy='approval_required' then 'pending' when v_device_limit>0 and v_approved_count>=v_device_limit then 'pending' else 'approved' end;
  end if;
  insert into public.platform_admin_devices(admin_id,device_hash,device_label,platform,app_version,status,last_session_id,first_seen_at,last_seen_at,approved_at)
  values(v_uid,v_device_hash,left(coalesce(nullif(trim(p_device_label),''),'ZHIROX app'),80),left(coalesce(nullif(trim(p_platform),''),'unknown'),32),left(coalesce(nullif(trim(p_app_version),''),'unknown'),40),v_status,v_session_id,now(),now(),case when v_status='approved' then now() else null end)
  on conflict(admin_id,device_hash) do update set device_label=excluded.device_label,platform=excluded.platform,app_version=excluded.app_version,last_session_id=excluded.last_session_id,last_seen_at=now()
  returning id,status into v_id,v_status;
  return jsonb_build_object('device_id',v_id,'status',v_status,'policy',v_policy,'allowed',v_status='approved','device_limit',v_device_limit,'limit_source','plan_or_override');
end; $$;
