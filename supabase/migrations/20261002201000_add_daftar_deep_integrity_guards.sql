-- Deep continuity hardening for Daftar <-> ZHIROX.
-- Adds cursor high-water anomaly detection, mirror/seen hash parity checks,
-- queue-age SLO monitoring, and a self-healing deep-integrity runtime job.

create table if not exists private.daftar_cursor_high_water (
  sync_source_id uuid primary key references public.daftar_sync_sources(id) on delete cascade,
  max_contact_id bigint,
  max_transaction_id bigint,
  updated_at timestamptz not null default now()
);
revoke all on table private.daftar_cursor_high_water from public, anon, authenticated;

insert into private.daftar_cursor_high_water(sync_source_id,max_contact_id,max_transaction_id)
select id,last_contact_id,last_transaction_id
from public.daftar_sync_sources
on conflict (sync_source_id) do update
set max_contact_id = greatest(private.daftar_cursor_high_water.max_contact_id, excluded.max_contact_id),
    max_transaction_id = greatest(private.daftar_cursor_high_water.max_transaction_id, excluded.max_transaction_id),
    updated_at = now();

create table if not exists private.daftar_cursor_anomalies (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  cursor_name text not null check (cursor_name in ('contact','transaction')),
  high_water bigint not null,
  observed_value bigint not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution_note text
);
create unique index if not exists daftar_cursor_anomalies_open_unique
  on private.daftar_cursor_anomalies(sync_source_id,cursor_name)
  where resolved_at is null;
revoke all on table private.daftar_cursor_anomalies from public, anon, authenticated;

create or replace function private.track_daftar_cursor_high_water()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contact_high bigint;
  v_tx_high bigint;
begin
  insert into private.daftar_cursor_high_water(sync_source_id,max_contact_id,max_transaction_id)
  values (new.id,new.last_contact_id,new.last_transaction_id)
  on conflict (sync_source_id) do nothing;

  select max_contact_id,max_transaction_id
  into v_contact_high,v_tx_high
  from private.daftar_cursor_high_water
  where sync_source_id=new.id
  for update;

  if new.last_contact_id is not null then
    if v_contact_high is not null and new.last_contact_id < v_contact_high then
      update private.daftar_cursor_anomalies
      set high_water=v_contact_high, observed_value=new.last_contact_id, last_seen_at=now()
      where sync_source_id=new.id and cursor_name='contact' and resolved_at is null;
      if not found then
        insert into private.daftar_cursor_anomalies(sync_source_id,cursor_name,high_water,observed_value)
        values(new.id,'contact',v_contact_high,new.last_contact_id);
      end if;
    else
      update private.daftar_cursor_high_water
      set max_contact_id=greatest(coalesce(max_contact_id,new.last_contact_id),new.last_contact_id),updated_at=now()
      where sync_source_id=new.id;
      update private.daftar_cursor_anomalies
      set resolved_at=now(),resolution_note='cursor_recovered_to_high_water',last_seen_at=now()
      where sync_source_id=new.id and cursor_name='contact' and resolved_at is null
        and new.last_contact_id >= high_water;
    end if;
  end if;

  if new.last_transaction_id is not null then
    if v_tx_high is not null and new.last_transaction_id < v_tx_high then
      update private.daftar_cursor_anomalies
      set high_water=v_tx_high, observed_value=new.last_transaction_id, last_seen_at=now()
      where sync_source_id=new.id and cursor_name='transaction' and resolved_at is null;
      if not found then
        insert into private.daftar_cursor_anomalies(sync_source_id,cursor_name,high_water,observed_value)
        values(new.id,'transaction',v_tx_high,new.last_transaction_id);
      end if;
    else
      update private.daftar_cursor_high_water
      set max_transaction_id=greatest(coalesce(max_transaction_id,new.last_transaction_id),new.last_transaction_id),updated_at=now()
      where sync_source_id=new.id;
      update private.daftar_cursor_anomalies
      set resolved_at=now(),resolution_note='cursor_recovered_to_high_water',last_seen_at=now()
      where sync_source_id=new.id and cursor_name='transaction' and resolved_at is null
        and new.last_transaction_id >= high_water;
    end if;
  end if;

  return new;
end;
$$;
revoke all on function private.track_daftar_cursor_high_water() from public, anon, authenticated;

drop trigger if exists daftar_sync_sources_cursor_high_water on public.daftar_sync_sources;
create trigger daftar_sync_sources_cursor_high_water
after update of last_contact_id,last_transaction_id on public.daftar_sync_sources
for each row execute function private.track_daftar_cursor_high_water();

create table if not exists private.daftar_deep_integrity_state (
  sync_source_id uuid primary key references public.daftar_sync_sources(id) on delete cascade,
  checked_at timestamptz not null default now(),
  contact_hash_or_mapping_mismatches integer not null default 0,
  transaction_hash_or_mapping_mismatches integer not null default 0,
  open_cursor_anomalies integer not null default 0,
  status text not null default 'healthy' check (status in ('healthy','critical')),
  details jsonb not null default '{}'::jsonb
);
revoke all on table private.daftar_deep_integrity_state from public, anon, authenticated;

