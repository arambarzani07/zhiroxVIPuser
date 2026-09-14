-- Final idempotent production-resilience state for Daftar sync, reconciliation,
-- tenant backups/restores, and RPC hardening.

-- 1) Route near-live polling through the lightweight ETag gateway.
do $$
declare
  v_jobid bigint;
  v_command text;
begin
  select jobid, command into v_jobid, v_command
  from cron.job
  where jobname = 'daftar-live-sync-account-28'
  limit 1;

  if v_jobid is not null
     and position('/functions/v1/daftar-sync-gateway' in v_command) = 0
     and position('/functions/v1/daftar-sync' in v_command) > 0 then
    perform cron.alter_job(
      job_id := v_jobid,
      command := replace(v_command, '/functions/v1/daftar-sync', '/functions/v1/daftar-sync-gateway')
    );
  end if;
end
$$;

-- 2) Hourly source-to-target integrity reconciliation.
create table if not exists private.daftar_sync_reconciliation_runs (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  status text not null check (status in ('healthy','unhealthy')),
  checks jsonb not null,
  created_at timestamptz not null default now()
);
revoke all on table private.daftar_sync_reconciliation_runs from public, anon, authenticated;
create index if not exists daftar_sync_reconciliation_runs_source_created_idx
  on private.daftar_sync_reconciliation_runs(sync_source_id, created_at desc);

