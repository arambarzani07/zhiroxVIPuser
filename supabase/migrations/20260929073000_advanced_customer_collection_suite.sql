-- Advanced Customer & Collection Suite
-- Adds tenant-scoped customer rules, grouping, relationships, business metadata,
-- document/note vault, approvals, report schedules and intelligence RPCs.

alter table public.profiles
  add column if not exists vip_expires_at timestamptz,
  add column if not exists customer_kind text not null default 'person'
    check (customer_kind in ('person','business'));

create table if not exists public.customer_groups (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  color text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (admin_id, name)
);

create table if not exists public.customer_group_members (
  group_id uuid not null references public.customer_groups(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, customer_id)
);

create table if not exists public.customer_advanced_rules (
  customer_id uuid primary key references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  credit_frozen boolean not null default false,
  watch_status text not null default 'normal'
    check (watch_status in ('normal','watchlist','blacklist')),
  grace_days integer not null default 0 check (grace_days between 0 and 365),
  max_debt_days integer check (max_debt_days is null or max_debt_days between 1 and 3650),
  manager_approval_amount numeric check (manager_approval_amount is null or manager_approval_amount >= 0),
  two_step_approval_amount numeric check (two_step_approval_amount is null or two_step_approval_amount >= 0),
  auto_vip_enabled boolean not null default false,
  auto_vip_months integer not null default 6 check (auto_vip_months between 1 and 60),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_relationships (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  related_customer_id uuid not null references public.profiles(id) on delete cascade,
  relation_type text not null default 'related',
  note text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (customer_id <> related_customer_id),
  unique (admin_id, customer_id, related_customer_id, relation_type)
);

create table if not exists public.customer_business_profiles (
  customer_id uuid primary key references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  company_name text not null default '',
  tax_number text not null default '',
  representative_name text not null default '',
  representative_phone text not null default '',
  invoice_reference text not null default '',
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_notes (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  note_type text not null default 'internal'
    check (note_type in ('internal','photo','voice')),
  body text not null default '',
  media_path text not null default '',
  mime_type text not null default '',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.customer_documents (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'other',
  file_name text not null,
  storage_path text not null,
  mime_type text not null default '',
  size_bytes bigint not null default 0 check (size_bytes >= 0),
  note text not null default '',
  uploaded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.credit_approval_requests (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  debt_amount numeric not null check (debt_amount > 0),
  projected_balance numeric not null default 0,
  required_approvals integer not null default 1 check (required_approvals in (1,2)),
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','consumed')),
  reason text not null default '',
  requested_by uuid not null references public.profiles(id) on delete cascade,
  decided_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.credit_approval_decisions (
  request_id uuid not null references public.credit_approval_requests(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  decision text not null check (decision in ('approved','rejected')),
  note text not null default '',
  created_at timestamptz not null default now(),
  primary key (request_id, actor_id)
);

create table if not exists public.scheduled_reports (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  report_kind text not null default 'daily_summary'
    check (report_kind in ('daily_summary','collections','cash_flow','employee_performance','data_quality')),
  cadence text not null default 'daily'
    check (cadence in ('daily','weekly','monthly')),
  run_hour integer not null default 8 check (run_hour between 0 and 23),
  weekday integer check (weekday is null or weekday between 1 and 7),
  month_day integer check (month_day is null or month_day between 1 and 28),
  recipients jsonb not null default '[]'::jsonb,
  enabled boolean not null default true,
  last_run_at timestamptz,
  next_run_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into storage.buckets(id,name,public,file_size_limit)
values ('customer-vault','customer-vault',false,52428800)
on conflict(id) do update set
  public=false,
  file_size_limit=excluded.file_size_limit;

drop policy if exists customer_vault_tenant_select on storage.objects;
create policy customer_vault_tenant_select
on storage.objects for select to authenticated
using (
  bucket_id='customer-vault'
  and name like ((select private.current_admin_id())::text || '/%')
  and (select private."current_role"()) in ('admin','employee')
);

drop policy if exists customer_vault_tenant_insert on storage.objects;
create policy customer_vault_tenant_insert
on storage.objects for insert to authenticated
with check (
  bucket_id='customer-vault'
  and name like ((select private.current_admin_id())::text || '/%')
  and (select private."current_role"()) in ('admin','employee')
);

drop policy if exists customer_vault_admin_delete on storage.objects;
create policy customer_vault_admin_delete
on storage.objects for delete to authenticated
using (
  bucket_id='customer-vault'
  and name like ((select private.current_admin_id())::text || '/%')
  and (select private."current_role"())='admin'
);

create index if not exists customer_group_members_customer_idx
  on public.customer_group_members(admin_id, customer_id);
create index if not exists customer_relationships_customer_idx
  on public.customer_relationships(admin_id, customer_id);
create index if not exists customer_notes_customer_created_idx
  on public.customer_notes(admin_id, customer_id, created_at desc);
create index if not exists customer_documents_customer_created_idx
  on public.customer_documents(admin_id, customer_id, created_at desc);
create index if not exists credit_approval_requests_inbox_idx
  on public.credit_approval_requests(admin_id, status, created_at desc);
create index if not exists scheduled_reports_due_idx
  on public.scheduled_reports(admin_id, enabled, next_run_at);

alter table public.customer_groups enable row level security;
alter table public.customer_group_members enable row level security;
alter table public.customer_advanced_rules enable row level security;
alter table public.customer_relationships enable row level security;
alter table public.customer_business_profiles enable row level security;
alter table public.customer_notes enable row level security;
alter table public.customer_documents enable row level security;
alter table public.credit_approval_requests enable row level security;
alter table public.credit_approval_decisions enable row level security;
alter table public.scheduled_reports enable row level security;

do $policies$
declare t text;
begin
  foreach t in array array[
    'customer_groups','customer_group_members','customer_advanced_rules',
    'customer_relationships','customer_business_profiles','customer_notes',
    'customer_documents','credit_approval_requests','scheduled_reports'
  ] loop
    execute format('drop policy if exists %I on public.%I', t || '_tenant_select', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (admin_id = (select private.current_admin_id()) and (select private."current_role"()) in (''admin'',''employee''))',
      t || '_tenant_select', t
    );
    execute format('drop policy if exists %I on public.%I', t || '_admin_write', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (admin_id = (select private.current_admin_id()) and (select private."current_role"()) = ''admin'') with check (admin_id = (select private.current_admin_id()) and (select private."current_role"()) = ''admin'')',
      t || '_admin_write', t
    );
  end loop;
end;
$policies$;

drop policy if exists credit_approval_decisions_tenant_select on public.credit_approval_decisions;
create policy credit_approval_decisions_tenant_select
on public.credit_approval_decisions for select to authenticated
using (
  exists (
    select 1 from public.credit_approval_requests r
    where r.id = request_id
      and r.admin_id = (select private.current_admin_id())
      and (select private."current_role"()) in ('admin','employee')
  )
);

drop policy if exists credit_approval_decisions_approver_insert on public.credit_approval_decisions;
create policy credit_approval_decisions_approver_insert
on public.credit_approval_decisions for insert to authenticated
with check (
  actor_id = (select auth.uid())
  and exists (
    select 1
    from public.credit_approval_requests r
    join public.profiles actor on actor.id = (select auth.uid())
    where r.id = request_id
      and r.admin_id = (select private.current_admin_id())
      and (
        actor.role = 'admin'
        or (actor.role = 'employee' and actor.can_set_debt_limit is true)
      )
  )
);

revoke all on public.customer_groups, public.customer_group_members,
  public.customer_advanced_rules, public.customer_relationships,
  public.customer_business_profiles, public.customer_notes,
  public.customer_documents, public.credit_approval_requests,
  public.credit_approval_decisions, public.scheduled_reports
  from public, anon;
grant select, insert, update, delete on public.customer_groups,
  public.customer_group_members, public.customer_advanced_rules,
  public.customer_relationships, public.customer_business_profiles,
  public.customer_notes, public.customer_documents,
  public.credit_approval_requests, public.credit_approval_decisions,
  public.scheduled_reports to authenticated;

create or replace function private.require_tenant_customer(p_customer_id uuid)
returns uuid
language plpgsql
stable
security invoker
set search_path to ''
as $function$
declare v_admin uuid := (select private.current_admin_id());
begin
  if v_admin is null or (select private."current_role"()) not in ('admin','employee') then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = p_customer_id and p.admin_id = v_admin and p.role = 'customer'
  ) then
    raise exception 'customer_not_found' using errcode = 'P0002';
  end if;
  return v_admin;
end;
$function$;

create or replace function public.get_customer_advanced_center(p_customer_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$
with ctx as (
  select private.require_tenant_customer(p_customer_id) as admin_id
),
p as (
  select pr.*
  from public.profiles pr, ctx
  where pr.id = p_customer_id and pr.admin_id = ctx.admin_id
),
rule as (
  select r.* from public.customer_advanced_rules r, ctx
  where r.customer_id = p_customer_id and r.admin_id = ctx.admin_id
),
debt_stats as (
  select
    count(*)::int as debt_count,
    count(*) filter (where d.remaining <= 0)::int as settled_count,
    count(*) filter (
      where d.remaining > 0
        and d.due_date is not null
        and d.due_date + coalesce((select grace_days from rule),0) < current_date
    )::int as overdue_count,
    coalesce(sum(d.amount),0)::numeric as total_debt,
    coalesce(sum(greatest(d.amount-d.remaining,0)),0)::numeric as total_paid,
    coalesce(sum(greatest(d.remaining,0)),0)::numeric as balance,
    max(coalesce(d.custom_date,d.created_at)) as last_debt_at
  from public.debts d
  where d.customer_id = p_customer_id and coalesce(d.is_deleted,false)=false
),
metric as (
  select d.*,
    case when d.total_debt > 0
      then least(1.0,greatest(0.0,(d.total_paid/d.total_debt)::numeric))
      else 0::numeric end as payment_ratio
  from debt_stats d
),
score as (
  select m.*,
    least(100,greatest(0,
      round(
        (m.payment_ratio*55)
        + least(m.settled_count*4,20)
        + case when m.overdue_count=0 then 15 else greatest(0,15-m.overdue_count*5) end
        + case when m.debt_count>=5 then 10 else m.debt_count*2 end
      )
    ))::int as trust_score
  from metric m
),
groups as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',g.id,'name',g.name,'color',g.color
  ) order by g.name),'[]'::jsonb) as items
  from public.customer_group_members gm
  join public.customer_groups g on g.id=gm.group_id
  cross join ctx
  where gm.customer_id=p_customer_id and gm.admin_id=ctx.admin_id
),
rels as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'related_customer_id',r.related_customer_id,
    'name',rp.name,'phone',rp.phone,'relation_type',r.relation_type,'note',r.note
  ) order by r.created_at desc),'[]'::jsonb) as items
  from public.customer_relationships r
  join public.profiles rp on rp.id=r.related_customer_id
  cross join ctx
  where r.customer_id=p_customer_id and r.admin_id=ctx.admin_id
),
business as (
  select coalesce(to_jsonb(b),'{}'::jsonb) as item
  from ctx
  left join public.customer_business_profiles b
    on b.customer_id=p_customer_id and b.admin_id=ctx.admin_id
),
asset_counts as (
  select
    (select count(*) from public.customer_notes n,ctx
      where n.customer_id=p_customer_id and n.admin_id=ctx.admin_id)::int as notes,
    (select count(*) from public.customer_documents d,ctx
      where d.customer_id=p_customer_id and d.admin_id=ctx.admin_id)::int as documents
),
merge_info as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'duplicate_id',m.duplicate_id,'canonical_id',m.canonical_id,
    'merged_by',m.merged_by,'created_at',m.created_at
  ) order by m.created_at desc),'[]'::jsonb) as items
  from public.customer_identity_merges m,ctx
  where m.admin_id=ctx.admin_id
    and (m.duplicate_id=p_customer_id or m.canonical_id=p_customer_id)
)
select jsonb_build_object(
  'profile', to_jsonb(p),
  'rules', coalesce((select to_jsonb(rule) from rule),'{}'::jsonb),
  'groups', groups.items,
  'relationships', rels.items,
  'business', business.item,
  'notes_count', asset_counts.notes,
  'documents_count', asset_counts.documents,
  'merge_history', merge_info.items,
  'trust_score', score.trust_score,
  'risk_score', 100-score.trust_score,
  'collection_priority_score', least(100,
    (100-score.trust_score)
    + least(score.overdue_count*8,30)
    + case when score.balance>0 then 10 else 0 end
    + case when (select is_pinned from p) then 5 else 0 end
  ),
  'payment_ratio', score.payment_ratio,
  'debt_count', score.debt_count,
  'settled_count', score.settled_count,
  'overdue_count', score.overdue_count,
  'balance', score.balance,
  'next_best_action',
    case
      when coalesce((select watch_status from rule),'normal')='blacklist' then 'credit_blocked'
      when coalesce((select credit_frozen from rule),false) then 'credit_frozen'
      when score.overdue_count>0 then 'follow_up_overdue'
      when score.trust_score<45 and score.balance>0 then 'request_payment_plan'
      when score.balance=0 and score.trust_score>=80 then 'eligible_for_vip'
      else 'maintain_relationship'
    end,
  'smart_summary',
    case
      when coalesce((select watch_status from rule),'normal')='blacklist'
        then 'کڕیار لە لیستی ڕاگیراودایە و قەرزی نوێ بۆی ڕێگەپێنەدراوە.'
      when coalesce((select credit_frozen from rule),false)
        then 'قەرزی نوێ بۆ ئەم کڕیارە کاتیی قوفڵ کراوە.'
      when score.overdue_count>0
        then 'کڕیار قەرزی دواکەوتووی هەیە و پێویستی بە بەدواداچوون هەیە.'
      when score.trust_score>=80
        then 'مێژووی پارەدانەوەی کڕیار باشە و دۆخی متمانەپێکراوە.'
      when score.debt_count=0
        then 'هێشتا مێژووی قەرزی کافی بۆ هەڵسەنگاندن نییە.'
      else 'دۆخی کڕیار مامناوەندە؛ مێژووی نوێ بەردەوام چاودێری بکرێت.'
    end
)
from p cross join score cross join groups cross join rels
cross join business cross join asset_counts cross join merge_info;
$function$;

