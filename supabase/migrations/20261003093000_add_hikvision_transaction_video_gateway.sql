-- ZHIROX Hikvision transaction-video gateway.
-- NVR credentials intentionally never live in Supabase; only a gateway token hash is stored.

create table if not exists public.hikvision_market_config (
  market_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  auto_capture boolean not null default true,
  nvr_label text not null default 'Hikvision NVR',
  nvr_host text not null default '',
  nvr_model text not null default '',
  nvr_firmware text not null default '',
  cashier_channel_id integer not null default 1 check (cashier_channel_id between 1 and 256),
  pre_seconds integer not null default 15 check (pre_seconds between 0 and 300),
  post_seconds integer not null default 30 check (post_seconds between 1 and 600),
  timezone text not null default 'Asia/Baghdad',
  retention_days integer not null default 90 check (retention_days between 1 and 3650),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.hikvision_market_config enable row level security;

drop policy if exists hikvision_market_config_admin_read on public.hikvision_market_config;
create policy hikvision_market_config_admin_read
on public.hikvision_market_config for select
to authenticated
using (
  market_id = auth.uid()
  or exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.active = true
      and p.approved = true
      and p.admin_id = hikvision_market_config.market_id
      and p.role = 'employee'
      and (p.can_view_transactions = true or p.can_manage_settings = true)
  )
);

drop policy if exists hikvision_market_config_admin_write on public.hikvision_market_config;
create policy hikvision_market_config_admin_write
on public.hikvision_market_config for all
to authenticated
using (
  market_id = auth.uid()
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin' and p.active = true and p.approved = true
  )
)
with check (
  market_id = auth.uid()
  and exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin' and p.active = true and p.approved = true
  )
);

create table if not exists private.hikvision_gateways (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null unique references public.profiles(id) on delete cascade,
  label text not null default 'Market Hikvision Gateway',
  token_sha256 text unique,
  active boolean not null default true,
  gateway_version text not null default '',
  platform text not null default '',
  last_seen_at timestamptz,
  last_ip text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (token_sha256 is null or token_sha256 ~ '^[0-9a-f]{64}$')
);
alter table private.hikvision_gateways enable row level security;

create table if not exists private.hikvision_video_jobs (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null check (source_type in ('debt','payment','general_payment')),
  source_id uuid not null,
  transaction_at timestamptz not null,
  channel_id integer not null check (channel_id between 1 and 256),
  clip_start_at timestamptz not null,
  clip_end_at timestamptz not null,
  status text not null default 'queued' check (status in ('queued','processing','uploading','ready','retrying','missing','failed')),
  gateway_id uuid references private.hikvision_gateways(id) on delete set null,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 8 check (max_attempts between 1 and 30),
  run_after timestamptz not null default now(),
  lease_until timestamptz,
  playback_metadata jsonb not null default '{}'::jsonb,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (source_type, source_id),
  check (clip_end_at > clip_start_at)
);
alter table private.hikvision_video_jobs enable row level security;
create index if not exists hikvision_video_jobs_claim_idx
  on private.hikvision_video_jobs(status, run_after, created_at)
  where status in ('queued','retrying');
create index if not exists hikvision_video_jobs_market_idx
  on private.hikvision_video_jobs(market_id, transaction_at desc);

create table if not exists public.transaction_video_evidence (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  job_id uuid not null unique references private.hikvision_video_jobs(id) on delete cascade,
  source_type text not null check (source_type in ('debt','payment','general_payment')),
  source_id uuid not null,
  channel_id integer not null,
  transaction_at timestamptz not null,
  clip_start_at timestamptz not null,
  clip_end_at timestamptz not null,
  status text not null default 'queued' check (status in ('queued','processing','uploading','ready','missing','failed')),
  object_path text,
  thumbnail_path text,
  content_sha256 text,
  byte_size bigint check (byte_size is null or byte_size >= 0),
  duration_seconds integer check (duration_seconds is null or duration_seconds >= 0),
  playback_metadata jsonb not null default '{}'::jsonb,
  captured_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_type, source_id)
);
alter table public.transaction_video_evidence enable row level security;
create index if not exists transaction_video_evidence_market_idx
  on public.transaction_video_evidence(market_id, transaction_at desc);