create or replace function private.run_daftar_sync_reconciliation(p_source_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_checks jsonb;
  v_status text;
begin
  if not exists (select 1 from public.daftar_sync_sources s where s.id = p_source_id) then
    raise exception 'sync_source_not_found' using errcode = 'P0002';
  end if;

  with mapped as (
    select s.* from public.daftar_sync_seen s where s.sync_source_id = p_source_id
  ), source_state as (
    select s.last_contact_id, s.last_transaction_id, s.last_success_at,
           (s.last_success_at is null or s.last_success_at < now() - interval '10 minutes') as sync_stale
    from public.daftar_sync_sources s where s.id = p_source_id
  ), mapping_counts as (
    select count(*) filter (where entity_kind='customer') as mapped_customers,
           count(*) filter (where entity_kind='debt') as mapped_debts,
           count(*) filter (where entity_kind='payment') as mapped_payments,
           count(*) filter (where entity_kind='payment_allocation') as mapped_payment_allocations
    from mapped
  ), orphan_counts as (
    select count(*) filter (where m.entity_kind='customer' and p.id is null) as customer_orphans,
           count(*) filter (where m.entity_kind='debt' and d.id is null) as debt_orphans,
           count(*) filter (where m.entity_kind='payment_allocation' and pay.id is null) as payment_allocation_orphans
    from mapped m
    left join public.profiles p on m.entity_kind='customer' and p.id=m.target_id
    left join public.debts d on m.entity_kind='debt' and d.id=m.target_id
    left join public.payments pay on m.entity_kind='payment_allocation' and pay.id=m.target_id
  ), target_conflicts as (
    select count(*) as duplicate_target_links from (
      select entity_kind,target_id from mapped
      where entity_kind in ('customer','debt','payment_allocation')
      group by entity_kind,target_id having count(*) > 1
    ) q
  ), source_conflicts as (
    select count(*) as duplicate_source_links from (
      select entity_kind,source_id from mapped group by entity_kind,source_id having count(*) > 1
    ) q
  ), mapped_debts as (
    select d.* from mapped m join public.debts d on m.entity_kind='debt' and d.id=m.target_id
  ), payment_totals as (
    select p.debt_id, coalesce(sum(p.amount),0) as paid
    from public.payments p join mapped_debts d on d.id=p.debt_id group by p.debt_id
  ), debt_checks as (
    select count(*) filter (where coalesce(d.remaining,0) < 0) as negative_remaining,
           count(*) filter (where coalesce(d.remaining,0) > coalesce(d.amount,0)) as remaining_over_amount,
           count(*) filter (where cm.target_id is null) as debt_customer_without_source_customer,
           count(*) filter (where abs(coalesce(d.remaining,0)-greatest(coalesce(d.amount,0)-coalesce(pt.paid,0),0)) > 0.01) as balance_mismatches,
           count(*) filter (where coalesce(pt.paid,0) > coalesce(d.amount,0)+0.01) as overpaid_debts
    from mapped_debts d
    left join mapped cm on cm.entity_kind='customer' and cm.target_id=d.customer_id
    left join payment_totals pt on pt.debt_id=d.id
  ), payment_checks as (
    select count(*) as mapped_payment_to_unmapped_debt
    from mapped m
    join public.payments p on m.entity_kind='payment_allocation' and p.id=m.target_id
    left join mapped dm on dm.entity_kind='debt' and dm.target_id=p.debt_id
    where dm.target_id is null
  )
  select jsonb_build_object(
    'last_contact_id',ss.last_contact_id,'last_transaction_id',ss.last_transaction_id,
    'last_success_at',ss.last_success_at,'sync_stale',ss.sync_stale,
    'mapped_customers',mc.mapped_customers,'mapped_debts',mc.mapped_debts,
    'mapped_payments',mc.mapped_payments,'mapped_payment_allocations',mc.mapped_payment_allocations,
    'customer_orphans',oc.customer_orphans,'debt_orphans',oc.debt_orphans,
    'payment_allocation_orphans',oc.payment_allocation_orphans,
    'duplicate_target_links',tc.duplicate_target_links,'duplicate_source_links',sc.duplicate_source_links,
    'negative_remaining',dc.negative_remaining,'remaining_over_amount',dc.remaining_over_amount,
    'debt_customer_without_source_customer',dc.debt_customer_without_source_customer,
    'balance_mismatches',dc.balance_mismatches,'overpaid_debts',dc.overpaid_debts,
    'mapped_payment_to_unmapped_debt',pc.mapped_payment_to_unmapped_debt
  ) into v_checks
  from source_state ss cross join mapping_counts mc cross join orphan_counts oc
  cross join target_conflicts tc cross join source_conflicts sc cross join debt_checks dc cross join payment_checks pc;

  v_status := case when
    coalesce((v_checks->>'sync_stale')::boolean,true)
    or coalesce((v_checks->>'customer_orphans')::bigint,0)>0
    or coalesce((v_checks->>'debt_orphans')::bigint,0)>0
    or coalesce((v_checks->>'payment_allocation_orphans')::bigint,0)>0
    or coalesce((v_checks->>'duplicate_target_links')::bigint,0)>0
    or coalesce((v_checks->>'duplicate_source_links')::bigint,0)>0
    or coalesce((v_checks->>'negative_remaining')::bigint,0)>0
    or coalesce((v_checks->>'remaining_over_amount')::bigint,0)>0
    or coalesce((v_checks->>'debt_customer_without_source_customer')::bigint,0)>0
    or coalesce((v_checks->>'balance_mismatches')::bigint,0)>0
    or coalesce((v_checks->>'overpaid_debts')::bigint,0)>0
    or coalesce((v_checks->>'mapped_payment_to_unmapped_debt')::bigint,0)>0
    then 'unhealthy' else 'healthy' end;

  insert into private.daftar_sync_reconciliation_runs(sync_source_id,status,checks)
  values (p_source_id,v_status,v_checks);
  delete from private.daftar_sync_reconciliation_runs where created_at < now()-interval '90 days';
  return jsonb_build_object('status',v_status,'checks',v_checks);
end;
$$;
revoke all on function private.run_daftar_sync_reconciliation(uuid) from public,anon,authenticated;

do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname='daftar-sync-reconcile-account-28' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
  perform cron.schedule('daftar-sync-reconcile-account-28','17 * * * *',$cron$
    select private.run_daftar_sync_reconciliation(
      (select id from public.daftar_sync_sources where legacy_user_id=28 limit 1)
    );
  $cron$);
end
$$;

-- 3) Scalable, checksummed tenant backups.
alter table public.tenant_backups
  add column if not exists payload_sha256 text,
  add column if not exists last_verified_at timestamptz,
  add column if not exists verification jsonb;