create or replace function public.save_customer_advanced_rules(
  p_customer_id uuid,
  p_credit_frozen boolean default false,
  p_watch_status text default 'normal',
  p_grace_days integer default 0,
  p_max_debt_days integer default null,
  p_manager_approval_amount numeric default null,
  p_two_step_approval_amount numeric default null,
  p_auto_vip_enabled boolean default false,
  p_auto_vip_months integer default 6,
  p_vip_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_admin uuid := private.require_tenant_customer(p_customer_id);
  v_row public.customer_advanced_rules%rowtype;
begin
  if (select private."current_role"()) <> 'admin' then
    raise exception 'admin_required' using errcode='42501';
  end if;
  if p_watch_status not in ('normal','watchlist','blacklist')
     or p_grace_days not between 0 and 365
     or (p_max_debt_days is not null and p_max_debt_days not between 1 and 3650)
     or (p_manager_approval_amount is not null and p_manager_approval_amount < 0)
     or (p_two_step_approval_amount is not null and p_two_step_approval_amount < 0)
     or p_auto_vip_months not between 1 and 60 then
    raise exception 'invalid_rules' using errcode='22023';
  end if;

  insert into public.customer_advanced_rules(
    customer_id,admin_id,credit_frozen,watch_status,grace_days,max_debt_days,
    manager_approval_amount,two_step_approval_amount,auto_vip_enabled,
    auto_vip_months,updated_by,updated_at
  ) values (
    p_customer_id,v_admin,coalesce(p_credit_frozen,false),p_watch_status,
    p_grace_days,p_max_debt_days,p_manager_approval_amount,
    p_two_step_approval_amount,coalesce(p_auto_vip_enabled,false),
    p_auto_vip_months,auth.uid(),now()
  )
  on conflict(customer_id) do update set
    credit_frozen=excluded.credit_frozen,
    watch_status=excluded.watch_status,
    grace_days=excluded.grace_days,
    max_debt_days=excluded.max_debt_days,
    manager_approval_amount=excluded.manager_approval_amount,
    two_step_approval_amount=excluded.two_step_approval_amount,
    auto_vip_enabled=excluded.auto_vip_enabled,
    auto_vip_months=excluded.auto_vip_months,
    updated_by=auth.uid(),
    updated_at=now()
  returning * into v_row;

  update public.profiles
  set vip_expires_at=p_vip_expires_at, updated_at=now()
  where id=p_customer_id and admin_id=v_admin;

  return to_jsonb(v_row);
end;
$function$;

create or replace function public.create_customer_group(p_name text,p_color text default '')
returns uuid
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid := private.current_admin_id(); v_id uuid;
begin
  if v_admin is null or (select private."current_role"())<>'admin' then
    raise exception 'admin_required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_name,'')))<1 then raise exception 'invalid_name'; end if;
  insert into public.customer_groups(admin_id,name,color,created_by)
  values(v_admin,left(trim(p_name),120),left(coalesce(p_color,''),20),auth.uid())
  on conflict(admin_id,name) do update set color=excluded.color
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.set_customer_groups(p_customer_id uuid,p_group_ids uuid[])
returns void
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid := private.require_tenant_customer(p_customer_id);
begin
  if (select private."current_role"())<>'admin' then raise exception 'admin_required' using errcode='42501'; end if;
  delete from public.customer_group_members
  where customer_id=p_customer_id and admin_id=v_admin;
  insert into public.customer_group_members(group_id,customer_id,admin_id)
  select g.id,p_customer_id,v_admin
  from public.customer_groups g
  where g.admin_id=v_admin and g.id=any(coalesce(p_group_ids,array[]::uuid[]))
  on conflict do nothing;
end;
$function$;

create or replace function public.get_customer_groups_catalog()
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
select coalesce(jsonb_agg(jsonb_build_object(
  'id',g.id,'name',g.name,'color',g.color,
  'member_count',(select count(*) from public.customer_group_members gm where gm.group_id=g.id)
) order by g.name),'[]'::jsonb)
from public.customer_groups g
where g.admin_id=(select private.current_admin_id())
  and (select private."current_role"()) in ('admin','employee');
$function$;

create or replace function public.save_customer_business_profile(
  p_customer_id uuid,p_company_name text,p_tax_number text default '',
  p_representative_name text default '',p_representative_phone text default '',
  p_invoice_reference text default ''
)
returns jsonb
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid := private.require_tenant_customer(p_customer_id); v_row public.customer_business_profiles%rowtype;
begin
  if (select private."current_role"())<>'admin' then raise exception 'admin_required' using errcode='42501'; end if;
  insert into public.customer_business_profiles(
    customer_id,admin_id,company_name,tax_number,representative_name,
    representative_phone,invoice_reference,updated_by,updated_at
  ) values (
    p_customer_id,v_admin,left(coalesce(p_company_name,''),200),
    left(coalesce(p_tax_number,''),100),left(coalesce(p_representative_name,''),160),
    left(coalesce(p_representative_phone,''),50),left(coalesce(p_invoice_reference,''),120),
    auth.uid(),now()
  )
  on conflict(customer_id) do update set
    company_name=excluded.company_name,tax_number=excluded.tax_number,
    representative_name=excluded.representative_name,
    representative_phone=excluded.representative_phone,
    invoice_reference=excluded.invoice_reference,updated_by=auth.uid(),updated_at=now()
  returning * into v_row;
  update public.profiles set customer_kind='business',updated_at=now()
  where id=p_customer_id and admin_id=v_admin;
  return to_jsonb(v_row);
end;
$function$;

create or replace function public.add_customer_relationship(
  p_customer_id uuid,p_related_customer_id uuid,p_relation_type text,p_note text default ''
)
returns uuid
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid := private.require_tenant_customer(p_customer_id); v_id uuid;
begin
  if (select private."current_role"())<>'admin' then raise exception 'admin_required' using errcode='42501'; end if;
  perform private.require_tenant_customer(p_related_customer_id);
  if p_customer_id=p_related_customer_id then raise exception 'same_customer' using errcode='22023'; end if;
  insert into public.customer_relationships(
    admin_id,customer_id,related_customer_id,relation_type,note,created_by
  ) values (
    v_admin,p_customer_id,p_related_customer_id,
    left(coalesce(nullif(trim(p_relation_type),''),'related'),80),
    left(coalesce(p_note,''),1000),auth.uid()
  )
  on conflict(admin_id,customer_id,related_customer_id,relation_type)
  do update set note=excluded.note
  returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.add_customer_note(
  p_customer_id uuid,p_note_type text,p_body text default '',
  p_media_path text default '',p_mime_type text default ''
)
returns uuid
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid := private.require_tenant_customer(p_customer_id); v_id uuid;
begin
  if p_note_type not in ('internal','photo','voice') then raise exception 'invalid_note_type'; end if;
  insert into public.customer_notes(
    admin_id,customer_id,note_type,body,media_path,mime_type,created_by
  ) values (
    v_admin,p_customer_id,p_note_type,left(coalesce(p_body,''),5000),
    left(coalesce(p_media_path,''),1000),left(coalesce(p_mime_type,''),160),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.add_customer_document(
  p_customer_id uuid,p_kind text,p_file_name text,p_storage_path text,
  p_mime_type text default '',p_size_bytes bigint default 0,p_note text default ''
)
returns uuid
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid := private.require_tenant_customer(p_customer_id); v_id uuid;
begin
  insert into public.customer_documents(
    admin_id,customer_id,kind,file_name,storage_path,mime_type,size_bytes,note,uploaded_by
  ) values (
    v_admin,p_customer_id,left(coalesce(p_kind,'other'),80),
    left(coalesce(p_file_name,''),255),left(coalesce(p_storage_path,''),1000),
    left(coalesce(p_mime_type,''),160),greatest(coalesce(p_size_bytes,0),0),
    left(coalesce(p_note,''),1000),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.get_customer_assets(p_customer_id uuid)
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
with ctx as (select private.require_tenant_customer(p_customer_id) admin_id)
select jsonb_build_object(
  'notes',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc)
    from public.customer_notes n,ctx
    where n.customer_id=p_customer_id and n.admin_id=ctx.admin_id),'[]'::jsonb),
  'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc)
    from public.customer_documents d,ctx
    where d.customer_id=p_customer_id and d.admin_id=ctx.admin_id),'[]'::jsonb)
);
$function$;

