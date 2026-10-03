-- Cloud-first Hik-Connect for Teams provider. Local gateway remains as fallback.
-- AK/SK and cached access tokens are stored only in Supabase Vault.

alter table public.hikvision_market_config
  add column if not exists capture_provider text not null default 'local_gateway',
  add column if not exists hikconnect_camera_id text not null default '',
  add column if not exists hikconnect_camera_name text not null default '',
  add column if not exists hikconnect_device_serial text not null default '',
  add column if not exists hikconnect_server_address text not null default '';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hikvision_market_config_capture_provider_check'
      and conrelid = 'public.hikvision_market_config'::regclass
  ) then
    alter table public.hikvision_market_config
      add constraint hikvision_market_config_capture_provider_check
      check (capture_provider in ('hikconnect_cloud','local_gateway'));
  end if;
end;
$$;

alter table private.hikvision_video_jobs
  add column if not exists provider text not null default 'local_gateway',
  add column if not exists cloud_task_id text,
  add column if not exists cloud_last_polled_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'hikvision_video_jobs_provider_check'
      and conrelid = 'private.hikvision_video_jobs'::regclass
  ) then
    alter table private.hikvision_video_jobs
      add constraint hikvision_video_jobs_provider_check
      check (provider in ('hikconnect_cloud','local_gateway'));
  end if;
end;
$$;

create index if not exists hikvision_video_jobs_cloud_claim_idx
  on private.hikvision_video_jobs(provider, status, run_after, created_at)
  where provider = 'hikconnect_cloud' and status in ('queued','retrying','processing');

