create table if not exists public.market_autopilot_settings (
  market_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  mode text not null default 'full_auto_safe' check (mode in ('manual','assisted','full_auto_safe')),
  risk_enabled boolean not null default true,
  max_retry_attempts integer not null default 5 check (max_retry_attempts between 1 and 20),
  updated_by uuid null references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.market_autopilot_settings enable row level security;

revoke all on table public.market_autopilot_settings from anon;
revoke all on table public.market_autopilot_settings from authenticated;
grant select, insert, update on table public.market_autopilot_settings to authenticated;

create policy market_autopilot_settings_select_tenant
on public.market_autopilot_settings
for select
to authenticated
using (
  market_id = (select private.current_admin_id())
  and (select private."current_role"()) in ('admin','employee')
);

create policy market_autopilot_settings_insert_admin
on public.market_autopilot_settings
for insert
to authenticated
with check (
  market_id = (select private.current_admin_id())
  and (select private."current_role"()) = 'admin'
  and updated_by = (select auth.uid())
);

create policy market_autopilot_settings_update_admin
on public.market_autopilot_settings
for update
to authenticated
using (
  market_id = (select private.current_admin_id())
  and (select private."current_role"()) = 'admin'
)
with check (
  market_id = (select private.current_admin_id())
  and (select private."current_role"()) = 'admin'
  and updated_by = (select auth.uid())
);

insert into public.market_autopilot_settings (market_id, updated_by)
select p.id, p.id
from public.profiles p
where p.role = 'admin'
on conflict (market_id) do nothing;

create table if not exists private.autopilot_events (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid null references public.profiles(id) on delete cascade,
  event_type text not null,
  source_table text not null,
  source_id uuid not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','materialized','ignored','failed')),
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  processed_at timestamptz null,
  last_error text null
);

create index if not exists autopilot_events_pending_idx
  on private.autopilot_events (status, created_at)
  where status = 'pending';
create index if not exists autopilot_events_market_idx
  on private.autopilot_events (market_id, created_at desc);
create index if not exists autopilot_events_customer_idx
  on private.autopilot_events (customer_id, created_at desc)
  where customer_id is not null;

create table if not exists private.autopilot_jobs (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references private.autopilot_events(id) on delete cascade,
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid null references public.profiles(id) on delete cascade,
  job_type text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued','processing','succeeded','retrying','dead_letter')),
  priority smallint not null default 100,
  attempt_count integer not null default 0,
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  run_after timestamptz not null default now(),
  idempotency_key text not null unique,
  last_error text null,
  locked_at timestamptz null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists autopilot_jobs_ready_idx
  on private.autopilot_jobs (status, run_after, priority, created_at)
  where status in ('queued','retrying');
create index if not exists autopilot_jobs_market_idx
  on private.autopilot_jobs (market_id, created_at desc);

revoke all on table private.autopilot_events from public, anon, authenticated;
revoke all on table private.autopilot_jobs from public, anon, authenticated;

create table if not exists public.customer_risk_scores (
  customer_id uuid primary key references public.profiles(id) on delete cascade,
  market_id uuid not null references public.profiles(id) on delete cascade,
  score integer not null check (score between 0 and 100),
  level text not null check (level in ('low','medium','high')),
  outstanding numeric not null default 0,
  max_overdue_days integer not null default 0,
  days_since_last_payment integer null,
  reasons jsonb not null default '[]'::jsonb,
  calculated_at timestamptz not null default now()
);

alter table public.customer_risk_scores enable row level security;
revoke all on table public.customer_risk_scores from anon;
revoke all on table public.customer_risk_scores from authenticated;
grant select on table public.customer_risk_scores to authenticated;

create policy customer_risk_scores_select_tenant
on public.customer_risk_scores
for select
to authenticated
using (
  market_id = (select private.current_admin_id())
  and (
    (select private."current_role"()) = 'admin'
    or (
      (select private."current_role"()) = 'employee'
      and (select private.employee_has_permission('view_intelligence'))
    )
  )
);

create or replace function private.enqueue_autopilot_debt_event()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_market uuid;
  v_event_type text;
  v_key text;
begin
  v_market := private.profile_tenant_id(new.customer_id);
  if v_market is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    v_event_type := 'debt.created';
    v_key := 'debt.created:' || new.id::text;
  else
    if new.remaining is not distinct from old.remaining
       and new.status is not distinct from old.status
       and new.due_date is not distinct from old.due_date then
      return new;
    end if;
    v_event_type := 'debt.changed';
    v_key := 'debt.changed:' || new.id::text || ':' || extract(epoch from new.updated_at)::text;
  end if;

  insert into private.autopilot_events(
    market_id, customer_id, event_type, source_table, source_id, payload, idempotency_key
  ) values (
    v_market,
    new.customer_id,
    v_event_type,
    'debts',
    new.id,
    jsonb_build_object(
      'remaining', new.remaining,
      'amount', new.amount,
      'currency', new.currency,
      'due_date', new.due_date,
      'status', new.status
    ),
    v_key
  ) on conflict (idempotency_key) do nothing;

  return new;
end;
$$;

create or replace function private.enqueue_autopilot_payment_event()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_market uuid;
  v_customer uuid;
begin
  v_market := private.debt_tenant_id(new.debt_id);
  v_customer := private.debt_customer_id(new.debt_id);
  if v_market is null or v_customer is null then
    return new;
  end if;

  insert into private.autopilot_events(
    market_id, customer_id, event_type, source_table, source_id, payload, idempotency_key
  ) values (
    v_market,
    v_customer,
    'payment.received',
    'payments',
    new.id,
    jsonb_build_object('debt_id', new.debt_id, 'amount', new.amount, 'created_at', new.created_at),
    'payment.received:' || new.id::text
  ) on conflict (idempotency_key) do nothing;

  return new;
end;
$$;

revoke all on function private.enqueue_autopilot_debt_event() from public, anon, authenticated;
revoke all on function private.enqueue_autopilot_payment_event() from public, anon, authenticated;

drop trigger if exists trg_autopilot_debt_event on public.debts;
create trigger trg_autopilot_debt_event
after insert or update of remaining, status, due_date on public.debts
for each row execute function private.enqueue_autopilot_debt_event();

drop trigger if exists trg_autopilot_payment_event on public.payments;
create trigger trg_autopilot_payment_event
after insert on public.payments
for each row execute function private.enqueue_autopilot_payment_event();

create or replace function private.materialize_autopilot_jobs(batch_limit integer default 100)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer := 0;
  r record;
  v_max_attempts integer;
begin
  for r in
    select e.*
    from private.autopilot_events e
    join public.market_autopilot_settings s on s.market_id = e.market_id
    where e.status = 'pending'
      and s.enabled = true
      and s.mode <> 'manual'
      and s.risk_enabled = true
    order by e.created_at
    for update of e skip locked
    limit greatest(1, least(coalesce(batch_limit,100),500))
  loop
    select s.max_retry_attempts into v_max_attempts
    from public.market_autopilot_settings s
    where s.market_id = r.market_id;

    insert into private.autopilot_jobs(
      event_id, market_id, customer_id, job_type, payload,
      max_attempts, idempotency_key
    ) values (
      r.id,
      r.market_id,
      r.customer_id,
      'risk.recalculate',
      jsonb_build_object('reason_event', r.event_type, 'source_table', r.source_table, 'source_id', r.source_id),
      coalesce(v_max_attempts,5),
      'risk.recalculate:' || r.id::text
    ) on conflict (idempotency_key) do nothing;

    update private.autopilot_events
    set status = 'materialized', processed_at = now(), last_error = null
    where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function private.recalculate_customer_risk(target_customer uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_market uuid;
  v_limit numeric := 0;
  v_outstanding numeric := 0;
  v_overdue integer := 0;
  v_last_payment date;
  v_days_since integer;
  v_score integer := 0;
  v_level text;
  v_reasons jsonb := '[]'::jsonb;
begin
  select private.profile_tenant_id(p.id), coalesce(p.debt_limit,0)
  into v_market, v_limit
  from public.profiles p
  where p.id = target_customer and p.role = 'customer';

  if v_market is null then
    delete from public.customer_risk_scores where customer_id = target_customer;
    return;
  end if;

  select coalesce(sum(d.remaining),0),
         coalesce(max(case when d.remaining > 0 and d.due_date is not null and d.due_date < current_date
                           then current_date - d.due_date else 0 end),0)
  into v_outstanding, v_overdue
  from public.debts d
  where d.customer_id = target_customer and d.is_deleted = false;

  select max(p.created_at)::date
  into v_last_payment
  from public.payments p
  join public.debts d on d.id = p.debt_id
  where d.customer_id = target_customer and d.is_deleted = false;

  if v_last_payment is not null then
    v_days_since := current_date - v_last_payment;
  end if;

  if v_overdue > 0 then
    v_score := v_score + least(50, v_overdue * 2);
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object('code','overdue','days',v_overdue));
  end if;

  if v_outstanding > 0 and (v_days_since is null or v_days_since >= 30) then
    v_score := v_score + 20;
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object('code','no_recent_payment','days',v_days_since));
  elsif v_days_since is not null and v_days_since >= 14 then
    v_score := v_score + 10;
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object('code','payment_gap','days',v_days_since));
  end if;

  if v_limit > 0 and v_outstanding > v_limit then
    v_score := v_score + 20;
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object('code','over_limit','outstanding',v_outstanding,'limit',v_limit));
  end if;

  if v_outstanding >= 1000000 then
    v_score := v_score + 10;
    v_reasons := v_reasons || jsonb_build_array(jsonb_build_object('code','high_outstanding','outstanding',v_outstanding));
  end if;

  v_score := greatest(0, least(100, v_score));
  v_level := case when v_score >= 70 then 'high' when v_score >= 35 then 'medium' else 'low' end;

  insert into public.customer_risk_scores(
    customer_id, market_id, score, level, outstanding,
    max_overdue_days, days_since_last_payment, reasons, calculated_at
  ) values (
    target_customer, v_market, v_score, v_level, v_outstanding,
    v_overdue, v_days_since, v_reasons, now()
  )
  on conflict (customer_id) do update set
    market_id = excluded.market_id,
    score = excluded.score,
    level = excluded.level,
    outstanding = excluded.outstanding,
    max_overdue_days = excluded.max_overdue_days,
    days_since_last_payment = excluded.days_since_last_payment,
    reasons = excluded.reasons,
    calculated_at = excluded.calculated_at;