create or replace function public.evaluate_customer_credit_policy(
  p_customer_id uuid,p_debt_amount numeric,p_projected_balance numeric
)
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
with ctx as (select private.require_tenant_customer(p_customer_id) admin_id),
r as (
  select coalesce(ar.credit_frozen,false) credit_frozen,
    coalesce(ar.watch_status,'normal') watch_status,
    ar.manager_approval_amount,ar.two_step_approval_amount,
    ar.max_debt_days,ar.grace_days
  from ctx left join public.customer_advanced_rules ar
    on ar.customer_id=p_customer_id and ar.admin_id=ctx.admin_id
),
approved as (
  select q.id,q.required_approvals
  from public.credit_approval_requests q,ctx
  where q.admin_id=ctx.admin_id and q.customer_id=p_customer_id
    and q.status='approved'
    and abs(q.debt_amount-p_debt_amount)<0.01
    and q.created_at>now()-interval '24 hours'
  order by q.created_at desc limit 1
)
select jsonb_build_object(
  'decision',
    case
      when r.watch_status='blacklist' or r.credit_frozen then 'blocked'
      when approved.id is not null then 'allowed'
      when r.two_step_approval_amount is not null and p_debt_amount>=r.two_step_approval_amount then 'approval_required'
      when r.manager_approval_amount is not null and p_debt_amount>=r.manager_approval_amount then 'approval_required'
      else 'allowed'
    end,
  'reason',
    case
      when r.watch_status='blacklist' then 'blacklist'
      when r.credit_frozen then 'credit_frozen'
      when approved.id is not null then 'approved_request'
      when r.two_step_approval_amount is not null and p_debt_amount>=r.two_step_approval_amount then 'two_step_approval'
      when r.manager_approval_amount is not null and p_debt_amount>=r.manager_approval_amount then 'manager_approval'
      when r.watch_status='watchlist' then 'watchlist'
      else 'ok'
    end,
  'required_approvals',
    case
      when r.two_step_approval_amount is not null and p_debt_amount>=r.two_step_approval_amount then 2
      when r.manager_approval_amount is not null and p_debt_amount>=r.manager_approval_amount then 1
      else 0
    end,
  'approved_request_id',approved.id,
  'watch_status',r.watch_status,
  'max_debt_days',r.max_debt_days,
  'grace_days',r.grace_days,
  'projected_balance',p_projected_balance
)
from r left join approved on true;
$function$;