create or replace function private.set_daftar_integrity_dead_letter(
  p_source_id uuid,
  p_error_code text,
  p_active boolean,
  p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_active then
    insert into public.daftar_sync_dead_letters(sync_source_id,entity_kind,source_id,error_code,error_detail,payload)
    values(p_source_id,'integrity',p_error_code,p_error_code,p_error_code,p_details)
    on conflict (sync_source_id,entity_kind,coalesce(source_id,''),error_code)
      where resolved_at is null
    do update set attempts=public.daftar_sync_dead_letters.attempts+1,
                  last_seen_at=now(),payload=excluded.payload,error_detail=excluded.error_detail;
  else
    update public.daftar_sync_dead_letters
    set resolved_at=now(),resolution_note='auto_resolved_after_integrity_recovered'
    where sync_source_id=p_source_id and entity_kind='integrity'
      and source_id=p_error_code and error_code=p_error_code and resolved_at is null;
  end if;
end;
$$;
revoke all on function private.set_daftar_integrity_dead_letter(uuid,text,boolean,jsonb) from public, anon, authenticated;

create or replace function private.run_daftar_deep_integrity_check()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
  v_contacts integer;
  v_transactions integer;
  v_cursor integer;
  v_status text;
  v_healthy integer := 0;
  v_critical integer := 0;
  v_details jsonb;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('zhirox-daftar-deep-integrity',0)) then
    return jsonb_build_object('skipped','already_running');
  end if;

  for r in
    select id from public.daftar_sync_sources
    where enabled=true or inbound_sync_enabled=true or outbound_sync_enabled=true
    order by created_at
  loop
    select count(*) into v_contacts
    from public.daftar_mirror_contacts m
    left join public.daftar_sync_seen s
      on s.sync_source_id=m.sync_source_id and s.entity_kind='customer' and s.source_id=m.source_id
    where m.sync_source_id=r.id
      and (s.source_id is null or (s.payload_hash is not null and s.payload_hash is distinct from m.payload_hash));

    select count(*) into v_transactions
    from public.daftar_mirror_transactions m
    left join public.daftar_sync_seen s
      on s.sync_source_id=m.sync_source_id
     and s.entity_kind = case
       when coalesce(nullif(m.payload->>'amount','')::numeric,0)=0 then 'zero_event'
       when m.payload->>'transaction_type'='PAYMENT' then 'payment'
       else 'debt' end
     and s.source_id=m.source_id
    where m.sync_source_id=r.id
      and (s.source_id is null or (s.payload_hash is not null and s.payload_hash is distinct from m.payload_hash));

    select count(*) into v_cursor
    from private.daftar_cursor_anomalies
    where sync_source_id=r.id and resolved_at is null;

    v_status := case when v_contacts=0 and v_transactions=0 and v_cursor=0 then 'healthy' else 'critical' end;
    v_details := jsonb_build_object(
      'contact_hash_or_mapping_mismatches',v_contacts,
      'transaction_hash_or_mapping_mismatches',v_transactions,
      'open_cursor_anomalies',v_cursor
    );

    insert into private.daftar_deep_integrity_state(
      sync_source_id,checked_at,contact_hash_or_mapping_mismatches,
      transaction_hash_or_mapping_mismatches,open_cursor_anomalies,status,details
    ) values (r.id,now(),v_contacts,v_transactions,v_cursor,v_status,v_details)
    on conflict (sync_source_id) do update
    set checked_at=excluded.checked_at,
        contact_hash_or_mapping_mismatches=excluded.contact_hash_or_mapping_mismatches,
        transaction_hash_or_mapping_mismatches=excluded.transaction_hash_or_mapping_mismatches,
        open_cursor_anomalies=excluded.open_cursor_anomalies,
        status=excluded.status,
        details=excluded.details;

    perform private.set_daftar_integrity_dead_letter(r.id,'contact_hash_parity_mismatch',v_contacts>0,jsonb_build_object('count',v_contacts));
    perform private.set_daftar_integrity_dead_letter(r.id,'transaction_hash_parity_mismatch',v_transactions>0,jsonb_build_object('count',v_transactions));
    perform private.set_daftar_integrity_dead_letter(r.id,'cursor_regression_detected',v_cursor>0,jsonb_build_object('count',v_cursor));

    if v_status='healthy' then v_healthy:=v_healthy+1; else v_critical:=v_critical+1; end if;
  end loop;

  return jsonb_build_object('healthy',v_healthy,'critical',v_critical);
end;
$$;
revoke all on function private.run_daftar_deep_integrity_check() from public, anon, authenticated;

alter table private.daftar_sync_health_samples
  add column if not exists oldest_waiting_age_seconds integer,
  add column if not exists cursor_anomalies integer not null default 0,
  add column if not exists deep_integrity_status text;

