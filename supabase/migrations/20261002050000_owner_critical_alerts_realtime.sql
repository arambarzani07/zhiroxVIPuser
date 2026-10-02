create table if not exists private.owner_critical_alert_state (
  owner_user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  reminder_hours integer not null default 6 check (reminder_hours between 1 and 48),
  last_status text not null default 'healthy' check (last_status in ('healthy','alert')),
  last_fingerprint text,
  last_sent_at timestamptz,
  last_recovered_at timestamptz,
  processing_kind text,
  processing_fingerprint text,
  processing_started_at timestamptz,
  last_error text,
  updated_at timestamptz not null default now()
);

alter table private.owner_critical_alert_state enable row level security;
drop policy if exists owner_critical_alert_state_deny_client on private.owner_critical_alert_state;
create policy owner_critical_alert_state_deny_client
  on private.owner_critical_alert_state
  for all to anon, authenticated
  using (false)
  with check (false);

insert into private.owner_critical_alert_state(owner_user_id)
select id
from public.profiles
where is_system_owner = true
  and active = true
  and approved = true
on conflict (owner_user_id) do nothing;

create index if not exists owner_critical_alert_state_processing_idx
  on private.owner_critical_alert_state(processing_started_at)
  where processing_started_at is not null;
create index if not exists owner_critical_alert_state_enabled_idx
  on private.owner_critical_alert_state(enabled)
  where enabled = true;

create or replace function public.claim_owner_critical_alert_service()
returns table(
  owner_user_id uuid,
  chat_id text,
  alert_kind text,
  fingerprint text,
  payload jsonb
)
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  r record;
  v_overview jsonb;
  v_summary jsonb;
  v_items jsonb;
  v_attention int;
  v_failed bigint;
  v_dead bigint;
  v_critical bigint;
  v_is_alert boolean;
  v_fingerprint text;
  v_now timestamptz := now();
