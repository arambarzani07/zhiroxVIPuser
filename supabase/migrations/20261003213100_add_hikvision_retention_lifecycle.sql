-- Enforce Hikvision video retention while preserving transaction evidence metadata.
-- Physical Storage objects are removed by the authenticated gateway Edge Function;
-- this migration owns expiry state, fencing, throttling, and audit metadata.

alter table private.hikvision_gateways
  add column if not exists last_retention_sweep_at timestamptz;

alter table public.transaction_video_evidence
  add column if not exists expires_at timestamptz,
  add column if not exists expired_at timestamptz;

alter table public.transaction_video_evidence
  drop constraint if exists transaction_video_evidence_status_check;

alter table public.transaction_video_evidence
  add constraint transaction_video_evidence_status_check
  check (status in ('queued','processing','uploading','ready','missing','failed','expired'));

create index if not exists transaction_video_evidence_retention_idx
  on public.transaction_video_evidence(market_id, expires_at)
  where status = 'ready' and object_path is not null and expires_at is not null;

update public.transaction_video_evidence e
set expires_at = coalesce(e.captured_at, e.transaction_at, e.created_at, now())
                 + make_interval(days => coalesce(c.retention_days, 90))
from public.hikvision_market_config c
where c.market_id = e.market_id
  and e.status = 'ready'
  and e.object_path is not null
  and e.expires_at is null;

update public.transaction_video_evidence e
set expires_at = coalesce(e.captured_at, e.transaction_at, e.created_at, now())
                 + interval '90 days'
where e.status = 'ready'
  and e.object_path is not null
  and e.expires_at is null;

create or replace function public.hikvision_gateway_retention_due_service(
  p_gateway_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update private.hikvision_gateways g
  set last_retention_sweep_at = now(),
      updated_at = now()
  where g.id = p_gateway_id
    and g.active = true
    and (
      g.last_retention_sweep_at is null
      or g.last_retention_sweep_at < now() - interval '15 minutes'
    );
  return found;
end;
$$;

create or replace function public.hikvision_retention_candidates_service(
  p_market_id uuid,
  p_limit integer default 20
)
returns table (
  evidence_id uuid,
  object_path text,
  thumbnail_path text,
  expires_at timestamptz
)
language sql
security definer
set search_path = ''
as $$
  select e.id, e.object_path, e.thumbnail_path, e.expires_at
  from public.transaction_video_evidence e
  where e.market_id = p_market_id
    and e.status = 'ready'
    and e.expires_at is not null
    and e.expires_at <= now()
    and e.object_path is not null
  order by e.expires_at asc, e.id asc
  limit least(greatest(coalesce(p_limit, 20), 1), 100);
$$;

create or replace function public.hikvision_mark_video_expired_service(
  p_market_id uuid,
  p_evidence_id uuid,
  p_object_path text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.transaction_video_evidence e
  set status = 'expired',
      object_path = null,
      thumbnail_path = null,
      expired_at = now(),
      updated_at = now(),
      playback_metadata = coalesce(e.playback_metadata, '{}'::jsonb)
        || jsonb_build_object('retention_expired_at', now())
  where e.id = p_evidence_id
    and e.market_id = p_market_id
    and e.status = 'ready'
    and e.expires_at is not null
    and e.expires_at <= now()
    and e.object_path = p_object_path;
  return found;
end;
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
    and j.active_attempt_token is null
    and j.status in ('processing','uploading');
  if not found then return false; end if;

  update public.transaction_video_evidence e
  set status='ready', object_path=p_object_path, thumbnail_path=p_thumbnail_path,
      content_sha256=p_content_sha256, byte_size=p_byte_size,
      duration_seconds=p_duration_seconds,
      playback_metadata=coalesce(p_playback_metadata,'{}'::jsonb),
      captured_at=now(),
      expires_at=now()+make_interval(days => coalesce((
        select c.retention_days
        from public.hikvision_market_config c
        where c.market_id=e.market_id
      ),90)),
      expired_at=null,
      updated_at=now()
  where e.job_id=p_job_id;
  return true;
end;
$$;

create or replace function private.complete_hikvision_video_job_v2(
  p_gateway_id uuid,
  p_job_id uuid,
  p_attempt_token uuid,
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
  set status = 'ready',
      lease_until = null,
      last_attempt_heartbeat_at = now(),
      completed_at = now(),
      updated_at = now(),
      playback_metadata = coalesce(p_playback_metadata,'{}'::jsonb),
      last_error = null
  where j.id = p_job_id
    and j.gateway_id = p_gateway_id
    and j.active_attempt_token = p_attempt_token
    and j.status in ('processing','uploading');

  if not found then
    return exists (
      select 1
      from private.hikvision_video_jobs j
      join public.transaction_video_evidence e on e.job_id = j.id
      where j.id = p_job_id
        and j.gateway_id = p_gateway_id
        and j.active_attempt_token = p_attempt_token
        and j.status = 'ready'
        and e.status = 'ready'
        and e.object_path = p_object_path
    );
  end if;

  update public.transaction_video_evidence e
  set status = 'ready',
      object_path = p_object_path,
      thumbnail_path = p_thumbnail_path,
      content_sha256 = p_content_sha256,
      byte_size = p_byte_size,
      duration_seconds = p_duration_seconds,
      playback_metadata = coalesce(p_playback_metadata,'{}'::jsonb),
      captured_at = now(),
      expires_at = now()+make_interval(days => coalesce((
        select c.retention_days
        from public.hikvision_market_config c
        where c.market_id=e.market_id
      ),90)),
      expired_at = null,
      updated_at = now()
  where e.job_id = p_job_id;

  return true;
end;
$$;

revoke all on function public.hikvision_gateway_retention_due_service(uuid) from public, anon, authenticated;
revoke all on function public.hikvision_retention_candidates_service(uuid,integer) from public, anon, authenticated;
revoke all on function public.hikvision_mark_video_expired_service(uuid,uuid,text) from public, anon, authenticated;

grant execute on function public.hikvision_gateway_retention_due_service(uuid) to service_role;
grant execute on function public.hikvision_retention_candidates_service(uuid,integer) to service_role;
grant execute on function public.hikvision_mark_video_expired_service(uuid,uuid,text) to service_role;