drop policy if exists transaction_video_evidence_read on public.transaction_video_evidence;
create policy transaction_video_evidence_read
on public.transaction_video_evidence for select
to authenticated
using (
  market_id = auth.uid()
  or exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.active = true
      and p.approved = true
      and p.admin_id = transaction_video_evidence.market_id
      and p.role = 'employee'
      and (p.can_view_transactions = true or p.can_view_audit_log = true)
  )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'transaction-camera-clips',
  'transaction-camera-clips',
  false,
  104857600,
  array['video/mp4','image/jpeg','image/png']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

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
    v_transaction_at := coalesce(new.custom_date, new.created_at, now());
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
  where c.market_id = v_market_id and c.enabled = true and c.auto_capture = true;

  if not found then return new; end if;

  insert into private.hikvision_video_jobs (
    market_id, source_type, source_id, transaction_at, channel_id,
    clip_start_at, clip_end_at, status
  ) values (
    v_market_id, v_source_type, v_source_id, v_transaction_at, v_cfg.cashier_channel_id,
    v_transaction_at - make_interval(secs => v_cfg.pre_seconds),
    v_transaction_at + make_interval(secs => v_cfg.post_seconds),
    'queued'
  )
  on conflict (source_type, source_id) do nothing
  returning id into v_job_id;

  if v_job_id is not null then
    insert into public.transaction_video_evidence (
      market_id, job_id, source_type, source_id, channel_id, transaction_at,
      clip_start_at, clip_end_at, status
    ) values (
      v_market_id, v_job_id, v_source_type, v_source_id, v_cfg.cashier_channel_id, v_transaction_at,
      v_transaction_at - make_interval(secs => v_cfg.pre_seconds),
      v_transaction_at + make_interval(secs => v_cfg.post_seconds), 'queued'
    ) on conflict (source_type, source_id) do nothing;
  end if;

  return new;
end;
$$;

revoke all on function private.hikvision_enqueue_transaction_video() from public, anon, authenticated;

drop trigger if exists trg_hikvision_debt_video on public.debts;
create trigger trg_hikvision_debt_video
after insert on public.debts
for each row execute function private.hikvision_enqueue_transaction_video();

drop trigger if exists trg_hikvision_payment_video on public.payments;
create trigger trg_hikvision_payment_video
after insert on public.payments
for each row execute function private.hikvision_enqueue_transaction_video();

drop trigger if exists trg_hikvision_general_payment_video on public.customer_general_payments;
create trigger trg_hikvision_general_payment_video
after insert on public.customer_general_payments
for each row execute function private.hikvision_enqueue_transaction_video();