begin
  for r in
    select s.owner_user_id,
           s.last_status,
           s.last_fingerprint,
           s.last_sent_at,
           s.reminder_hours,
           tc.chat_id
    from private.owner_critical_alert_state s
    join public.profiles p
      on p.id = s.owner_user_id
     and p.is_system_owner = true
     and p.active = true
     and p.approved = true
    join private.telegram_credentials tc
      on tc.user_id = s.owner_user_id
     and nullif(btrim(tc.chat_id), '') is not null
    where s.enabled = true
      and (
        s.processing_started_at is null
        or s.processing_started_at < v_now - interval '10 minutes'
      )
    for update of s skip locked
  loop
    v_overview := public.get_system_owner_autopilot_overview_service('', 'all', 1, 100);
    v_summary := coalesce(v_overview->'overview', '{}'::jsonb);
    v_items := coalesce(v_overview->'items', '[]'::jsonb);
    v_attention := coalesce((v_summary->>'attention')::int, 0);
    v_failed := coalesce((v_summary->>'failed')::bigint, 0);
    v_dead := coalesce((v_summary->>'dead_letter')::bigint, 0);
    v_critical := coalesce((v_summary->>'risk_critical')::bigint, 0);
    v_is_alert := v_attention > 0 or v_failed > 0 or v_dead > 0 or v_critical > 0;

    select md5(
      concat_ws(
        '|',
        v_attention::text,
        v_failed::text,
        v_dead::text,
        v_critical::text,
        coalesce(
          string_agg(
            coalesce(x.item->>'market_id', '') || ':' ||
            coalesce(x.item #>> '{health,status}', '') || ':' ||
            coalesce(x.item #>> '{health,failed}', '0') || ':' ||
            coalesce(x.item #>> '{health,dead_letter}', '0') || ':' ||
            coalesce(x.item #>> '{risk,critical}', '0'),
            ',' order by coalesce(x.item->>'market_id', '')
          ),
          ''
        )
      )
    )
    into v_fingerprint
    from jsonb_array_elements(v_items) as x(item);

    if v_is_alert then
      if r.last_status <> 'alert'
         or r.last_fingerprint is distinct from v_fingerprint
         or r.last_sent_at is null
         or r.last_sent_at < v_now - make_interval(hours => r.reminder_hours)
      then
        update private.owner_critical_alert_state
        set processing_kind = 'alert',
            processing_fingerprint = v_fingerprint,
            processing_started_at = v_now,
            last_error = null,
            updated_at = v_now
        where owner_user_id = r.owner_user_id;

        owner_user_id := r.owner_user_id;
        chat_id := r.chat_id;
        alert_kind := 'alert';
        fingerprint := v_fingerprint;
        payload := jsonb_build_object(
          'overview', v_summary,
          'items', v_items,
          'generated_at', v_overview->'generated_at'
        );
        return next;
      end if;
    elsif r.last_status = 'alert' then
      update private.owner_critical_alert_state
      set processing_kind = 'recovery',
          processing_fingerprint = v_fingerprint,
          processing_started_at = v_now,
          last_error = null,
          updated_at = v_now
      where owner_user_id = r.owner_user_id;

      owner_user_id := r.owner_user_id;
      chat_id := r.chat_id;
      alert_kind := 'recovery';
      fingerprint := v_fingerprint;
      payload := jsonb_build_object(
        'overview', v_summary,
        'items', v_items,
        'generated_at', v_overview->'generated_at'
      );
      return next;
    end if;
  end loop;
end;
$fn$;

create or replace function public.finish_owner_critical_alert_service(
  p_owner_user_id uuid,
  p_kind text,
  p_fingerprint text,
  p_success boolean,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if p_success then
    update private.owner_critical_alert_state
    set last_status = case when p_kind = 'recovery' then 'healthy' else 'alert' end,
        last_fingerprint = p_fingerprint,
        last_sent_at = case when p_kind = 'alert' then now() else last_sent_at end,
        last_recovered_at = case when p_kind = 'recovery' then now() else last_recovered_at end,
        processing_kind = null,
        processing_fingerprint = null,
        processing_started_at = null,
        last_error = null,
        updated_at = now()
    where owner_user_id = p_owner_user_id;
  else
    update private.owner_critical_alert_state
    set processing_kind = null,
        processing_fingerprint = null,
        processing_started_at = null,
        last_error = left(coalesce(p_error, 'unknown_error'), 500),
        updated_at = now()
    where owner_user_id = p_owner_user_id;
  end if;
end;
$fn$;

revoke all on function public.claim_owner_critical_alert_service() from public, anon, authenticated;
revoke all on function public.finish_owner_critical_alert_service(uuid,text,text,boolean,text) from public, anon, authenticated;
grant execute on function public.claim_owner_critical_alert_service() to service_role;
grant execute on function public.finish_owner_critical_alert_service(uuid,text,text,boolean,text) to service_role;

create or replace function private.emit_owner_critical_alerts()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  r record;
  v_overview jsonb;
  v_summary jsonb;
  v_items jsonb;
  v_attention int;
  v_failed bigint;
  v_dead bigint;
  v_critical bigint;
  v_is_alert boolean;
  v_fp text;
  v_body text;
  v_count integer := 0;
  v_now timestamptz := now();
begin
  for r in
    select s.owner_user_id,
           s.last_status,
           s.last_fingerprint,
           s.last_sent_at,
           s.reminder_hours
    from private.owner_critical_alert_state s
    join public.profiles p
      on p.id = s.owner_user_id
     and p.is_system_owner = true
     and p.active = true
     and p.approved = true
    where s.enabled = true
    for update of s skip locked
  loop
    v_overview := public.get_system_owner_autopilot_overview_service('', 'all', 1, 100);
    v_summary := coalesce(v_overview->'overview', '{}'::jsonb);
    v_items := coalesce(v_overview->'items', '[]'::jsonb);
    v_attention := coalesce((v_summary->>'attention')::int, 0);
    v_failed := coalesce((v_summary->>'failed')::bigint, 0);
    v_dead := coalesce((v_summary->>'dead_letter')::bigint, 0);
    v_critical := coalesce((v_summary->>'risk_critical')::bigint, 0);
    v_is_alert := v_attention > 0 or v_failed > 0 or v_dead > 0 or v_critical > 0;

    select md5(
      concat_ws(
        '|',
        v_attention::text,
        v_failed::text,
        v_dead::text,
        v_critical::text,
        coalesce(
          string_agg(
            coalesce(x.item->>'market_id', '') || ':' ||
            coalesce(x.item #>> '{health,status}', '') || ':' ||
            coalesce(x.item #>> '{health,failed}', '0') || ':' ||
            coalesce(x.item #>> '{health,dead_letter}', '0') || ':' ||
            coalesce(x.item #>> '{risk,critical}', '0'),
            ',' order by coalesce(x.item->>'market_id', '')
          ),
          ''
        )
      )
    )
    into v_fp
    from jsonb_array_elements(v_items) as x(item);

    if v_is_alert and (
      r.last_status <> 'alert'
      or r.last_fingerprint is distinct from v_fp
      or r.last_sent_at is null
      or r.last_sent_at < v_now - make_interval(hours => r.reminder_hours)
    ) then
      v_body := format(
        'Attention: %s • Failed: %s • Dead-letter: %s • Critical Risk: %s • Queue: %s',
        v_attention,
        v_failed,
        v_dead,
        v_critical,
        coalesce((v_summary->>'active_queue')::bigint, 0)
      );

      insert into public.app_realtime_notifications(
        recipient_user_id,
        market_id,
        title,
        body,
        event_type,
        data,
        expires_at
      )
      values(
        r.owner_user_id,
        null,
        '🚨 ZHIROX AutoPilot Critical Alert',
        v_body,
        'owner_autopilot_critical',
        jsonb_build_object(
          'fingerprint', v_fp,
          'overview', v_summary,
          'items', v_items,
          'kind', 'alert'
        ),
        v_now + interval '7 days'
      );

      update private.owner_critical_alert_state
      set last_status = 'alert',
          last_fingerprint = v_fp,
          last_sent_at = v_now,
          last_error = null,
          processing_kind = null,
          processing_fingerprint = null,
          processing_started_at = null,
          updated_at = v_now
      where owner_user_id = r.owner_user_id;
      v_count := v_count + 1;
    elsif not v_is_alert and r.last_status = 'alert' then
      insert into public.app_realtime_notifications(
        recipient_user_id,
        market_id,
        title,
        body,
        event_type,
        data,
        expires_at
      )
      values(
        r.owner_user_id,
        null,
        '✅ ZHIROX AutoPilot Recovery',
        'هەموو مارکێتەکان گەڕانەوە بۆ دۆخی سالم.',
        'owner_autopilot_recovery',
        jsonb_build_object(
          'fingerprint', v_fp,
          'overview', v_summary,
          'kind', 'recovery'
        ),
        v_now + interval '7 days'
      );

      update private.owner_critical_alert_state
      set last_status = 'healthy',
          last_fingerprint = v_fp,
          last_recovered_at = v_now,
          last_error = null,
          processing_kind = null,
          processing_fingerprint = null,
          processing_started_at = null,
          updated_at = v_now
      where owner_user_id = r.owner_user_id;
      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$fn$;

revoke all on function private.emit_owner_critical_alerts() from public, anon, authenticated;
grant execute on function private.emit_owner_critical_alerts() to service_role;

do $$
declare
  j record;
begin
  for j in
    select jobid from cron.job
    where jobname in ('zhirox-owner-critical-alert-worker', 'zhirox-owner-critical-alert-emitter')
  loop
    perform cron.unschedule(j.jobid);
  end loop;

  perform cron.schedule(
    'zhirox-owner-critical-alert-emitter',
    '*/5 * * * *',
    'select private.emit_owner_critical_alerts();'
  );
end $$;
