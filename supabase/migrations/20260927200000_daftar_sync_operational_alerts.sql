-- Persistent tenant-scoped alerts; never expose the source secret or error payload.
create table if not exists public.daftar_sync_alerts (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('failures', 'stale', 'dead_letters', 'outbound')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  resolved_at timestamptz
);
create unique index if not exists daftar_sync_alerts_one_open
  on public.daftar_sync_alerts(source_id, kind) where resolved_at is null;
create index if not exists daftar_sync_alerts_admin_open
  on public.daftar_sync_alerts(admin_id, first_seen_at desc) where resolved_at is null;
alter table public.daftar_sync_alerts enable row level security;
revoke all on public.daftar_sync_alerts from public, anon, authenticated;

create or replace function private.refresh_daftar_sync_alerts()
returns void language plpgsql security definer set search_path = '' as $$
declare s record; v_kind text; v_issue boolean;
begin
  for s in
    select id, admin_id, enabled, created_at, last_success_at,
      consecutive_failures, health_status, circuit_open_until
    from public.daftar_sync_sources
  loop
    foreach v_kind in array array['failures','stale','dead_letters','outbound'] loop
      v_issue := case v_kind
        when 'failures' then s.enabled and (s.consecutive_failures >= 3
          or s.health_status = 'circuit_open' or s.circuit_open_until > now())
        when 'stale' then s.enabled and s.created_at < now() - interval '20 minutes'
          and (s.last_success_at is null or s.last_success_at < now() - interval '20 minutes')
        when 'dead_letters' then s.enabled and exists (
          select 1 from public.daftar_sync_dead_letters d
          where d.sync_source_id = s.id and d.resolved_at is null
            and d.first_seen_at < now() - interval '10 minutes')
        when 'outbound' then s.enabled and exists (
          select 1 from public.daftar_outbound_events e
          where e.sync_source_id = s.id
            and ((e.status in ('failed','blocked') and e.updated_at < now() - interval '10 minutes')
              or (e.status in ('pending','processing') and e.created_at < now() - interval '20 minutes')))
        else false end;
      if v_issue then
        insert into public.daftar_sync_alerts(source_id, admin_id, kind)
        values(s.id, s.admin_id, v_kind)
        on conflict (source_id, kind) where resolved_at is null
        do update set last_seen_at = now();
      else
        update public.daftar_sync_alerts a set resolved_at = now()
        where a.source_id = s.id and a.kind = v_kind and a.resolved_at is null;
      end if;
    end loop;
  end loop;
end;
$$;
revoke all on function private.refresh_daftar_sync_alerts() from public, anon, authenticated;

create or replace function public.get_my_daftar_sync_alerts()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles p where p.id = (select auth.uid())
    and p.role = 'admin' and p.active) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id, 'kind', a.kind, 'first_seen_at', a.first_seen_at,
    'acknowledged_at', a.acknowledged_at, 'source_name', s.source_name
  ) order by a.first_seen_at desc), '[]'::jsonb)
  from public.daftar_sync_alerts a
  join public.daftar_sync_sources s on s.id = a.source_id
  where a.admin_id = (select auth.uid()) and a.resolved_at is null);
end;
$$;
revoke all on function public.get_my_daftar_sync_alerts() from public, anon;
grant execute on function public.get_my_daftar_sync_alerts() to authenticated;

create or replace function public.acknowledge_my_daftar_sync_alert(p_alert_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles p where p.id = (select auth.uid())
    and p.role = 'admin' and p.active) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  update public.daftar_sync_alerts
    set acknowledged_at = now()
  where id = p_alert_id and admin_id = (select auth.uid()) and resolved_at is null;
end;
$$;
revoke all on function public.acknowledge_my_daftar_sync_alert(uuid) from public, anon;
grant execute on function public.acknowledge_my_daftar_sync_alert(uuid) to authenticated;

do $$ begin
  if not exists (select 1 from cron.job where jobname = 'zhirox-daftar-operational-alerts') then
    perform cron.schedule('zhirox-daftar-operational-alerts', '*/5 * * * *',
      'select private.refresh_daftar_sync_alerts();');
  end if;
end $$;