create or replace function private.claim_hikvision_video_job(p_gateway_id uuid)
returns table (
  job_id uuid,
  market_id uuid,
  source_type text,
  source_id uuid,
  transaction_at timestamptz,
  channel_id integer,
  clip_start_at timestamptz,
  clip_end_at timestamptz,
  attempt_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_market_id uuid;
  v_job_id uuid;
begin
  select g.market_id into v_market_id
  from private.hikvision_gateways g
  where g.id = p_gateway_id and g.active = true;
  if v_market_id is null then return; end if;

  select j.id into v_job_id
  from private.hikvision_video_jobs j
  where j.market_id = v_market_id
    and j.status in ('queued','retrying')
    and j.run_after <= now()
    and (j.lease_until is null or j.lease_until < now())
  order by j.transaction_at asc
  for update skip locked
  limit 1;

  if v_job_id is null then return; end if;

  update private.hikvision_video_jobs j
  set status = 'processing', gateway_id = p_gateway_id,
      attempt_count = j.attempt_count + 1,
      lease_until = now() + interval '3 minutes', updated_at = now()
  where j.id = v_job_id;

  update public.transaction_video_evidence e
  set status = 'processing', updated_at = now()
  where e.job_id = v_job_id;

  return query
  select j.id, j.market_id, j.source_type, j.source_id, j.transaction_at,
         j.channel_id, j.clip_start_at, j.clip_end_at, j.attempt_count
  from private.hikvision_video_jobs j
  where j.id = v_job_id;
end;
$$;

create or replace function private.heartbeat_hikvision_gateway(
  p_gateway_id uuid,
  p_gateway_version text default '',
  p_platform text default '',
  p_ip text default null
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update private.hikvision_gateways
  set last_seen_at = now(),
      gateway_version = left(coalesce(p_gateway_version,''),120),
      platform = left(coalesce(p_platform,''),120),
      last_ip = left(coalesce(p_ip,''),120),
      last_error = null,
      updated_at = now()
  where id = p_gateway_id and active = true
  returning true;
$$;

create or replace function private.complete_hikvision_video_job(
  p_gateway_id uuid,
  p_job_id uuid,
  p_object_path text,
  p_thumbnail_path text default null,
  p_content_sha256 text default null,
  p_byte_size bigint default null,
  p_duration_seconds integer default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set status='ready', lease_until=null, completed_at=now(), updated_at=now(),
      playback_metadata=coalesce(p_playback_metadata,'{}'::jsonb), last_error=null
  where j.id=p_job_id
    and j.gateway_id=p_gateway_id
    and j.status in ('processing','uploading');
  if not found then return false; end if;

  update public.transaction_video_evidence e
  set status='ready', object_path=p_object_path, thumbnail_path=p_thumbnail_path,
      content_sha256=p_content_sha256, byte_size=p_byte_size,
      duration_seconds=p_duration_seconds,
      playback_metadata=coalesce(p_playback_metadata,'{}'::jsonb),
      captured_at=now(), updated_at=now()
  where e.job_id=p_job_id;
  return true;
end;
$$;

create or replace function private.fail_hikvision_video_job(
  p_gateway_id uuid,
  p_job_id uuid,
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
  select attempt_count, max_attempts into v_attempt, v_max
  from private.hikvision_video_jobs
  where id=p_job_id and gateway_id=p_gateway_id and status in ('processing','uploading')
  for update;
  if not found then return false; end if;

  if p_missing then
    v_status := 'missing';
  elsif v_attempt >= v_max then
    v_status := 'failed';
  else
    v_status := 'retrying';
  end if;

  update private.hikvision_video_jobs
  set status=v_status,
      run_after = case
        when v_status='retrying'
        then now() + make_interval(secs => least(300, 15 * (2 ^ greatest(0, v_attempt - 1))::int))
        else run_after
      end,
      lease_until=null,
      last_error=left(coalesce(p_error,'unknown_error'),1000),
      updated_at=now(),
      completed_at=case when v_status in ('missing','failed') then now() else null end
  where id=p_job_id;

  update public.transaction_video_evidence
  set status=case when v_status='retrying' then 'queued' else v_status end,
      updated_at=now()
  where job_id=p_job_id;
  return true;
end;
$$;

revoke all on function private.claim_hikvision_video_job(uuid) from public, anon, authenticated;
revoke all on function private.heartbeat_hikvision_gateway(uuid,text,text,text) from public, anon, authenticated;
revoke all on function private.complete_hikvision_video_job(uuid,uuid,text,text,text,bigint,integer,jsonb) from public, anon, authenticated;
revoke all on function private.fail_hikvision_video_job(uuid,uuid,text,boolean) from public, anon, authenticated;
grant execute on function private.claim_hikvision_video_job(uuid) to service_role;
grant execute on function private.heartbeat_hikvision_gateway(uuid,text,text,text) to service_role;
grant execute on function private.complete_hikvision_video_job(uuid,uuid,text,text,text,bigint,integer,jsonb) to service_role;
grant execute on function private.fail_hikvision_video_job(uuid,uuid,text,boolean) to service_role;

create or replace function public.hikvision_gateway_auth_service(p_token_sha256 text)
returns table(gateway_id uuid, market_id uuid, label text)
language sql
security definer
set search_path = ''
as $$
  select g.id, g.market_id, g.label
  from private.hikvision_gateways g
  where g.active = true
    and g.token_sha256 = lower(trim(p_token_sha256))
  limit 1;
$$;

create or replace function public.hikvision_gateway_rotate_token_service(
  p_market_id uuid,
  p_token_sha256 text
)
returns table(gateway_id uuid, market_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_token_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_token_hash';
  end if;
  return query
  update private.hikvision_gateways g
     set token_sha256 = p_token_sha256,
         active = true,
         last_error = null,
         updated_at = now()
   where g.market_id = p_market_id
   returning g.id, g.market_id;
end;
$$;

create or replace function public.hikvision_gateway_claim_service(p_gateway_id uuid)
returns table (
  job_id uuid,
  market_id uuid,
  source_type text,
  source_id uuid,
  transaction_at timestamptz,
  channel_id integer,
  clip_start_at timestamptz,
  clip_end_at timestamptz,
  attempt_count integer
)
language sql
security definer
set search_path = ''
as $$
  select * from private.claim_hikvision_video_job(p_gateway_id);
$$;

create or replace function public.hikvision_gateway_heartbeat_service(
  p_gateway_id uuid,
  p_gateway_version text default '',
  p_platform text default '',
  p_ip text default null
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select private.heartbeat_hikvision_gateway(p_gateway_id,p_gateway_version,p_platform,p_ip);
$$;

create or replace function public.hikvision_gateway_prepare_upload_service(
  p_gateway_id uuid,
  p_job_id uuid
)
returns table (
  market_id uuid,
  source_type text,
  source_id uuid,
  transaction_at timestamptz,
  channel_id integer,
  clip_start_at timestamptz,
  clip_end_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_video_jobs j
  set status='uploading', lease_until=now()+interval '10 minutes', updated_at=now()
  where j.id=p_job_id and j.gateway_id=p_gateway_id and j.status='processing';
  if not found then return; end if;

  update public.transaction_video_evidence e
  set status='uploading', updated_at=now()
  where e.job_id=p_job_id;

  return query
  select j.market_id,j.source_type,j.source_id,j.transaction_at,j.channel_id,j.clip_start_at,j.clip_end_at
  from private.hikvision_video_jobs j
  where j.id=p_job_id;
end;
$$;

create or replace function public.hikvision_gateway_complete_service(
  p_gateway_id uuid,
  p_job_id uuid,
  p_object_path text,
  p_thumbnail_path text default null,
  p_content_sha256 text default null,
  p_byte_size bigint default null,
  p_duration_seconds integer default null,
  p_playback_metadata jsonb default '{}'::jsonb
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select private.complete_hikvision_video_job(
    p_gateway_id,p_job_id,p_object_path,p_thumbnail_path,p_content_sha256,
    p_byte_size,p_duration_seconds,p_playback_metadata
  );
$$;

create or replace function public.hikvision_gateway_fail_service(
  p_gateway_id uuid,
  p_job_id uuid,
  p_error text,
  p_missing boolean default false
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select private.fail_hikvision_video_job(p_gateway_id,p_job_id,p_error,p_missing);
$$;

create or replace function public.hikvision_gateway_status_service(p_market_id uuid)
returns table (
  gateway_id uuid,
  active boolean,
  paired boolean,
  last_seen_at timestamptz,
  gateway_version text,
  platform text,
  last_error text,
  queued bigint,
  processing bigint,
  ready bigint,
  failed bigint,
  missing bigint
)
language sql
security definer
set search_path = ''
as $$
  select g.id,g.active,(g.token_sha256 is not null),g.last_seen_at,g.gateway_version,g.platform,g.last_error,
    count(*) filter (where j.status in ('queued','retrying')),
    count(*) filter (where j.status in ('processing','uploading')),
    count(*) filter (where j.status='ready'),
    count(*) filter (where j.status='failed'),
    count(*) filter (where j.status='missing')
  from private.hikvision_gateways g
  left join private.hikvision_video_jobs j on j.market_id=g.market_id
  where g.market_id=p_market_id
  group by g.id,g.active,g.token_sha256,g.last_seen_at,g.gateway_version,g.platform,g.last_error;
$$;

revoke all on function public.hikvision_gateway_auth_service(text) from public, anon, authenticated;
revoke all on function public.hikvision_gateway_rotate_token_service(uuid,text) from public, anon, authenticated;
revoke all on function public.hikvision_gateway_claim_service(uuid) from public, anon, authenticated;
revoke all on function public.hikvision_gateway_heartbeat_service(uuid,text,text,text) from public, anon, authenticated;
revoke all on function public.hikvision_gateway_prepare_upload_service(uuid,uuid) from public, anon, authenticated;
revoke all on function public.hikvision_gateway_complete_service(uuid,uuid,text,text,text,bigint,integer,jsonb) from public, anon, authenticated;
revoke all on function public.hikvision_gateway_fail_service(uuid,uuid,text,boolean) from public, anon, authenticated;
revoke all on function public.hikvision_gateway_status_service(uuid) from public, anon, authenticated;

grant execute on function public.hikvision_gateway_auth_service(text) to service_role;
grant execute on function public.hikvision_gateway_rotate_token_service(uuid,text) to service_role;
grant execute on function public.hikvision_gateway_claim_service(uuid) to service_role;
grant execute on function public.hikvision_gateway_heartbeat_service(uuid,text,text,text) to service_role;
grant execute on function public.hikvision_gateway_prepare_upload_service(uuid,uuid) to service_role;
grant execute on function public.hikvision_gateway_complete_service(uuid,uuid,text,text,text,bigint,integer,jsonb) to service_role;
grant execute on function public.hikvision_gateway_fail_service(uuid,uuid,text,boolean) to service_role;
grant execute on function public.hikvision_gateway_status_service(uuid) to service_role;