create or replace function public.request_credit_approval(
  p_customer_id uuid,p_debt_amount numeric,p_projected_balance numeric,p_reason text default ''
)
returns uuid
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid := private.require_tenant_customer(p_customer_id);
v_policy jsonb; v_required int; v_id uuid;
begin
  if p_debt_amount<=0 then raise exception 'invalid_amount'; end if;
  v_policy:=public.evaluate_customer_credit_policy(p_customer_id,p_debt_amount,p_projected_balance);
  if v_policy->>'decision'<>'approval_required' then raise exception 'approval_not_required'; end if;
  v_required:=greatest(1,least(2,coalesce((v_policy->>'required_approvals')::int,1)));
  insert into public.credit_approval_requests(
    admin_id,customer_id,debt_amount,projected_balance,required_approvals,
    reason,requested_by
  ) values (
    v_admin,p_customer_id,p_debt_amount,p_projected_balance,v_required,
    left(coalesce(p_reason,''),1000),auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$function$;

create or replace function public.decide_credit_approval(
  p_request_id uuid,p_decision text,p_note text default ''
)
returns jsonb
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid:=private.current_admin_id(); v_req public.credit_approval_requests%rowtype;
v_approved int; v_rejected int;
begin
  if p_decision not in ('approved','rejected') then raise exception 'invalid_decision'; end if;
  select * into v_req from public.credit_approval_requests r
  where r.id=p_request_id and r.admin_id=v_admin and r.status='pending'
  for update;
  if not found then raise exception 'request_not_found'; end if;
  if not exists (
    select 1 from public.profiles p
    where p.id=auth.uid() and (
      p.role='admin' or (p.role='employee' and p.can_set_debt_limit is true)
    )
  ) then raise exception 'forbidden' using errcode='42501'; end if;
  if v_req.requested_by=auth.uid() and v_req.required_approvals>1 then
    raise exception 'requester_cannot_self_approve' using errcode='42501';
  end if;
  insert into public.credit_approval_decisions(request_id,actor_id,decision,note)
  values(p_request_id,auth.uid(),p_decision,left(coalesce(p_note,''),1000))
  on conflict(request_id,actor_id) do update set
    decision=excluded.decision,note=excluded.note,created_at=now();
  select count(*) filter(where decision='approved'),
         count(*) filter(where decision='rejected')
  into v_approved,v_rejected
  from public.credit_approval_decisions d where d.request_id=p_request_id;
  if v_rejected>0 then
    update public.credit_approval_requests set status='rejected',decided_at=now()
    where id=p_request_id;
  elsif v_approved>=v_req.required_approvals then
    update public.credit_approval_requests set status='approved',decided_at=now()
    where id=p_request_id;
  end if;
  return jsonb_build_object('approved_count',v_approved,'rejected_count',v_rejected,
    'required_approvals',v_req.required_approvals,
    'status',(select status from public.credit_approval_requests where id=p_request_id));
end;
$function$;

create or replace function public.consume_credit_approval(p_request_id uuid)
returns boolean
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid:=private.current_admin_id(); v_count int;
begin
  update public.credit_approval_requests
  set status='consumed',consumed_at=now()
  where id=p_request_id and admin_id=v_admin and status='approved';
  get diagnostics v_count=row_count;
  return v_count>0;
end;
$function$;

create or replace function public.get_credit_approval_inbox(p_limit int default 100)
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
select coalesce(jsonb_agg(jsonb_build_object(
  'id',r.id,'customer_id',r.customer_id,'customer_name',p.name,'phone',p.phone,
  'debt_amount',r.debt_amount,'projected_balance',r.projected_balance,
  'required_approvals',r.required_approvals,'status',r.status,'reason',r.reason,
  'requested_by',r.requested_by,'requested_by_name',actor.name,
  'approved_count',(select count(*) from public.credit_approval_decisions d where d.request_id=r.id and d.decision='approved'),
  'rejected_count',(select count(*) from public.credit_approval_decisions d where d.request_id=r.id and d.decision='rejected'),
  'created_at',r.created_at
) order by (r.status='pending') desc,r.created_at desc),'[]'::jsonb)
from (
  select * from public.credit_approval_requests
  where admin_id=(select private.current_admin_id())
  order by (status='pending') desc,created_at desc
  limit greatest(1,least(coalesce(p_limit,100),300))
) r
join public.profiles p on p.id=r.customer_id
left join public.profiles actor on actor.id=r.requested_by
where (select private."current_role"()) in ('admin','employee');
$function$;

create or replace function public.get_cash_flow_forecast(p_days int default 30)
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
with cfg as (
  select private.current_admin_id() admin_id,
    greatest(1,least(coalesce(p_days,30),365)) days
),
rows as (
  select d.due_date,
    case when upper(coalesce(d.currency,'IQD'))='USD' then d.remaining else 0 end usd,
    case when upper(coalesce(d.currency,'IQD'))<>'USD' then d.remaining else 0 end iqd
  from public.debts d join public.profiles p on p.id=d.customer_id cross join cfg
  left join public.customer_advanced_rules r on r.customer_id=p.id and r.admin_id=cfg.admin_id
  where p.admin_id=cfg.admin_id and p.role='customer'
    and coalesce(d.is_deleted,false)=false and d.remaining>0 and d.due_date is not null
    and d.due_date+coalesce(r.grace_days,0) between current_date and current_date+cfg.days
),
daily as (
  select due_date,sum(iqd)::numeric iqd,sum(usd)::numeric usd,count(*)::int items
  from rows group by due_date order by due_date
)
select jsonb_build_object(
  'days',(select days from cfg),
  'total_iqd',coalesce((select sum(iqd) from rows),0),
  'total_usd',coalesce((select sum(usd) from rows),0),
  'items',coalesce((select jsonb_agg(to_jsonb(d) order by due_date) from daily d),'[]'::jsonb)
);
$function$;

create or replace function public.get_employee_performance(p_days int default 30)
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
with cfg as (
  select private.current_admin_id() admin_id,
    now()-make_interval(days=>greatest(1,least(coalesce(p_days,30),365))) since_at
),
employees as (
  select p.id,p.name,p.phone from public.profiles p,cfg
  where p.admin_id=cfg.admin_id and p.role='employee' and p.active
),
rows as (
  select e.*,
    (select count(*) from public.profiles c,cfg where c.created_by=e.id and c.role='customer' and c.created_at>=cfg.since_at)::int customers_added,
    (select count(*) from public.debts d,cfg where d.created_by=e.id and d.created_at>=cfg.since_at and coalesce(d.is_deleted,false)=false)::int debts_added,
    coalesce((select sum(d.amount) from public.debts d,cfg where d.created_by=e.id and d.created_at>=cfg.since_at and coalesce(d.is_deleted,false)=false),0)::numeric debt_amount,
    (select count(*) from public.payments pay,cfg where pay.created_by=e.id and pay.created_at>=cfg.since_at)::int payments_recorded,
    coalesce((select sum(pay.amount) from public.payments pay,cfg where pay.created_by=e.id and pay.created_at>=cfg.since_at),0)::numeric payment_amount
  from employees e
)
select coalesce(jsonb_agg(to_jsonb(rows) order by payment_amount desc,debt_amount desc,name),'[]'::jsonb)
from rows;
$function$;

create or replace function public.get_customer_anomalies(p_limit int default 100)
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
with cfg as (select private.current_admin_id() admin_id),
events as (
  select
    d.customer_id,d.id::text record_id,'debt'::text kind,d.amount,
    coalesce(d.custom_date,d.created_at) at,
    lag(d.amount) over(partition by d.customer_id order by coalesce(d.custom_date,d.created_at),d.id) prev_amount,
    lag(coalesce(d.custom_date,d.created_at)) over(partition by d.customer_id order by coalesce(d.custom_date,d.created_at),d.id) prev_at
  from public.debts d join public.profiles p on p.id=d.customer_id,cfg
  where p.admin_id=cfg.admin_id and p.role='customer' and coalesce(d.is_deleted,false)=false
),
flagged as (
  select e.*,case
    when e.prev_amount=e.amount and e.prev_at is not null and e.at-e.prev_at<=interval '2 minutes' then 'possible_duplicate'
    when e.amount >= 10000000 then 'large_amount'
    else null end anomaly
  from events e
)
select coalesce(jsonb_agg(jsonb_build_object(
  'customer_id',f.customer_id,'customer_name',p.name,'record_id',f.record_id,
  'kind',f.kind,'amount',f.amount,'at',f.at,'anomaly',f.anomaly
) order by f.at desc),'[]'::jsonb)
from (
  select * from flagged where anomaly is not null
  order by at desc limit greatest(1,least(coalesce(p_limit,100),300))
) f join public.profiles p on p.id=f.customer_id;
$function$;

create or replace function public.get_data_quality_center(p_limit int default 200)
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
with cfg as (select private.current_admin_id() admin_id),
issues as (
  select p.id customer_id,p.name,p.phone,'missing_name' issue
  from public.profiles p,cfg
  where p.admin_id=cfg.admin_id and p.role='customer' and trim(coalesce(p.name,''))=''
  union all
  select p.id,p.name,p.phone,'invalid_phone'
  from public.profiles p,cfg
  where p.admin_id=cfg.admin_id and p.role='customer'
    and length(regexp_replace(coalesce(p.phone,''),'[^0-9]','','g'))<10
  union all
  select d.customer_id,p.name,p.phone,'open_debt_without_due_date'
  from public.debts d join public.profiles p on p.id=d.customer_id,cfg
  where p.admin_id=cfg.admin_id and p.role='customer'
    and coalesce(d.is_deleted,false)=false and d.remaining>0 and d.due_date is null
  union all
  select p.id,p.name,p.phone,'duplicate_name'
  from public.profiles p,cfg
  where p.admin_id=cfg.admin_id and p.role='customer'
    and exists (
      select 1 from public.profiles x
      where x.admin_id=p.admin_id and x.role='customer' and x.id<>p.id
        and lower(trim(x.name))=lower(trim(p.name)) and trim(p.name)<>''
    )
)
select jsonb_build_object(
  'count',(select count(*) from issues),
  'items',coalesce((select jsonb_agg(to_jsonb(i) order by issue,name)
    from (select distinct * from issues limit greatest(1,least(coalesce(p_limit,200),500))) i),'[]'::jsonb)
);
$function$;

create or replace function public.save_scheduled_report(
  p_id uuid default null,p_report_kind text default 'daily_summary',
  p_cadence text default 'daily',p_run_hour int default 8,
  p_weekday int default null,p_month_day int default null,
  p_recipients jsonb default '[]'::jsonb,p_enabled boolean default true
)
returns uuid
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid:=private.current_admin_id(); v_id uuid:=coalesce(p_id,gen_random_uuid()); v_next timestamptz;
begin
  if v_admin is null or (select private."current_role"())<>'admin' then raise exception 'admin_required' using errcode='42501'; end if;
  if p_report_kind not in ('daily_summary','collections','cash_flow','employee_performance','data_quality')
    or p_cadence not in ('daily','weekly','monthly') or p_run_hour not between 0 and 23 then
    raise exception 'invalid_schedule';
  end if;
  v_next:=date_trunc('day',now()) + make_interval(hours=>p_run_hour);
  if v_next<=now() then v_next:=v_next+interval '1 day'; end if;
  insert into public.scheduled_reports(
    id,admin_id,report_kind,cadence,run_hour,weekday,month_day,recipients,
    enabled,next_run_at,created_by,updated_at
  ) values(v_id,v_admin,p_report_kind,p_cadence,p_run_hour,p_weekday,p_month_day,
    coalesce(p_recipients,'[]'::jsonb),coalesce(p_enabled,true),v_next,auth.uid(),now())
  on conflict(id) do update set report_kind=excluded.report_kind,cadence=excluded.cadence,
    run_hour=excluded.run_hour,weekday=excluded.weekday,month_day=excluded.month_day,
    recipients=excluded.recipients,enabled=excluded.enabled,next_run_at=excluded.next_run_at,
    updated_at=now()
  where public.scheduled_reports.admin_id=v_admin;
  return v_id;
end;
$function$;

create or replace function public.get_scheduled_reports()
returns jsonb
language sql stable security invoker set search_path to ''
as $function$
select coalesce(jsonb_agg(to_jsonb(r) order by r.enabled desc,r.next_run_at,r.created_at),'[]'::jsonb)
from public.scheduled_reports r
where r.admin_id=(select private.current_admin_id())
  and (select private."current_role"()) in ('admin','employee');
$function$;

create or replace function private.recalculate_customer_auto_vip(p_customer_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_enabled boolean;
  v_months integer;
  v_grace integer;
  v_total numeric;
  v_paid numeric;
  v_settled integer;
  v_overdue integer;
  v_ratio numeric;
  v_should boolean;
begin
  select r.auto_vip_enabled,r.auto_vip_months,r.grace_days
  into v_enabled,v_months,v_grace
  from public.customer_advanced_rules r
  where r.customer_id=p_customer_id;

  if coalesce(v_enabled,false)=false then
    return;
  end if;

  select
    coalesce(sum(d.amount),0),
    coalesce(sum(greatest(d.amount-d.remaining,0)),0),
    count(*) filter(where d.remaining<=0),
    count(*) filter(
      where d.remaining>0 and d.due_date is not null
        and d.due_date+coalesce(v_grace,0)<current_date
    )
  into v_total,v_paid,v_settled,v_overdue
  from public.debts d
  where d.customer_id=p_customer_id and coalesce(d.is_deleted,false)=false;

  v_ratio:=case when v_total>0 then v_paid/v_total else 0 end;
  v_should:=v_settled>=5 and v_ratio>=0.90 and v_overdue=0;

  update public.profiles
  set is_vip=v_should,
      vip_expires_at=case
        when v_should then now()+make_interval(months=>coalesce(v_months,6))
        else null
      end,
      updated_at=now()
  where id=p_customer_id and role='customer';
end;
$function$;

create or replace function private.customer_auto_vip_refresh_trigger()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare v_customer_id uuid;
begin
  if tg_table_name='payments' then
    select d.customer_id into v_customer_id
    from public.debts d
    where d.id=coalesce(new.debt_id,old.debt_id);
  else
    v_customer_id:=coalesce(new.customer_id,old.customer_id);
  end if;
  if v_customer_id is not null then
    perform private.recalculate_customer_auto_vip(v_customer_id);
  end if;
  return null;
end;
$function$;

drop trigger if exists debts_auto_vip_refresh on public.debts;
create trigger debts_auto_vip_refresh
after insert or update or delete on public.debts
for each row execute function private.customer_auto_vip_refresh_trigger();

drop trigger if exists payments_auto_vip_refresh on public.payments;
create trigger payments_auto_vip_refresh
after insert or update or delete on public.payments
for each row execute function private.customer_auto_vip_refresh_trigger();

create or replace function public.refresh_auto_vip(p_customer_id uuid)
returns jsonb
language plpgsql security invoker set search_path to ''
as $function$
declare v_admin uuid:=private.require_tenant_customer(p_customer_id);
v_rule public.customer_advanced_rules%rowtype; v_total numeric; v_paid numeric;
v_settled int; v_overdue int; v_ratio numeric; v_should boolean;
begin
  select * into v_rule from public.customer_advanced_rules
  where customer_id=p_customer_id and admin_id=v_admin;
  if not found or not v_rule.auto_vip_enabled then
    return jsonb_build_object('changed',false,'reason','disabled');
  end if;
  select coalesce(sum(amount),0),coalesce(sum(greatest(amount-remaining,0)),0),
    count(*) filter(where remaining<=0),
    count(*) filter(where remaining>0 and due_date is not null
      and due_date+v_rule.grace_days<current_date)
  into v_total,v_paid,v_settled,v_overdue
  from public.debts where customer_id=p_customer_id and coalesce(is_deleted,false)=false;
  v_ratio:=case when v_total>0 then v_paid/v_total else 0 end;
  v_should:=v_settled>=5 and v_ratio>=0.90 and v_overdue=0;
  update public.profiles set
    is_vip=v_should,
    vip_expires_at=case when v_should then now()+make_interval(months=>v_rule.auto_vip_months) else null end,
    updated_at=now()
  where id=p_customer_id and admin_id=v_admin;
  return jsonb_build_object('changed',true,'is_vip',v_should,'payment_ratio',v_ratio,
    'settled_count',v_settled,'overdue_count',v_overdue);
end;
$function$;

revoke all on function public.get_customer_advanced_center(uuid),
 public.save_customer_advanced_rules(uuid,boolean,text,integer,integer,numeric,numeric,boolean,integer,timestamptz),
 public.create_customer_group(text,text), public.set_customer_groups(uuid,uuid[]),
 public.get_customer_groups_catalog(), public.save_customer_business_profile(uuid,text,text,text,text,text),
 public.add_customer_relationship(uuid,uuid,text,text),
 public.add_customer_note(uuid,text,text,text,text),
 public.add_customer_document(uuid,text,text,text,text,bigint,text),
 public.get_customer_assets(uuid), public.evaluate_customer_credit_policy(uuid,numeric,numeric),
 public.request_credit_approval(uuid,numeric,numeric,text),
 public.decide_credit_approval(uuid,text,text), public.consume_credit_approval(uuid), public.get_credit_approval_inbox(integer),
 public.get_cash_flow_forecast(integer), public.get_employee_performance(integer),
 public.get_customer_anomalies(integer), public.get_data_quality_center(integer),
 public.save_scheduled_report(uuid,text,text,integer,integer,integer,jsonb,boolean),
 public.get_scheduled_reports(), public.refresh_auto_vip(uuid)
 from public, anon;

grant execute on function public.get_customer_advanced_center(uuid),
 public.save_customer_advanced_rules(uuid,boolean,text,integer,integer,numeric,numeric,boolean,integer,timestamptz),
 public.create_customer_group(text,text), public.set_customer_groups(uuid,uuid[]),
 public.get_customer_groups_catalog(), public.save_customer_business_profile(uuid,text,text,text,text,text),
 public.add_customer_relationship(uuid,uuid,text,text),
 public.add_customer_note(uuid,text,text,text,text),
 public.add_customer_document(uuid,text,text,text,text,bigint,text),
 public.get_customer_assets(uuid), public.evaluate_customer_credit_policy(uuid,numeric,numeric),
 public.request_credit_approval(uuid,numeric,numeric,text),
 public.decide_credit_approval(uuid,text,text), public.get_credit_approval_inbox(integer),
 public.get_cash_flow_forecast(integer), public.get_employee_performance(integer),
 public.get_customer_anomalies(integer), public.get_data_quality_center(integer),
 public.save_scheduled_report(uuid,text,text,integer,integer,integer,jsonb,boolean),
 public.get_scheduled_reports(), public.refresh_auto_vip(uuid)
 to authenticated;
