-- Harden Daftar <-> ZHIROX break-glass recovery authorization and audit.

create table if not exists private.daftar_recovery_audit_chain (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  sequence_no bigint not null,
  event_type text not null,
  actor_id uuid,
  snapshot_id uuid,
  reason text,
  event_payload jsonb not null default '{}'::jsonb,
  prev_event_sha256 text,
  event_sha256 text not null,
  occurred_at timestamptz not null default now(),
  unique(sync_source_id, sequence_no)
);
revoke all on table private.daftar_recovery_audit_chain from public,anon,authenticated;

create table if not exists private.daftar_break_glass_authorizations (
  id uuid primary key default gen_random_uuid(),
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  actor_id uuid not null,
  snapshot_id uuid not null references private.daftar_sync_state_snapshots(id) on delete restrict,
  token_sha256 text not null unique,
  reason text not null,
  preflight jsonb not null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  revoked_at timestamptz
);
create index if not exists daftar_break_glass_active_idx
  on private.daftar_break_glass_authorizations(sync_source_id,expires_at)
  where consumed_at is null and revoked_at is null;
revoke all on table private.daftar_break_glass_authorizations from public,anon,authenticated;

create or replace function private.protect_daftar_recovery_audit_chain()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if current_setting('zhirox.recovery_audit_maintenance',true)='on' then
    return case when tg_op='DELETE' then old else new end;
  end if;
  raise exception 'recovery_audit_chain_is_append_only' using errcode='42501';
end;
$$;
revoke all on function private.protect_daftar_recovery_audit_chain() from public,anon,authenticated;

drop trigger if exists protect_daftar_recovery_audit_chain on private.daftar_recovery_audit_chain;
create trigger protect_daftar_recovery_audit_chain
before update or delete on private.daftar_recovery_audit_chain
for each row execute function private.protect_daftar_recovery_audit_chain();