create table if not exists private.hikvision_cloud_credentials (
  market_id uuid primary key references public.profiles(id) on delete cascade,
  server_address text not null,
  app_key_secret_id uuid not null,
  secret_key_secret_id uuid not null,
  access_token_secret_id uuid,
  token_expires_at timestamptz,
  area_domain text,
  last_test_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table private.hikvision_cloud_credentials enable row level security;

create table if not exists private.hikvision_cloud_worker_runtime (
  singleton boolean primary key default true check (singleton),
  worker_secret_id uuid not null,
  worker_secret_sha256 text not null check (worker_secret_sha256 ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table private.hikvision_cloud_worker_runtime enable row level security;

-- Stamp the provider at enqueue time without changing the existing transaction trigger.
create or replace function private.hikvision_video_job_provider_stamp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select coalesce(c.capture_provider, 'local_gateway')
    into new.provider
  from public.hikvision_market_config c
  where c.market_id = new.market_id;
  new.provider := coalesce(new.provider, 'local_gateway');
  return new;
end;
$$;

revoke all on function private.hikvision_video_job_provider_stamp() from public,anon,authenticated;
drop trigger if exists trg_hikvision_video_job_provider_stamp on private.hikvision_video_jobs;
create trigger trg_hikvision_video_job_provider_stamp
before insert on private.hikvision_video_jobs
for each row execute function private.hikvision_video_job_provider_stamp();

create or replace function public.hikvision_cloud_credentials_set_service(
  p_market_id uuid,
  p_server_address text,
  p_app_key text,
  p_secret_key text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ak uuid;
  v_sk uuid;
  v_server text := regexp_replace(trim(coalesce(p_server_address,'')), '/+$', '');
begin
  if v_server !~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$' then
    raise exception 'invalid_server_address';
  end if;
  if length(trim(coalesce(p_app_key,''))) < 8 or length(trim(coalesce(p_app_key,''))) > 128 then
    raise exception 'invalid_app_key';
  end if;
  if length(trim(coalesce(p_secret_key,''))) < 8 or length(trim(coalesce(p_secret_key,''))) > 128 then
    raise exception 'invalid_secret_key';
  end if;

  select c.app_key_secret_id, c.secret_key_secret_id
    into v_ak, v_sk
  from private.hikvision_cloud_credentials c
  where c.market_id = p_market_id
  for update;

  if v_ak is null then
    v_ak := vault.create_secret(trim(p_app_key), 'zhirox_hikconnect_ak_' || p_market_id::text, 'Hik-Connect Team AppKey');
  else
    perform vault.update_secret(v_ak, trim(p_app_key));
  end if;

  if v_sk is null then
    v_sk := vault.create_secret(trim(p_secret_key), 'zhirox_hikconnect_sk_' || p_market_id::text, 'Hik-Connect Team SecretKey');
  else
    perform vault.update_secret(v_sk, trim(p_secret_key));
  end if;

  insert into private.hikvision_cloud_credentials(
    market_id, server_address, app_key_secret_id, secret_key_secret_id,
    access_token_secret_id, token_expires_at, area_domain, last_error, updated_at
  ) values (
    p_market_id, v_server, v_ak, v_sk,
    null, null, null, null, now()
  )
  on conflict (market_id) do update
    set server_address = excluded.server_address,
        app_key_secret_id = excluded.app_key_secret_id,
        secret_key_secret_id = excluded.secret_key_secret_id,
        access_token_secret_id = null,
        token_expires_at = null,
        area_domain = null,
        last_error = null,
        updated_at = now();

  update public.hikvision_market_config
  set hikconnect_server_address = v_server, updated_at = now()
  where market_id = p_market_id;
  return true;
end;
$$;

create or replace function public.hikvision_cloud_credentials_get_service(p_market_id uuid)
returns table(
  server_address text,
  app_key text,
  secret_key text,
  access_token text,
  token_expires_at timestamptz,
  area_domain text
)
language sql
security definer
set search_path = ''
as $$
  select c.server_address,
         ak.decrypted_secret,
         sk.decrypted_secret,
         tok.decrypted_secret,
         c.token_expires_at,
         c.area_domain
  from private.hikvision_cloud_credentials c
  join vault.decrypted_secrets ak on ak.id = c.app_key_secret_id
  join vault.decrypted_secrets sk on sk.id = c.secret_key_secret_id
  left join vault.decrypted_secrets tok on tok.id = c.access_token_secret_id
  where c.market_id = p_market_id;
$$;

create or replace function public.hikvision_cloud_token_cache_service(
  p_market_id uuid,
  p_access_token text,
  p_expires_at timestamptz,
  p_area_domain text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token_id uuid;
begin
  select access_token_secret_id into v_token_id
  from private.hikvision_cloud_credentials
  where market_id = p_market_id
  for update;
  if not found then return false; end if;

  if v_token_id is null then
    v_token_id := vault.create_secret(p_access_token, 'zhirox_hikconnect_token_' || p_market_id::text, 'Cached Hik-Connect access token');
  else
    perform vault.update_secret(v_token_id, p_access_token);
  end if;

  update private.hikvision_cloud_credentials
  set access_token_secret_id = v_token_id,
      token_expires_at = p_expires_at,
      area_domain = regexp_replace(trim(coalesce(p_area_domain,'')), '/+$', ''),
      last_test_at = now(), last_error = null, updated_at = now()
  where market_id = p_market_id;
  return true;
end;
$$;

create or replace function public.hikvision_cloud_mark_error_service(p_market_id uuid, p_error text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update private.hikvision_cloud_credentials
  set last_test_at = now(), last_error = left(coalesce(p_error,'unknown_error'),500), updated_at = now()
  where market_id = p_market_id
  returning true;
$$;

create or replace function public.hikvision_cloud_status_service(p_market_id uuid)
returns table(
  configured boolean,
  server_address text,
  area_domain text,
  token_expires_at timestamptz,
  last_test_at timestamptz,
  last_error text
)
language sql
security definer
set search_path = ''
as $$
  select true, c.server_address, c.area_domain, c.token_expires_at, c.last_test_at, c.last_error
  from private.hikvision_cloud_credentials c
  where c.market_id = p_market_id;
$$;

create or replace function public.hikvision_cloud_activate_camera_service(
  p_market_id uuid,
  p_camera_id text,
  p_camera_name text,
  p_device_serial text,
  p_channel_no integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if length(trim(coalesce(p_camera_id,''))) < 8 or length(trim(coalesce(p_camera_id,''))) > 128 then
    raise exception 'invalid_camera_id';
  end if;
  if p_channel_no < 1 or p_channel_no > 256 then
    raise exception 'invalid_channel';
  end if;
  if not exists (select 1 from private.hikvision_cloud_credentials where market_id = p_market_id) then
    raise exception 'cloud_credentials_missing';
  end if;

  update public.hikvision_market_config
  set capture_provider = 'hikconnect_cloud',
      hikconnect_camera_id = trim(p_camera_id),
      hikconnect_camera_name = left(coalesce(p_camera_name,''),120),
      hikconnect_device_serial = left(coalesce(p_device_serial,''),64),
      cashier_channel_id = p_channel_no,
      enabled = true,
      auto_capture = true,
      updated_at = now()
  where market_id = p_market_id;

  update private.hikvision_video_jobs
  set provider = 'hikconnect_cloud',
      gateway_id = null,
      active_attempt_token = null,
      lease_until = null,
      run_after = now(),
      updated_at = now()
  where market_id = p_market_id
    and status in ('queued','retrying');
  return found;
end;
$$;

create or replace function public.hikvision_use_local_gateway_service(p_market_id uuid)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update public.hikvision_market_config
  set capture_provider = 'local_gateway', updated_at = now()
  where market_id = p_market_id
  returning true;
$$;

create or replace function private.claim_hikvision_cloud_job()
returns table(
  job_id uuid,
  market_id uuid,
  source_type text,
  source_id uuid,
  clip_start_at timestamptz,
  clip_end_at timestamptz,
  camera_id text,
  device_serial text,
  channel_id integer,
  stage text,
  cloud_task_id text,
  attempt_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job_id uuid;
  v_token uuid := gen_random_uuid();
  v_stage text;
begin
  select j.id into v_job_id
  from private.hikvision_video_jobs j
  join public.hikvision_market_config c on c.market_id = j.market_id
  join private.hikvision_cloud_credentials h on h.market_id = j.market_id
  where j.provider = 'hikconnect_cloud'
    and c.capture_provider = 'hikconnect_cloud'
    and c.enabled = true and c.auto_capture = true
    and c.hikconnect_camera_id <> ''
    and j.run_after <= now()
    and (j.lease_until is null or j.lease_until < now())
    and j.clip_end_at + interval '3 seconds' <= now()
    and (
      j.status in ('queued','retrying')
      or (j.status = 'processing' and j.cloud_task_id is not null)
    )
  order by j.transaction_at
  for update skip locked
  limit 1;

  if v_job_id is null then return; end if;

  select case when j.cloud_task_id is null then 'save' else 'poll' end
    into v_stage
  from private.hikvision_video_jobs j where j.id = v_job_id;

  update private.hikvision_video_jobs j
  set status = 'processing',
      attempt_count = case when v_stage = 'save' then j.attempt_count + 1 else j.attempt_count end,
      attempt_generation = j.attempt_generation + 1,
      active_attempt_token = v_token,
      attempt_started_at = now(),
      last_attempt_heartbeat_at = now(),
      lease_until = now() + interval '2 minutes',
      gateway_id = null,
      last_error = null,
      updated_at = now()
  where j.id = v_job_id;

  update public.transaction_video_evidence e
  set status = 'processing', updated_at = now()
  where e.job_id = v_job_id;

  return query
  select j.id, j.market_id, j.source_type, j.source_id,
         j.clip_start_at, j.clip_end_at,
         c.hikconnect_camera_id, c.hikconnect_device_serial,
         j.channel_id, v_stage, j.cloud_task_id, j.active_attempt_token
  from private.hikvision_video_jobs j
  join public.hikvision_market_config c on c.market_id = j.market_id
  where j.id = v_job_id;
end;
$$;

create or replace function public.hikvision_cloud_claim_service()
returns table(
  job_id uuid,
  market_id uuid,
  source_type text,
  source_id uuid,
  clip_start_at timestamptz,
  clip_end_at timestamptz,
  camera_id text,
  device_serial text,
  channel_id integer,
  stage text,
  cloud_task_id text,
  attempt_token uuid
)
language sql
security definer
set search_path = ''
as $$ select * from private.claim_hikvision_cloud_job(); $$;

create or replace function public.hikvision_cloud_task_started_service(
  p_job_id uuid, p_attempt_token uuid, p_task_id text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set cloud_task_id = left(p_task_id,500),
      playback_metadata = coalesce(j.playback_metadata,'{}'::jsonb) || jsonb_build_object('provider','hikconnect_cloud','cloud_task_id',left(p_task_id,500)),
      run_after = now() + interval '15 seconds',
      lease_until = null,
      active_attempt_token = null,
      updated_at = now()
  where j.id = p_job_id
    and j.provider = 'hikconnect_cloud'
    and j.active_attempt_token = p_attempt_token
    and j.status = 'processing';
  return found;
end;
$$;

create or replace function public.hikvision_cloud_wait_service(
  p_job_id uuid, p_attempt_token uuid, p_seconds integer default 20
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set cloud_last_polled_at = now(),
      run_after = now() + make_interval(secs => greatest(10,least(120,coalesce(p_seconds,20)))),
      lease_until = null,
      active_attempt_token = null,
      updated_at = now()
  where j.id = p_job_id
    and j.provider = 'hikconnect_cloud'
    and j.active_attempt_token = p_attempt_token
    and j.status = 'processing';
  return found;
end;
$$;

create or replace function public.hikvision_cloud_complete_service(
  p_job_id uuid,
  p_attempt_token uuid,
  p_object_path text,
  p_content_sha256 text,
  p_byte_size bigint,
  p_duration_seconds integer,
  p_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set status='ready', lease_until=null, active_attempt_token=null,
      last_attempt_heartbeat_at=now(), completed_at=now(), updated_at=now(),
      playback_metadata=coalesce(j.playback_metadata,'{}'::jsonb) || coalesce(p_metadata,'{}'::jsonb),
      last_error=null
  where j.id=p_job_id
    and j.provider='hikconnect_cloud'
    and j.active_attempt_token=p_attempt_token
    and j.status='processing';
  if not found then return false; end if;

  update public.transaction_video_evidence e
  set status='ready', object_path=p_object_path,
      content_sha256=p_content_sha256, byte_size=p_byte_size,
      duration_seconds=p_duration_seconds,
      playback_metadata=coalesce(e.playback_metadata,'{}'::jsonb) || coalesce(p_metadata,'{}'::jsonb),
      captured_at=now(), updated_at=now()
  where e.job_id=p_job_id;
  return true;
end;
$$;

create or replace function public.hikvision_cloud_fail_service(
  p_job_id uuid,
  p_attempt_token uuid,
  p_error text,
  p_missing boolean default false
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_attempt integer;
  v_max integer;
  v_status text;
begin
  select j.attempt_count,j.max_attempts into v_attempt,v_max
  from private.hikvision_video_jobs j
  where j.id=p_job_id
    and j.provider='hikconnect_cloud'
    and j.active_attempt_token=p_attempt_token
    and j.status='processing'
  for update;
  if not found then return false; end if;

  v_status := case
    when p_missing then 'missing'
    when v_attempt >= v_max then 'failed'
    else 'retrying'
  end;

  update private.hikvision_video_jobs j
  set status=v_status,
      cloud_task_id=case when v_status='retrying' then null else j.cloud_task_id end,
      active_attempt_token=null,
      lease_until=null,
      run_after=case when v_status='retrying'
        then now()+make_interval(secs=>least(300,15*(2^greatest(0,v_attempt-1))::int))
        else j.run_after end,
      last_error=left(coalesce(p_error,'cloud_failed'),1000),
      completed_at=case when v_status in ('missing','failed') then now() else null end,
      updated_at=now()
  where j.id=p_job_id;

  update public.transaction_video_evidence e
  set status=case when v_status='retrying' then 'queued' else v_status end,
      updated_at=now()
  where e.job_id=p_job_id;
  return true;
end;
$$;

-- One private cron secret; only its SHA-256 is exposed to the worker auth RPC.
do $$
declare
  v_secret text;
  v_secret_id uuid;
begin
  if not exists (select 1 from private.hikvision_cloud_worker_runtime where singleton=true) then
    v_secret := encode(gen_random_bytes(32),'hex');
    v_secret_id := vault.create_secret(v_secret, 'zhirox_hikvision_cloud_worker', 'Internal Hik-Connect cloud worker secret');
    insert into private.hikvision_cloud_worker_runtime(singleton,worker_secret_id,worker_secret_sha256)
    values (true,v_secret_id,encode(digest(v_secret,'sha256'),'hex'));
  end if;
end;
$$;

create or replace function public.hikvision_cloud_worker_auth_service(p_token_sha256 text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists(
    select 1 from private.hikvision_cloud_worker_runtime r
    where r.singleton=true and r.worker_secret_sha256=p_token_sha256
  );
$$;

create or replace function private.invoke_hikvision_cloud_worker_service()
returns bigint
language plpgsql
security definer
set search_path = 'pg_catalog','public'
as $$
declare
  v_secret text;
  v_request_id bigint;
begin
  select s.decrypted_secret into v_secret
  from private.hikvision_cloud_worker_runtime r
  join vault.decrypted_secrets s on s.id=r.worker_secret_id
  where r.singleton=true;
  if v_secret is null then raise exception 'hikvision_cloud_worker_secret_missing'; end if;

  select net.http_post(
    url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/hikvision-cloud-worker',
    body := '{}'::jsonb,
    params := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-zhirox-hikvision-cloud-worker',v_secret),
    timeout_milliseconds := 10000
  ) into v_request_id;
  return v_request_id;
end;
$$;

-- Service wrappers are internal-only.
revoke all on function public.hikvision_cloud_credentials_set_service(uuid,text,text,text) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_credentials_get_service(uuid) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_token_cache_service(uuid,text,timestamptz,text) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_mark_error_service(uuid,text) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_status_service(uuid) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_activate_camera_service(uuid,text,text,text,integer) from public,anon,authenticated;
revoke all on function public.hikvision_use_local_gateway_service(uuid) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_claim_service() from public,anon,authenticated;
revoke all on function public.hikvision_cloud_task_started_service(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_wait_service(uuid,uuid,integer) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_complete_service(uuid,uuid,text,text,bigint,integer,jsonb) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_fail_service(uuid,uuid,text,boolean) from public,anon,authenticated;
revoke all on function public.hikvision_cloud_worker_auth_service(text) from public,anon,authenticated;
revoke all on function private.claim_hikvision_cloud_job() from public,anon,authenticated;
revoke all on function private.invoke_hikvision_cloud_worker_service() from public,anon,authenticated;

grant execute on function public.hikvision_cloud_credentials_set_service(uuid,text,text,text) to service_role;
grant execute on function public.hikvision_cloud_credentials_get_service(uuid) to service_role;
grant execute on function public.hikvision_cloud_token_cache_service(uuid,text,timestamptz,text) to service_role;
grant execute on function public.hikvision_cloud_mark_error_service(uuid,text) to service_role;
grant execute on function public.hikvision_cloud_status_service(uuid) to service_role;
grant execute on function public.hikvision_cloud_activate_camera_service(uuid,text,text,text,integer) to service_role;
grant execute on function public.hikvision_use_local_gateway_service(uuid) to service_role;
grant execute on function public.hikvision_cloud_claim_service() to service_role;
grant execute on function public.hikvision_cloud_task_started_service(uuid,uuid,text) to service_role;
grant execute on function public.hikvision_cloud_wait_service(uuid,uuid,integer) to service_role;
grant execute on function public.hikvision_cloud_complete_service(uuid,uuid,text,text,bigint,integer,jsonb) to service_role;
grant execute on function public.hikvision_cloud_fail_service(uuid,uuid,text,boolean) to service_role;
grant execute on function public.hikvision_cloud_worker_auth_service(text) to service_role;
grant execute on function private.invoke_hikvision_cloud_worker_service() to service_role;

-- Keep exactly one cloud worker schedule.
do $$
declare v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job where jobname='zhirox-hikvision-cloud-worker' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule('zhirox-hikvision-cloud-worker','* * * * *','select private.invoke_hikvision_cloud_worker_service();');
end;
$$;
