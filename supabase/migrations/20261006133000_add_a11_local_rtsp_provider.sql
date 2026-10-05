-- Add a direct on-device RTSP provider for the O-KAM/A11 camera.
-- This migration is intentionally non-activating: existing markets keep their
-- current capture_provider until the matching ZHIROX app build is installed.

alter table public.hikvision_market_config
  drop constraint if exists hikvision_market_config_capture_provider_check;

alter table public.hikvision_market_config
  add constraint hikvision_market_config_capture_provider_check
  check (capture_provider = any (array[
    'hikconnect_cloud'::text,
    'local_gateway'::text,
    'a11_local_rtsp'::text
  ]));

alter table private.hikvision_video_jobs
  drop constraint if exists hikvision_video_jobs_provider_check;

alter table private.hikvision_video_jobs
  add constraint hikvision_video_jobs_provider_check
  check (provider = any (array[
    'hikconnect_cloud'::text,
    'local_gateway'::text,
    'a11_local_rtsp'::text
  ]));

create or replace function private.hikvision_enqueue_transaction_video()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_source_type text;
  v_source_id uuid;
  v_transaction_at timestamptz;
  v_cfg public.hikvision_market_config%rowtype;
  v_job_id uuid;
begin
  if tg_table_name = 'debts' then
    v_source_type := 'debt';
    v_source_id := new.id;
    v_transaction_at := coalesce(new.created_at, now());
    select case when p.role = 'admin' then p.id else p.admin_id end
      into v_market_id
      from public.profiles p
      where p.id = new.customer_id;
  elsif tg_table_name = 'payments' then
    v_source_type := 'payment';
    v_source_id := new.id;
    v_transaction_at := coalesce(new.created_at, now());
    select case when p.role = 'admin' then p.id else p.admin_id end
      into v_market_id
      from public.debts d
      join public.profiles p on p.id = d.customer_id
      where d.id = new.debt_id;
  elsif tg_table_name = 'customer_general_payments' then
    v_source_type := 'general_payment';
    v_source_id := new.id;
    v_transaction_at := coalesce(new.created_at, now());
    v_market_id := new.admin_id;
  else
    return new;
  end if;

  if v_market_id is null then return new; end if;

  select * into v_cfg
  from public.hikvision_market_config c
  where c.market_id = v_market_id
    and c.enabled = true
    and c.auto_capture = true;

  if not found then return new; end if;

  insert into private.hikvision_video_jobs (
    market_id, source_type, source_id, transaction_at, channel_id,
    clip_start_at, clip_end_at, status, provider
  ) values (
    v_market_id, v_source_type, v_source_id, v_transaction_at,
    v_cfg.cashier_channel_id,
    v_transaction_at - interval '15 seconds',
    v_transaction_at + interval '15 seconds',
    'queued', v_cfg.capture_provider
  )
  on conflict (source_type, source_id) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    insert into public.transaction_video_evidence (
      market_id, job_id, source_type, source_id, channel_id, transaction_at,
      clip_start_at, clip_end_at, status
    ) values (
      v_market_id, v_job_id, v_source_type, v_source_id,
      v_cfg.cashier_channel_id, v_transaction_at,
      v_transaction_at - interval '15 seconds',
      v_transaction_at + interval '15 seconds', 'queued'
    ) on conflict (source_type, source_id) do nothing;
  end if;

  return new;
end;
$$;

-- Local Windows gateways must never claim a job owned by the direct A11
-- provider. Existing local_gateway jobs continue to behave exactly as before.
create or replace function private.claim_hikvision_video_job_v2(p_gateway_id uuid)
returns table(
  job_id uuid,
  market_id uuid,
  source_type text,
  source_id uuid,
  transaction_at timestamptz,
  channel_id integer,
  clip_start_at timestamptz,
  clip_end_at timestamptz,
  attempt_count integer,
  attempt_generation bigint,
  attempt_token uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_job_id uuid;
  v_token uuid := gen_random_uuid();
begin
  select g.market_id into v_market_id
  from private.hikvision_gateways g
  where g.id = p_gateway_id and g.active = true;
  if v_market_id is null then return; end if;

  perform private.recover_stale_hikvision_video_jobs(v_market_id);

  if exists (
    select 1 from private.hikvision_video_jobs j
    where j.gateway_id = p_gateway_id
      and j.provider = 'local_gateway'
      and j.status in ('processing','uploading')
      and coalesce(j.lease_until, now() + interval '1 second') > now()
  ) then
    return;
  end if;

  select j.id into v_job_id
  from private.hikvision_video_jobs j
  where j.market_id = v_market_id
    and j.provider = 'local_gateway'
    and j.status in ('queued','retrying')
    and j.run_after <= now()
    and j.clip_end_at + interval '3 seconds' <= now()
    and (j.lease_until is null or j.lease_until < now())
  order by j.transaction_at
  for update skip locked
  limit 1;
  if v_job_id is null then return; end if;

  update private.hikvision_video_jobs j
  set status = 'processing',
      gateway_id = p_gateway_id,
      attempt_count = j.attempt_count + 1,
      attempt_generation = j.attempt_generation + 1,
      active_attempt_token = v_token,
      attempt_started_at = now(),
      last_attempt_heartbeat_at = now(),
      lease_until = now() + interval '3 minutes',
      last_error = null,
      updated_at = now()
  where j.id = v_job_id;

  update public.transaction_video_evidence e
  set status = 'processing', updated_at = now()
  where e.job_id = v_job_id;

  return query
  select j.id, j.market_id, j.source_type, j.source_id, j.transaction_at,
         j.channel_id, j.clip_start_at, j.clip_end_at, j.attempt_count,
         j.attempt_generation, j.active_attempt_token
  from private.hikvision_video_jobs j
  where j.id = v_job_id;
end;
$$;

-- Authenticated market staff may upload a unique, tenant-scoped MP4 produced
-- by the on-device A11 recorder. No overwrite policy is granted.
drop policy if exists transaction_camera_clips_insert_staff on storage.objects;
create policy transaction_camera_clips_insert_staff
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'transaction-camera-clips'
  and private.current_role() = any (array['admin'::text, 'employee'::text])
  and (storage.foldername(name))[1] = private.current_admin_id()::text
);