update public.tenant_backups
set payload_sha256=encode(extensions.digest(payload::text,'sha256'),'hex')
where payload_sha256 is null;

create or replace function private.build_tenant_backup_snapshot(p_admin_id uuid)
returns jsonb language sql stable security definer set search_path=''
as $$
  with tenant_profiles as materialized (
    select p.* from public.profiles p where p.id=p_admin_id or p.admin_id=p_admin_id
  ), tenant_debts as materialized (
    select d.* from public.debts d join tenant_profiles p on p.id=d.customer_id
  ), tenant_payments as materialized (
    select pay.* from public.payments pay join tenant_debts d on d.id=pay.debt_id
  )
  select jsonb_build_object(
    'version',1,'created_at',now(),
    'profiles',coalesce((select jsonb_agg(to_jsonb(p)-'password_hash' order by p.id) from tenant_profiles p),'[]'::jsonb),
    'debts',coalesce((select jsonb_agg(to_jsonb(d) order by d.id) from tenant_debts d),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(pay) order by pay.id) from tenant_payments pay),'[]'::jsonb),
    'employee_permissions',coalesce((select jsonb_agg(to_jsonb(ep) order by ep.employee_id) from public.employee_permissions ep where ep.admin_id=p_admin_id),'[]'::jsonb)
  )
$$;
revoke all on function private.build_tenant_backup_snapshot(uuid) from public,anon,authenticated;

create or replace function private.create_tenant_backup_impl(p_label text,p_type text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare tenant_id uuid; backup_id uuid; snapshot jsonb; counts jsonb; checksum text;
begin
  if private."current_role"()<>'admin' then raise exception 'admin_required' using errcode='42501'; end if;
  if p_type not in ('manual','automatic','before_restore') then raise exception 'invalid_backup_type' using errcode='22023'; end if;
  tenant_id:=private.current_admin_id();
  snapshot:=private.build_tenant_backup_snapshot(tenant_id);
  counts:=jsonb_build_object('profiles',jsonb_array_length(snapshot->'profiles'),'debts',jsonb_array_length(snapshot->'debts'),'payments',jsonb_array_length(snapshot->'payments'),'employee_permissions',jsonb_array_length(snapshot->'employee_permissions'));
  checksum:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  insert into public.tenant_backups(admin_id,created_by,label,backup_type,payload,record_counts,payload_sha256,expires_at)
  values(tenant_id,auth.uid(),left(coalesce(nullif(trim(p_label),''),'Backup'),120),p_type,snapshot,counts,checksum,case when p_type='automatic' then now()+interval '7 days' else null end)
  returning id into backup_id;
  insert into public.audit_logs(admin_id,actor_id,action,entity_type,entity_id,after_data)
  values(tenant_id,auth.uid(),'backup','tenant_backups',backup_id::text,counts||jsonb_build_object('payload_sha256',checksum));
  return backup_id;
end;
$$;

create or replace function private.create_tenant_backup_for_admin(p_admin_id uuid,p_label text default 'Automatic daily backup',p_type text default 'automatic')
returns uuid language plpgsql security definer set search_path=''
as $$
declare backup_id uuid; snapshot jsonb; counts jsonb; checksum text;
begin
  if p_type not in ('automatic','before_restore') then raise exception 'service_backup_type_not_allowed' using errcode='22023'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_admin_id and p.role='admin') then raise exception 'admin_not_found' using errcode='P0002'; end if;
  if p_type='automatic' then
    select b.id into backup_id from public.tenant_backups b
    where b.admin_id=p_admin_id and b.backup_type='automatic' and b.created_at>=date_trunc('day',now())
    order by b.created_at desc limit 1;
    if backup_id is not null then return backup_id; end if;
  end if;
  snapshot:=private.build_tenant_backup_snapshot(p_admin_id);
  counts:=jsonb_build_object('profiles',jsonb_array_length(snapshot->'profiles'),'debts',jsonb_array_length(snapshot->'debts'),'payments',jsonb_array_length(snapshot->'payments'),'employee_permissions',jsonb_array_length(snapshot->'employee_permissions'));
  checksum:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  insert into public.tenant_backups(admin_id,created_by,label,backup_type,payload,record_counts,payload_sha256,expires_at)
  values(p_admin_id,null,left(coalesce(nullif(trim(p_label),''),'Automatic backup'),120),p_type,snapshot,counts,checksum,case when p_type='automatic' then now()+interval '7 days' else null end)
  returning id into backup_id;
  insert into public.audit_logs(admin_id,actor_id,action,entity_type,entity_id,after_data)
  values(p_admin_id,null,'backup','tenant_backups',backup_id::text,counts||jsonb_build_object('backup_type',p_type,'automatic',true,'payload_sha256',checksum));
  return backup_id;
