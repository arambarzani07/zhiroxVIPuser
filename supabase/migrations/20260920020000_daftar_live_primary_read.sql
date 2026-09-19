alter table public.daftar_sync_sources
  add column if not exists live_read_mode text not null default 'off',
  add column if not exists live_read_fallback_enabled boolean not null default true,
  add column if not exists live_read_stale_after_seconds integer not null default 300;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_live_read_mode_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_live_read_mode_check
      check (live_read_mode in ('off', 'shadow', 'live'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'daftar_sync_sources_live_read_stale_check'
      and conrelid = 'public.daftar_sync_sources'::regclass
  ) then
    alter table public.daftar_sync_sources
      add constraint daftar_sync_sources_live_read_stale_check
      check (live_read_stale_after_seconds between 60 and 3600);
  end if;
end;
$$;

create table if not exists public.daftar_live_read_events (
  id bigint generated always as identity primary key,
  sync_source_id uuid not null
    references public.daftar_sync_sources(id) on delete restrict,
  viewer_id uuid not null,
  operation text not null,
  result_source text not null
    check (result_source in ('live', 'mirror', 'error')),
  status text not null
    check (status in ('success', 'fallback', 'rejected', 'failed')),
  fallback_reason text,
  live_status integer,
  live_latency_ms integer,
  total_latency_ms integer not null,
  mirror_age_ms bigint,
  detail_code text,
  created_at timestamptz not null default now()
);

create index if not exists daftar_live_read_events_source_time_idx
  on public.daftar_live_read_events(sync_source_id, created_at desc);

alter table public.daftar_live_read_events enable row level security;
revoke all on public.daftar_live_read_events
  from public, anon, authenticated;
grant all on public.daftar_live_read_events to service_role;
grant usage, select on sequence public.daftar_live_read_events_id_seq
  to service_role;