end;
$$;

create or replace function private.run_autopilot_jobs(batch_limit integer default 100)
returns integer
language plpgsql
set search_path = ''
as $$
declare
  v_count integer := 0;
  r record;
begin
  for r in
    select j.*
    from private.autopilot_jobs j
    join public.market_autopilot_settings s on s.market_id = j.market_id
    where j.status in ('queued','retrying')
      and j.run_after <= now()
      and s.enabled = true
      and s.mode <> 'manual'
    order by j.priority, j.created_at
    for update of j skip locked
    limit greatest(1, least(coalesce(batch_limit,100),500))
  loop
    update private.autopilot_jobs
    set status = 'processing', locked_at = now(), updated_at = now(), attempt_count = attempt_count + 1
    where id = r.id;

    begin
      if r.job_type = 'risk.recalculate' and r.customer_id is not null then
        perform private.recalculate_customer_risk(r.customer_id);
      end if;

      update private.autopilot_jobs
      set status = 'succeeded', completed_at = now(), last_error = null, updated_at = now()
      where id = r.id;
      v_count := v_count + 1;
    exception when others then
      update private.autopilot_jobs
      set status = case when attempt_count >= max_attempts then 'dead_letter' else 'retrying' end,
          run_after = case when attempt_count >= max_attempts then run_after else now() + make_interval(mins => least(60, power(2, greatest(attempt_count,1))::integer)) end,
          last_error = left(sqlerrm, 1000),
          locked_at = null,
          updated_at = now()
      where id = r.id;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function private.materialize_autopilot_jobs(integer) from public, anon, authenticated;
revoke all on function private.recalculate_customer_risk(uuid) from public, anon, authenticated;
revoke all on function private.run_autopilot_jobs(integer) from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from cron.job where jobname = 'zhirox-autopilot-materialize') then
    perform cron.schedule('zhirox-autopilot-materialize', '* * * * *', 'select private.materialize_autopilot_jobs(200);');
  end if;
  if not exists (select 1 from cron.job where jobname = 'zhirox-autopilot-worker') then
    perform cron.schedule('zhirox-autopilot-worker', '* * * * *', 'select private.run_autopilot_jobs(200);');
  end if;
end;
$$;