end;
$$;
revoke all on function private.create_tenant_backup_for_admin(uuid,text,text) from public,anon,authenticated;
grant execute on function private.create_tenant_backup_for_admin(uuid,text,text) to service_role;

create or replace function private.verify_tenant_backup_for_admin(p_backup_id uuid,p_admin_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare snapshot jsonb; expected_counts jsonb; stored_checksum text; calculated_checksum text; actual_counts jsonb;
structure_valid boolean; counts_valid boolean; checksum_valid boolean; profiles_valid boolean:=false; debts_valid boolean:=false;
debt_financial_valid boolean:=false; payments_valid boolean:=false; payment_amounts_valid boolean:=false; permissions_valid boolean:=false;
restorable boolean; result jsonb;
begin
  select b.payload,b.record_counts,b.payload_sha256 into snapshot,expected_counts,stored_checksum
  from public.tenant_backups b where b.id=p_backup_id and b.admin_id=p_admin_id;
  if snapshot is null then raise exception 'backup_not_found' using errcode='P0002'; end if;
  structure_valid:=coalesce((snapshot->>'version')::integer,0)=1
    and jsonb_typeof(snapshot->'profiles')='array' and jsonb_typeof(snapshot->'debts')='array'
    and jsonb_typeof(snapshot->'payments')='array' and jsonb_typeof(snapshot->'employee_permissions')='array';
  if structure_valid then
    actual_counts:=jsonb_build_object('profiles',jsonb_array_length(snapshot->'profiles'),'debts',jsonb_array_length(snapshot->'debts'),'payments',jsonb_array_length(snapshot->'payments'),'employee_permissions',jsonb_array_length(snapshot->'employee_permissions'));
    counts_valid:=actual_counts=expected_counts;
    select not exists(select 1 from jsonb_to_recordset(snapshot->'profiles') as p(id uuid,admin_id uuid) where p.id<>p_admin_id and p.admin_id is distinct from p_admin_id) into profiles_valid;
    select not exists(select 1 from jsonb_to_recordset(snapshot->'debts') as d(customer_id uuid) left join jsonb_to_recordset(snapshot->'profiles') as p(id uuid) on p.id=d.customer_id where p.id is null) into debts_valid;
    select not exists(select 1 from jsonb_to_recordset(snapshot->'debts') as d(amount numeric,remaining numeric,status text) where d.amount is null or d.amount<=0 or d.remaining is null or d.remaining<0 or d.remaining>d.amount or d.status is distinct from case when d.remaining=0 then 'paid' when d.remaining<d.amount then 'partial' else 'pending' end) into debt_financial_valid;
    select not exists(select 1 from jsonb_to_recordset(snapshot->'payments') as pay(debt_id uuid) left join jsonb_to_recordset(snapshot->'debts') as d(id uuid) on d.id=pay.debt_id where d.id is null) into payments_valid;
    select not exists(select 1 from jsonb_to_recordset(snapshot->'payments') as pay(amount numeric) where pay.amount is null or pay.amount<=0) into payment_amounts_valid;
    select not exists(select 1 from jsonb_to_recordset(snapshot->'employee_permissions') as ep(admin_id uuid) where ep.admin_id is distinct from p_admin_id) into permissions_valid;
  else actual_counts:='{}'::jsonb; counts_valid:=false; end if;
  calculated_checksum:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  checksum_valid:=stored_checksum is not null and stored_checksum=calculated_checksum;
  restorable:=structure_valid and counts_valid and checksum_valid and profiles_valid and debts_valid and debt_financial_valid and payments_valid and payment_amounts_valid and permissions_valid;
  result:=jsonb_build_object('restorable',restorable,'structure_valid',structure_valid,'counts_valid',counts_valid,'checksum_valid',checksum_valid,'profiles_valid',profiles_valid,'debts_valid',debts_valid,'debt_financial_valid',debt_financial_valid,'payments_valid',payments_valid,'payment_amounts_valid',payment_amounts_valid,'permissions_valid',permissions_valid,'record_counts',actual_counts,'verified_at',now());
  update public.tenant_backups set last_verified_at=now(),verification=result where id=p_backup_id and admin_id=p_admin_id;
  return result;
end;
$$;
revoke all on function private.verify_tenant_backup_for_admin(uuid,uuid) from public,anon,authenticated;
grant execute on function private.verify_tenant_backup_for_admin(uuid,uuid) to service_role;

create or replace function public.cleanup_tenant_backups()
returns integer language plpgsql security definer set search_path=''
as $$
declare removed integer:=0; removed_expired integer:=0; removed_excess integer:=0;
begin
  delete from public.tenant_backups b where b.expires_at is not null and b.expires_at<now(); get diagnostics removed_expired=row_count;
  delete from public.tenant_backups b using (
    select id,row_number() over(partition by admin_id order by created_at desc) rn from public.tenant_backups where backup_type='automatic'
  ) ranked where b.id=ranked.id and ranked.rn>3; get diagnostics removed_excess=row_count;
  removed:=removed_expired+removed_excess; return removed;
end;
$$;
revoke all on function public.cleanup_tenant_backups() from public,anon,authenticated;
grant execute on function public.cleanup_tenant_backups() to service_role;

create or replace function private.run_scheduled_tenant_backup(p_admin_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare backup_id uuid; verification_result jsonb; removed integer;
begin
  backup_id:=private.create_tenant_backup_for_admin(p_admin_id,'Automatic daily backup','automatic');
  verification_result:=private.verify_tenant_backup_for_admin(backup_id,p_admin_id);
  removed:=public.cleanup_tenant_backups();
  return jsonb_build_object('backup_id',backup_id,'verification',verification_result,'removed_old_backups',removed);
end;
$$;
revoke all on function private.run_scheduled_tenant_backup(uuid) from public,anon,authenticated;
grant execute on function private.run_scheduled_tenant_backup(uuid) to service_role;

do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid from cron.job where jobname='daily-tenant-backup-account-28' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
  perform cron.schedule('daily-tenant-backup-account-28','30 2 * * *',$cron$
    select private.run_scheduled_tenant_backup((select admin_id from public.daftar_sync_sources where legacy_user_id=28 limit 1));
  $cron$);
end
$$;

-- 4) Transactional bulk restore with strict normal-operation guards.
create or replace function private.guard_debt_financial_state()
returns trigger language plpgsql set search_path=''
as $$
declare v_paid numeric; v_expected_remaining numeric; v_expected_status text;
begin
  if coalesce(current_setting('zhirox.backup_restore',true),'')='on' then
    if private."current_role"()<>'admin' then raise exception 'restore_admin_required' using errcode='42501'; end if;
    if new.amount<=0 or new.remaining<0 or new.remaining>new.amount then raise exception 'invalid_restored_debt_financial_state' using errcode='22023'; end if;
    v_expected_status:=case when new.remaining=0 then 'paid' when new.remaining<new.amount then 'partial' else 'pending' end;
    if new.status is distinct from v_expected_status then raise exception 'invalid_restored_debt_status' using errcode='22023'; end if;
    return new;
  end if;
  if tg_op='INSERT' then if new.remaining is distinct from new.amount or new.status<>'pending' then raise exception 'invalid_initial_debt_state' using errcode='22023'; end if; return new; end if;
  if coalesce(current_setting('zhirox.payment_rpc',true),'')='on' then
    if new.amount<=0 or new.remaining<0 or new.remaining>new.amount then raise exception 'invalid_debt_financial_state' using errcode='22023'; end if;
    v_expected_status:=case when new.remaining=0 then 'paid' when new.remaining<new.amount then 'partial' else 'pending' end;
    if new.status is distinct from v_expected_status then raise exception 'invalid_debt_status' using errcode='22023'; end if; return new;
  end if;
  if new.amount is distinct from old.amount then
    v_paid:=old.amount-old.remaining; if new.amount<v_paid then raise exception 'debt_amount_below_paid_amount' using errcode='22023'; end if;
    v_expected_remaining:=new.amount-v_paid; if new.remaining is distinct from v_expected_remaining then raise exception 'debt_edit_must_preserve_paid_amount' using errcode='22023'; end if;
    new.status:=case when v_expected_remaining=0 then 'paid' when v_expected_remaining<new.amount then 'partial' else 'pending' end; return new;
  end if;
  if new.remaining is distinct from old.remaining or new.status is distinct from old.status then raise exception 'debt_financial_state_requires_payment_rpc' using errcode='42501'; end if;
  return new;
end;
$$;

create or replace function private.guard_payment_active_debt()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if coalesce(current_setting('zhirox.backup_restore',true),'')='on' then return new; end if;
  if not exists(select 1 from public.debts d where d.id=new.debt_id and d.is_deleted=false) then raise exception 'debt_deleted_or_missing' using errcode='23503'; end if;
  return new;
end;
$$;

create or replace function private.normalize_debt_discount()
returns trigger language plpgsql set search_path='pg_catalog'
as $$
declare v_paid numeric:=0;
begin
  if coalesce(current_setting('zhirox.backup_restore',true),'')='on' then
    if private."current_role"()<>'admin' then raise exception 'restore_admin_required' using errcode='42501'; end if;
    new.discount_percent:=coalesce(new.discount_percent,0); new.discount_amount:=coalesce(new.discount_amount,0); new.subtotal:=coalesce(nullif(new.subtotal,0),new.amount);
    if new.amount<=0 or new.subtotal<=0 or new.discount_percent<0 or new.discount_percent>100 then raise exception 'invalid_restored_debt_discount_state' using errcode='22023'; end if;
    return new;
  end if;
  new.discount_percent:=coalesce(new.discount_percent,0); new.discount_amount:=coalesce(new.discount_amount,0); new.subtotal:=coalesce(new.subtotal,0);
  if new.discount_percent<0 or new.discount_percent>100 then raise exception 'invalid_discount_percent'; end if;
  if tg_op='INSERT' then
    if new.subtotal<=0 and coalesce(new.amount,0)>0 then new.subtotal:=new.amount; end if;
    if new.subtotal<=0 then raise exception 'invalid_subtotal'; end if;
    new.discount_amount:=round(new.subtotal*new.discount_percent/100.0,2); new.amount:=new.subtotal-new.discount_amount;
    if new.amount<=0 then raise exception 'discounted_total_must_be_positive'; end if; new.remaining:=new.amount; new.status:='pending'; return new;
  end if;
  if new.amount is distinct from old.amount and new.subtotal is not distinct from old.subtotal and new.discount_percent is not distinct from old.discount_percent and new.discount_amount is not distinct from old.discount_amount then
    if new.amount<=0 then raise exception 'discounted_total_must_be_positive'; end if; new.subtotal:=new.amount; new.discount_percent:=0; new.discount_amount:=0; return new;
  end if;
  if new.subtotal is distinct from old.subtotal or new.discount_percent is distinct from old.discount_percent or new.discount_amount is distinct from old.discount_amount then
    if new.subtotal<=0 then raise exception 'invalid_subtotal'; end if; v_paid:=greatest(old.amount-old.remaining,0);
    new.discount_amount:=round(new.subtotal*new.discount_percent/100.0,2); new.amount:=new.subtotal-new.discount_amount;
    if new.amount<=0 then raise exception 'discounted_total_must_be_positive'; end if; if v_paid>new.amount then raise exception 'discounted_total_below_paid'; end if;
    new.remaining:=new.amount-v_paid; new.status:=case when new.remaining<=0 then 'paid' when v_paid>0 then 'partial' else 'pending' end;
  end if; return new;
end;
$$;

create or replace function private.restore_backup_rows_bulk(p_table regclass,p_rows jsonb,p_conflict_column text,p_excluded_columns text[] default '{}')
returns integer language plpgsql security definer set search_path=''
as $$
declare cols text; updates text; changes text; table_name text; present_columns text[]; affected integer:=0;
begin
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'restore_rows_must_be_array' using errcode='22023'; end if;
  if jsonb_array_length(p_rows)=0 then return 0; end if;
  table_name:=p_table::text; select array_agg(key) into present_columns from jsonb_object_keys(p_rows->0) key;
  if not (p_conflict_column=any(present_columns)) then raise exception 'restore_conflict_column_missing' using errcode='22023'; end if;
  select string_agg(format('%I',a.attname),', ' order by a.attnum),
         string_agg(format('%1$I = excluded.%1$I',a.attname),', ' order by a.attnum) filter(where a.attname<>p_conflict_column),
         string_agg(format('target.%1$I is distinct from excluded.%1$I',a.attname),' or ' order by a.attnum) filter(where a.attname<>p_conflict_column)
  into cols,updates,changes from pg_catalog.pg_attribute a
  where a.attrelid=p_table and a.attnum>0 and not a.attisdropped and a.attgenerated='' and a.attname=any(present_columns) and not(a.attname=any(p_excluded_columns));
  if cols is null then raise exception 'restore_no_compatible_columns' using errcode='22023'; end if;
  if updates is null then execute format('insert into %s as target (%s) select %s from jsonb_populate_recordset(null::%s,$1) r on conflict (%I) do nothing',table_name,cols,cols,table_name,p_conflict_column) using p_rows;
  else execute format('insert into %s as target (%s) select %s from jsonb_populate_recordset(null::%s,$1) r on conflict (%I) do update set %s where %s',table_name,cols,cols,table_name,p_conflict_column,updates,changes) using p_rows; end if;
  get diagnostics affected=row_count; return affected;
end;
$$;
revoke all on function private.restore_backup_rows_bulk(regclass,jsonb,text,text[]) from public,anon,authenticated;

create or replace function private.restore_tenant_backup_impl(p_backup_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare tenant_id uuid; snapshot jsonb; verification_result jsonb; permission_rows jsonb; restored_debts integer:=0; restored_payments integer:=0; restored_permissions integer:=0; safety_backup uuid;
begin
  if private."current_role"()<>'admin' then raise exception 'admin_required' using errcode='42501'; end if;
  tenant_id:=private.current_admin_id();
  select b.payload into snapshot from public.tenant_backups b where b.id=p_backup_id and b.admin_id=tenant_id for share;
  if snapshot is null then raise exception 'backup_not_found' using errcode='P0002'; end if;
  verification_result:=private.verify_tenant_backup_for_admin(p_backup_id,tenant_id);
  if coalesce((verification_result->>'restorable')::boolean,false) is not true then raise exception 'backup_failed_restore_verification' using errcode='22023'; end if;
  if exists(select 1 from jsonb_to_recordset(snapshot->'debts') d(customer_id uuid) left join public.profiles p on p.id=d.customer_id where p.id is null or (p.id<>tenant_id and p.admin_id is distinct from tenant_id)) then raise exception 'backup_customer_identity_missing_or_cross_tenant' using errcode='42501'; end if;
  if exists(select 1 from jsonb_to_recordset(snapshot->'employee_permissions') ep(employee_id uuid,admin_id uuid) left join public.profiles p on p.id=ep.employee_id where ep.admin_id is distinct from tenant_id or p.id is null or p.admin_id is distinct from tenant_id) then raise exception 'backup_employee_identity_missing_or_cross_tenant' using errcode='42501'; end if;
  safety_backup:=public.create_tenant_backup('Automatic safety backup before restore','before_restore');
  perform set_config('zhirox.backup_restore','on',true);
  restored_debts:=private.restore_backup_rows_bulk('public.debts'::regclass,snapshot->'debts','id',array['updated_at']);
  restored_payments:=private.restore_backup_rows_bulk('public.payments'::regclass,snapshot->'payments','id','{}'::text[]);
  select coalesce(jsonb_agg(value||jsonb_build_object('updated_by',auth.uid(),'updated_at',now())),'[]'::jsonb) into permission_rows from jsonb_array_elements(snapshot->'employee_permissions');
  restored_permissions:=private.restore_backup_rows_bulk('public.employee_permissions'::regclass,permission_rows,'employee_id','{}'::text[]);
  perform set_config('zhirox.backup_restore','off',true);
  insert into public.audit_logs(admin_id,actor_id,action,entity_type,entity_id,after_data)
  values(tenant_id,auth.uid(),'backup_restore','tenant_backups',p_backup_id::text,jsonb_build_object('safety_backup_id',safety_backup,'debt_rows_changed',restored_debts,'payment_rows_changed',restored_payments,'permission_rows_changed',restored_permissions,'source_counts',verification_result->'record_counts'));
  return jsonb_build_object('success',true,'safety_backup_id',safety_backup,'debt_rows_changed',restored_debts,'payment_rows_changed',restored_payments,'permission_rows_changed',restored_permissions,'source_counts',verification_result->'record_counts');
exception when others then perform set_config('zhirox.backup_restore','off',true); raise;
end;
$$;
revoke all on function private.restore_tenant_backup_impl(uuid) from public,anon;
grant execute on function private.restore_tenant_backup_impl(uuid) to authenticated,service_role;

create or replace function public.restore_tenant_backup(p_backup_id uuid)
returns jsonb language sql security invoker set search_path=''
as $$ select private.restore_tenant_backup_impl(p_backup_id) $$;
revoke all on function public.restore_tenant_backup(uuid) from public,anon;
grant execute on function public.restore_tenant_backup(uuid) to authenticated,service_role;

create or replace function private.verify_tenant_backup_impl(p_backup_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare tenant_id uuid;
begin
  if private."current_role"()<>'admin' then raise exception 'admin_required' using errcode='42501'; end if;
  tenant_id:=private.current_admin_id(); return private.verify_tenant_backup_for_admin(p_backup_id,tenant_id);
end;
$$;
revoke all on function private.verify_tenant_backup_impl(uuid) from public,anon;
grant execute on function private.verify_tenant_backup_impl(uuid) to authenticated,service_role;

create or replace function public.verify_tenant_backup(p_backup_id uuid)
returns jsonb language sql security invoker set search_path=''
as $$ select private.verify_tenant_backup_impl(p_backup_id) $$;
revoke all on function public.verify_tenant_backup(uuid) from public,anon;
grant execute on function public.verify_tenant_backup(uuid) to authenticated,service_role;

revoke all on function public.owner_set_admin_import_permission(uuid,boolean) from public,anon,authenticated;
grant execute on function public.owner_set_admin_import_permission(uuid,boolean) to service_role;

drop policy if exists customer_read_links_deny_clients on public.customer_read_links;
create policy customer_read_links_deny_clients on public.customer_read_links for all to authenticated using(false) with check(false);