drop policy if exists transaction_camera_clips_select_staff on storage.objects;
create policy transaction_camera_clips_select_staff
on storage.objects for select
to authenticated
using (
  bucket_id = 'transaction-camera-clips'
  and private.current_role() = any (array['admin'::text, 'employee'::text])
  and (storage.foldername(name))[1] = private.current_admin_id()::text
);

-- Privileged finalizer lives in the non-exposed private schema and performs
-- an explicit auth + tenant + source check before changing a private job.
create or replace function private.a11_complete_video(
  p_source_type text,
  p_source_id uuid,
  p_object_path text,
  p_byte_size bigint,
  p_duration_seconds integer,
  p_content_sha256 text,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_market_id uuid;
  v_source_market_id uuid;
  v_role text;
  v_job_id uuid;
begin
  if v_user_id is null then return false; end if;

  v_market_id := private.current_admin_id();
  v_role := private.current_role();
  if v_market_id is null or v_role not in ('admin','employee') then
    return false;
  end if;

  if p_source_type = 'debt' then
    select private.profile_tenant_id(d.customer_id)
      into v_source_market_id
      from public.debts d
      where d.id = p_source_id and d.is_deleted = false;
  elsif p_source_type = 'payment' then
    select private.profile_tenant_id(d.customer_id)
      into v_source_market_id
      from public.payments p
      join public.debts d on d.id = p.debt_id
      where p.id = p_source_id and d.is_deleted = false;
  elsif p_source_type = 'general_payment' then
    select gp.admin_id
      into v_source_market_id
      from public.customer_general_payments gp
      where gp.id = p_source_id;
  else
    return false;
  end if;

  if v_source_market_id is distinct from v_market_id then return false; end if;
  if p_object_path is null or split_part(p_object_path, '/', 1) <> v_market_id::text then
    return false;
  end if;
  if p_duration_seconds is null or p_duration_seconds < 28 or p_duration_seconds > 32 then
    return false;
  end if;
  if p_byte_size is null or p_byte_size < 20000 then return false; end if;
  if coalesce((p_playback_metadata->>'exact_trim')::boolean, false) is not true then
    return false;
  end if;

  select j.id into v_job_id
  from private.hikvision_video_jobs j
  where j.market_id = v_market_id
    and j.source_type = p_source_type
    and j.source_id = p_source_id
    and j.provider = 'a11_local_rtsp'
  for update;

  if v_job_id is null then return false; end if;

  update private.hikvision_video_jobs j
  set status = 'ready',
      completed_at = now(),
      lease_until = null,
      gateway_id = null,
      active_attempt_token = null,
      last_error = null,
      playback_metadata = coalesce(p_playback_metadata, '{}'::jsonb)
        || jsonb_build_object('provider', 'a11_local_rtsp'),
      updated_at = now()
  where j.id = v_job_id;

  update public.transaction_video_evidence e
  set status = 'ready',
      object_path = p_object_path,
      content_sha256 = nullif(p_content_sha256, ''),
      byte_size = p_byte_size,
      duration_seconds = p_duration_seconds,
      playback_metadata = coalesce(p_playback_metadata, '{}'::jsonb)
        || jsonb_build_object('provider', 'a11_local_rtsp'),
      captured_at = now(),
      updated_at = now()
  where e.job_id = v_job_id;

  return found;
end;
$$;

revoke all on function private.a11_complete_video(text,uuid,text,bigint,integer,text,jsonb) from public;
grant usage on schema private to authenticated;
grant execute on function private.a11_complete_video(text,uuid,text,bigint,integer,text,jsonb) to authenticated;

create or replace function public.a11_video_complete_service(
  p_source_type text,
  p_source_id uuid,
  p_object_path text,
  p_byte_size bigint,
  p_duration_seconds integer,
  p_content_sha256 text default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.a11_complete_video(
    p_source_type,
    p_source_id,
    p_object_path,
    p_byte_size,
    p_duration_seconds,
    p_content_sha256,
    p_playback_metadata
  );
$$;

revoke all on function public.a11_video_complete_service(text,uuid,text,bigint,integer,text,jsonb) from public, anon;
grant execute on function public.a11_video_complete_service(text,uuid,text,bigint,integer,text,jsonb) to authenticated;