create or replace function private.check_daftar_sync_integrity(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.daftar_sync_sources%rowtype;
  v_heartbeat_age integer;
  v_success_age integer;
  v_queue integer := 0;
  v_stale integer := 0;
  v_blocked integer := 0;
  v_failed integer := 0;
  v_dead integer := 0;
  v_cursor integer := 0;
  v_oldest_wait integer := 0;
  v_deep_status text;
  v_deep_checked timestamptz;
  v_status text := 'healthy';
  v_result jsonb;
begin
  select * into s from public.daftar_sync_sources where id=p_source_id;
  if s.id is null then raise exception 'sync_source_not_found'; end if;

  v_heartbeat_age := case when s.last_heartbeat_at is null then null else greatest(0,extract(epoch from (now()-s.last_heartbeat_at))::int) end;
  v_success_age := case when s.last_success_at is null then null else greatest(0,extract(epoch from (now()-s.last_success_at))::int) end;

  select
    count(*) filter (where status in ('pending','failed') and next_attempt_at <= now()),
    count(*) filter (where status='processing' and updated_at < now()-interval '2 minutes'),
    count(*) filter (where status='blocked'),
    count(*) filter (where status='failed'),
    coalesce(extract(epoch from (now()-min(created_at) filter (where status in ('pending','processing','failed','blocked'))))::int,0)
  into v_queue,v_stale,v_blocked,v_failed,v_oldest_wait
  from public.daftar_outbound_events where sync_source_id=s.id;

  select count(*) into v_dead from public.daftar_sync_dead_letters where sync_source_id=s.id and resolved_at is null;
  select count(*) into v_cursor from private.daftar_cursor_anomalies where sync_source_id=s.id and resolved_at is null;
  select status,checked_at into v_deep_status,v_deep_checked from private.daftar_deep_integrity_state where sync_source_id=s.id;

  if s.last_status='failed'
     or s.health_status in ('circuit_open','disabled')
     or s.outage_status='confirmed'
     or coalesce(v_success_age,2147483647) > 300
     or coalesce(s.reconciliation_missing_contacts,0) > 0
     or coalesce(s.reconciliation_missing_transactions,0) > 0
     or v_stale > 0 or v_blocked > 0 or v_dead > 0 or v_cursor > 0
     or v_oldest_wait > 300
     or v_deep_status='critical'
     or v_deep_checked is null or v_deep_checked < now()-interval '10 minutes' then
    v_status := 'critical';
  elsif s.health_status='degraded'
     or s.outage_status='suspected'
     or coalesce(v_success_age,2147483647) > 90
     or v_failed > 0 or v_queue > 25 or v_oldest_wait > 60 then
    v_status := 'degraded';
  end if;

  v_result := jsonb_build_object(
    'status',v_status,
    'heartbeat_age_seconds',v_heartbeat_age,
    'success_age_seconds',v_success_age,
    'queue_waiting',v_queue,
    'oldest_waiting_age_seconds',v_oldest_wait,
    'stale_processing',v_stale,
    'blocked_events',v_blocked,
    'failed_events',v_failed,
    'open_dead_letters',v_dead,
    'cursor_anomalies',v_cursor,
    'deep_integrity_status',coalesce(v_deep_status,'missing'),
    'deep_integrity_checked_at',v_deep_checked,
    'missing_contacts',coalesce(s.reconciliation_missing_contacts,0),
    'missing_transactions',coalesce(s.reconciliation_missing_transactions,0),
    'source_health',s.health_status,
    'outage_status',s.outage_status,
    'last_status',s.last_status
  );

  insert into private.daftar_sync_health_samples(
    sync_source_id,status,heartbeat_age_seconds,success_age_seconds,
    queue_waiting,oldest_waiting_age_seconds,stale_processing,blocked_events,failed_events,open_dead_letters,
    cursor_anomalies,deep_integrity_status,missing_contacts,missing_transactions,details
  ) values (
    s.id,v_status,v_heartbeat_age,v_success_age,v_queue,v_oldest_wait,v_stale,v_blocked,v_failed,v_dead,
    v_cursor,coalesce(v_deep_status,'missing'),coalesce(s.reconciliation_missing_contacts,0),
    coalesce(s.reconciliation_missing_transactions,0),v_result
  );

  delete from private.daftar_sync_health_samples where observed_at < now()-interval '30 days';
  return v_result;
end;
$$;
revoke all on function private.check_daftar_sync_integrity(uuid) from public, anon, authenticated;

do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname='daftar-sync-deep-integrity' limit 1;
  if v_job_id is null then
    perform cron.schedule('daftar-sync-deep-integrity','*/5 * * * *','select private.run_daftar_deep_integrity_check();');
  else
    perform cron.alter_job(job_id=>v_job_id,schedule=>'*/5 * * * *',command=>'select private.run_daftar_deep_integrity_check();',active=>true);
  end if;
end;
$$;