create or replace function private.append_daftar_recovery_audit(
  p_source_id uuid,
  p_event_type text,
  p_actor_id uuid,
  p_snapshot_id uuid,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare
  v_seq bigint;
  v_prev text;
  v_now timestamptz:=clock_timestamp();
  v_hash text;
  v_id bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('daftar-recovery-audit:'||p_source_id::text,0));
  select sequence_no,event_sha256 into v_seq,v_prev
  from private.daftar_recovery_audit_chain
  where sync_source_id=p_source_id
  order by sequence_no desc limit 1;
  v_seq:=coalesce(v_seq,0)+1;
  v_hash:=encode(extensions.digest(
    coalesce(v_prev,'GENESIS')||':'||v_seq::text||':'||p_source_id::text||':'||
    coalesce(p_event_type,'')||':'||coalesce(p_actor_id::text,'')||':'||coalesce(p_snapshot_id::text,'')||':'||
    coalesce(p_reason,'')||':'||coalesce(p_payload,'{}'::jsonb)::text||':'||v_now::text,
    'sha256'),'hex');
  insert into private.daftar_recovery_audit_chain(
    sync_source_id,sequence_no,event_type,actor_id,snapshot_id,reason,event_payload,prev_event_sha256,event_sha256,occurred_at
  ) values(
    p_source_id,v_seq,left(coalesce(p_event_type,'unknown'),120),p_actor_id,p_snapshot_id,left(coalesce(p_reason,''),1000),
    coalesce(p_payload,'{}'::jsonb),v_prev,v_hash,v_now
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function private.append_daftar_recovery_audit(uuid,text,uuid,uuid,text,jsonb) from public,anon,authenticated;

create or replace function private.verify_daftar_recovery_audit_chain(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_prev text:=null;
  v_hash text;
  v_total integer:=0;
  v_invalid integer:=0;
  v_seq_invalid integer:=0;
begin
  for r in
    select * from private.daftar_recovery_audit_chain
    where sync_source_id=p_source_id
    order by sequence_no
  loop
    v_total:=v_total+1;
    if r.sequence_no<>v_total then v_seq_invalid:=v_seq_invalid+1; end if;
    if r.prev_event_sha256 is distinct from v_prev then v_invalid:=v_invalid+1; end if;
    v_hash:=encode(extensions.digest(
      coalesce(r.prev_event_sha256,'GENESIS')||':'||r.sequence_no::text||':'||r.sync_source_id::text||':'||
      coalesce(r.event_type,'')||':'||coalesce(r.actor_id::text,'')||':'||coalesce(r.snapshot_id::text,'')||':'||
      coalesce(r.reason,'')||':'||coalesce(r.event_payload,'{}'::jsonb)::text||':'||r.occurred_at::text,
      'sha256'),'hex');
    if v_hash is distinct from r.event_sha256 then v_invalid:=v_invalid+1; end if;
    v_prev:=r.event_sha256;
  end loop;
  return jsonb_build_object(
    'status',case when v_invalid=0 and v_seq_invalid=0 then 'healthy' else 'critical' end,
    'events',v_total,'invalid_links_or_hashes',v_invalid,'sequence_errors',v_seq_invalid,
    'last_hash',v_prev
  );
end;
$$;
revoke all on function private.verify_daftar_recovery_audit_chain(uuid) from public,anon,authenticated;

create or replace function private.plan_daftar_break_glass_recovery(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  lkg private.daftar_last_known_good_recovery%rowtype;
  s private.daftar_sync_state_snapshots%rowtype;
  live public.daftar_sync_sources%rowtype;
  v_validation jsonb;
  v_chain jsonb;
  v_audit jsonb;
  v_cursor_regression boolean;
  v_risk text;
begin
  select * into lkg from private.daftar_last_known_good_recovery where sync_source_id=p_source_id;
  if lkg.sync_source_id is null then raise exception 'last_known_good_missing' using errcode='P0002'; end if;
  select * into s from private.daftar_sync_state_snapshots where id=lkg.snapshot_id;
  select * into live from public.daftar_sync_sources where id=p_source_id;
  if live.id is null then raise exception 'sync_source_not_found' using errcode='P0002'; end if;
  v_validation:=private.validate_daftar_sync_state_snapshot(s.id);
  v_chain:=private.verify_daftar_snapshot_chain(p_source_id);
  v_audit:=private.verify_daftar_recovery_audit_chain(p_source_id);
  v_cursor_regression:=coalesce((s.source_state->>'last_contact_id')::bigint,0)<coalesce(live.last_contact_id,0)
    or coalesce((s.source_state->>'last_transaction_id')::bigint,0)<coalesce(live.last_transaction_id,0);
  v_risk:=case
    when v_validation->>'status'<>'pass' or v_chain->>'status'<>'healthy' or v_audit->>'status'<>'healthy' then 'blocked'
    when v_cursor_regression then 'high'
    when jsonb_array_length(s.active_outbox_state)>0 or jsonb_array_length(s.unresolved_dead_letters)>0 then 'elevated'
    else 'low' end;
  return jsonb_build_object(
    'status',case when v_risk='blocked' then 'blocked' else 'ready' end,
    'risk_level',v_risk,
    'snapshot_id',s.id,
    'captured_at',s.captured_at,
    'snapshot_validation',v_validation,
    'snapshot_chain',v_chain,
    'recovery_audit_chain',v_audit,
    'would_regress_live_cursor',v_cursor_regression,
    'active_outbox_events',jsonb_array_length(s.active_outbox_state),
    'unresolved_dead_letters',jsonb_array_length(s.unresolved_dead_letters),
    'live_last_contact_id',live.last_contact_id,
    'live_last_transaction_id',live.last_transaction_id,
    'snapshot_last_contact_id',(s.source_state->>'last_contact_id')::bigint,
    'snapshot_last_transaction_id',(s.source_state->>'last_transaction_id')::bigint
  );
end;
$$;
revoke all on function private.plan_daftar_break_glass_recovery(uuid) from public,anon,authenticated;

create or replace function public.prepare_daftar_break_glass_recovery_service(
  p_actor_id uuid,
  p_source_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_plan jsonb;
  v_token text;
  v_token_hash text;
  v_auth_id uuid;
  v_snapshot_id uuid;
  v_admin_id uuid;
  v_reason text:=left(trim(coalesce(p_reason,'')),1000);
begin
  if auth.role()<>'service_role' then raise exception 'service_role_required' using errcode='42501'; end if;
  if length(v_reason)<20 then raise exception 'break_glass_reason_too_short' using errcode='22023'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_actor_id and p.is_system_owner=true and p.active=true and p.approved=true) then
    raise exception 'system_owner_required' using errcode='42501';
  end if;
  select admin_id into v_admin_id from public.daftar_sync_sources where id=p_source_id;
  if v_admin_id is null then raise exception 'sync_source_not_found' using errcode='P0002'; end if;
  v_plan:=private.plan_daftar_break_glass_recovery(p_source_id);
  if v_plan->>'status'<>'ready' then
    perform private.append_daftar_recovery_audit(p_source_id,'authorization_blocked',p_actor_id,null,v_reason,v_plan);
    raise exception 'recovery_preflight_blocked' using errcode='P0001';
  end if;
  v_snapshot_id:=(v_plan->>'snapshot_id')::uuid;
  update private.daftar_break_glass_authorizations
  set revoked_at=now()
  where sync_source_id=p_source_id and consumed_at is null and revoked_at is null and expires_at>now();
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  v_token_hash:=encode(extensions.digest(v_token,'sha256'),'hex');
  insert into private.daftar_break_glass_authorizations(
    sync_source_id,actor_id,snapshot_id,token_sha256,reason,preflight,expires_at
  ) values(p_source_id,p_actor_id,v_snapshot_id,v_token_hash,v_reason,v_plan,now()+interval '10 minutes')
  returning id into v_auth_id;
  perform private.append_daftar_recovery_audit(p_source_id,'authorization_issued',p_actor_id,v_snapshot_id,v_reason,
    jsonb_build_object('authorization_id',v_auth_id,'expires_in_seconds',600,'risk_level',v_plan->>'risk_level'));
  insert into public.audit_logs(admin_id,actor_id,action,entity_type,entity_id,after_data)
  values(v_admin_id,p_actor_id,'prepare_break_glass_recovery','daftar_sync_source',p_source_id::text,
    jsonb_build_object('authorization_id',v_auth_id,'snapshot_id',v_snapshot_id,'risk_level',v_plan->>'risk_level','expires_in_seconds',600));
  return jsonb_build_object(
    'authorization_id',v_auth_id,
    'one_time_token',v_token,
    'expires_at',now()+interval '10 minutes',
    'snapshot_id',v_snapshot_id,
    'risk_level',v_plan->>'risk_level',
    'preflight',v_plan
  );
end;
$$;

create or replace function public.validate_daftar_break_glass_recovery_service(
  p_actor_id uuid,
  p_source_id uuid,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  a private.daftar_break_glass_authorizations%rowtype;
  v_hash text;
  v_plan jsonb;
begin
  if auth.role()<>'service_role' then raise exception 'service_role_required' using errcode='42501'; end if;
  if not exists(select 1 from public.profiles p where p.id=p_actor_id and p.is_system_owner=true and p.active=true and p.approved=true) then
    raise exception 'system_owner_required' using errcode='42501';
  end if;
  v_hash:=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');
  select * into a from private.daftar_break_glass_authorizations
  where sync_source_id=p_source_id and actor_id=p_actor_id and token_sha256=v_hash
    and consumed_at is null and revoked_at is null and expires_at>now()
  order by issued_at desc limit 1;
  if a.id is null then raise exception 'break_glass_authorization_invalid_or_expired' using errcode='42501'; end if;
  v_plan:=private.plan_daftar_break_glass_recovery(p_source_id);
  if v_plan->>'status'<>'ready' or (v_plan->>'snapshot_id')::uuid<>a.snapshot_id then
    perform private.append_daftar_recovery_audit(p_source_id,'authorization_revalidation_failed',p_actor_id,a.snapshot_id,a.reason,v_plan);
    raise exception 'recovery_preflight_changed' using errcode='P0001';
  end if;
  return jsonb_build_object('authorized',true,'authorization_id',a.id,'snapshot_id',a.snapshot_id,'expires_at',a.expires_at,'preflight',v_plan);
end;
$$;

revoke all on function public.prepare_daftar_break_glass_recovery_service(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.validate_daftar_break_glass_recovery_service(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.prepare_daftar_break_glass_recovery_service(uuid,uuid,text) to service_role;
grant execute on function public.validate_daftar_break_glass_recovery_service(uuid,uuid,text) to service_role;

create or replace function private.guard_daftar_restore_drill_runtime()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_job bigint;
  v_stale integer:=0;
  v_audit_critical integer:=0;
  v_audit jsonb;
begin
  select jobid into v_job from cron.job where jobname='daftar-sync-restore-drill' limit 1;
  if v_job is null then
    perform cron.schedule('daftar-sync-restore-drill','5,20,35,50 * * * *','select private.run_daftar_restore_drill();');
  else
    perform cron.alter_job(job_id=>v_job,schedule=>'5,20,35,50 * * * *',command=>'select private.run_daftar_restore_drill();',active=>true);
  end if;
  for r in
    select s.id,d.checked_at,d.status
    from public.daftar_sync_sources s
    left join private.daftar_restore_drill_state d on d.sync_source_id=s.id
    where s.enabled=true or s.inbound_sync_enabled=true or s.outbound_sync_enabled=true
  loop
    if r.checked_at is null or r.checked_at<now()-interval '25 minutes' then
      v_stale:=v_stale+1;
      perform private.set_daftar_integrity_dead_letter(r.id,'restore_drill_stale',true,jsonb_build_object('last_checked_at',r.checked_at,'last_status',r.status));
    else
      perform private.set_daftar_integrity_dead_letter(r.id,'restore_drill_stale',false,'{}'::jsonb);
    end if;
    v_audit:=private.verify_daftar_recovery_audit_chain(r.id);
    if v_audit->>'status'<>'healthy' then
      v_audit_critical:=v_audit_critical+1;
      perform private.set_daftar_integrity_dead_letter(r.id,'recovery_audit_chain_invalid',true,v_audit);
    else
      perform private.set_daftar_integrity_dead_letter(r.id,'recovery_audit_chain_invalid',false,'{}'::jsonb);
    end if;
  end loop;
  return jsonb_build_object('job','daftar-sync-restore-drill','stale_sources',v_stale,'audit_chain_critical_sources',v_audit_critical);
end;
$$;
revoke all on function private.guard_daftar_restore_drill_runtime() from public,anon,authenticated;

create or replace function private.guard_daftar_sync_runtime_extensions()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_restore jsonb;
begin
  v_restore:=private.guard_daftar_restore_drill_runtime();
  return jsonb_build_object('restore_drill',v_restore,'runtime_jobs',8);
end;
$$;
revoke all on function private.guard_daftar_sync_runtime_extensions() from public,anon,authenticated;
