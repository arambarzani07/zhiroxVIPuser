create table if not exists private.telegram_full_statement_jobs (
  id uuid primary key default gen_random_uuid(),
  chat_id text not null,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  market_id uuid not null references public.profiles(id) on delete cascade,
  next_offset integer not null default 0 check (next_offset >= 0),
  chunk_size integer not null default 200 check (chunk_size between 1 and 200),
  total_rows integer not null default 0 check (total_rows >= 0),
  status text not null default 'queued' check (status in ('queued','processing','retrying','succeeded','dead_letter','cancelled')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 8 check (max_attempts between 1 and 20),
  run_after timestamptz not null default now(),
  locked_at timestamptz,
  last_error text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists telegram_full_statement_jobs_ready_idx
  on private.telegram_full_statement_jobs(status, run_after, created_at)
  where status in ('queued','retrying');
create index if not exists telegram_full_statement_jobs_chat_active_idx
  on private.telegram_full_statement_jobs(chat_id, created_at desc)
  where status in ('queued','processing','retrying');

revoke all on private.telegram_full_statement_jobs from public, anon, authenticated;

create or replace function public.get_telegram_customer_statement_chunk_service(
  p_chat_id text,
  p_offset integer default 0,
  p_limit integer default 200
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_customer public.profiles%rowtype;
  v_market public.profiles%rowtype;
  v_rows jsonb := '[]'::jsonb;
  v_has_more boolean := false;
  v_limit integer := greatest(1, least(coalesce(p_limit,200),200));
  v_offset integer := greatest(0, coalesce(p_offset,0));
  v_balance numeric := 0;
begin
  if nullif(btrim(p_chat_id),'') is null then return null; end if;

  select p.* into v_customer
  from private.telegram_credentials tc
  join public.profiles p on p.id = tc.user_id
  where tc.chat_id = p_chat_id
    and p.role = 'customer'
    and p.active = true
    and p.approved = true
  limit 1;

  if v_customer.id is null or v_customer.admin_id is null then return null; end if;

  select p.* into v_market
  from public.profiles p
  where p.id = v_customer.admin_id
    and p.role = 'admin'
    and p.active = true
    and p.approved = true
    and (p.is_system_owner or p.subscription_end is null or p.subscription_end >= now())
  limit 1;

  if v_market.id is null then return null; end if;
  v_balance := public.get_customer_effective_balance(v_customer.id);

  with ledger as (
    select d.id, 'debt'::text as kind, null::text as payment_scope,
           d.amount, coalesce(nullif(d.currency,''),'IQD') as currency,
           coalesce(d.custom_date,d.created_at) as occurred_at, d.description as note
    from public.debts d
    where d.customer_id = v_customer.id and d.is_deleted = false
    union all
    select p.id, 'payment'::text, 'debt'::text,
           p.amount, coalesce(nullif(d.currency,''),'IQD'), p.created_at, p.note
    from public.payments p
    join public.debts d on d.id = p.debt_id
    where d.customer_id = v_customer.id and d.is_deleted = false
    union all
    select g.id, 'payment'::text, 'general'::text,
           g.amount, 'IQD'::text, g.created_at, g.note
    from public.customer_general_payments g
    where g.customer_id = v_customer.id
  ), page as (
    select * from ledger
    order by occurred_at desc, kind, id
    offset v_offset
    limit v_limit + 1
  ), numbered as (
    select row_number() over(order by occurred_at desc, kind, id) as rn, p.*
    from page p
  )
  select
    coalesce(jsonb_agg(to_jsonb(n) - 'rn' order by n.rn) filter (where n.rn <= v_limit), '[]'::jsonb),
    count(*) > v_limit
  into v_rows, v_has_more
  from numbered n;

  return jsonb_build_object(
    'customer_id', v_customer.id,
    'customer_name', v_customer.name,
    'market_id', v_market.id,
    'market_name', coalesce(nullif(v_market.market_name,''),'ZHIROX'),
    'remaining_iqd', coalesce(v_balance,0),
    'offset', v_offset,
    'limit', v_limit,
    'rows', v_rows,
    'has_more', v_has_more,
    'as_of', now()
  );
end;
$$;

create or replace function public.enqueue_telegram_full_statement_service(p_chat_id text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_customer_id uuid;
  v_market_id uuid;
  v_existing private.telegram_full_statement_jobs%rowtype;
  v_total integer := 0;
  v_job_id uuid;
begin
  if nullif(btrim(p_chat_id),'') is null then raise exception 'invalid_chat_id'; end if;

  select customer.id, customer.admin_id
    into v_customer_id, v_market_id
  from private.telegram_credentials tc
  join public.profiles customer on customer.id = tc.user_id
  join public.profiles market on market.id = customer.admin_id
  where tc.chat_id = p_chat_id
    and customer.role='customer' and customer.active=true and customer.approved=true
    and market.role='admin' and market.active=true and market.approved=true
    and (market.is_system_owner or market.subscription_end is null or market.subscription_end >= now())
  limit 1;

  if v_customer_id is null or v_market_id is null then raise exception 'telegram_not_linked'; end if;

  select * into v_existing
  from private.telegram_full_statement_jobs j
  where j.chat_id = p_chat_id and j.status in ('queued','processing','retrying')
  order by j.created_at desc
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'job_id',v_existing.id,'status',v_existing.status,'total_rows',v_existing.total_rows,
      'chunk_size',v_existing.chunk_size,
      'total_parts',greatest(1,ceil(v_existing.total_rows::numeric/v_existing.chunk_size)::integer),
      'existing',true
    );
  end if;

  select count(*)::integer into v_total from (
    select d.id from public.debts d where d.customer_id=v_customer_id and d.is_deleted=false
    union all
    select p.id from public.payments p join public.debts d on d.id=p.debt_id where d.customer_id=v_customer_id and d.is_deleted=false
    union all
    select g.id from public.customer_general_payments g where g.customer_id=v_customer_id
  ) q;

  insert into private.telegram_full_statement_jobs(chat_id,customer_id,market_id,total_rows)
  values (p_chat_id,v_customer_id,v_market_id,v_total)
  returning id into v_job_id;

  return jsonb_build_object(
    'job_id',v_job_id,'status','queued','total_rows',v_total,'chunk_size',200,
    'total_parts',greatest(1,ceil(v_total::numeric/200)::integer),'existing',false
  );
end;
$$;

create or replace function public.claim_telegram_full_statement_job_service()
returns table(job_id uuid, chat_id text, next_offset integer, chunk_size integer, total_rows integer, part_no integer, total_parts integer)
language plpgsql
security definer
set search_path to ''
as $$
begin
  return query
  with candidate as (
    select j.id
    from private.telegram_full_statement_jobs j
    where j.status in ('queued','retrying') and j.run_after <= now()
    order by j.created_at
    for update skip locked
    limit 1
  ), updated as (
    update private.telegram_full_statement_jobs j
    set status='processing', locked_at=now(), updated_at=now(), attempt_count=j.attempt_count+1
    from candidate c
    where j.id=c.id
    returning j.id,j.chat_id,j.next_offset,j.chunk_size,j.total_rows
  )
  select u.id,u.chat_id,u.next_offset,u.chunk_size,u.total_rows,
         (u.next_offset/u.chunk_size)+1,
         greatest(1,ceil(u.total_rows::numeric/u.chunk_size)::integer)
  from updated u;
end;
$$;

create or replace function public.finish_telegram_full_statement_chunk_service(
  p_job_id uuid,
  p_sent_count integer,
  p_has_more boolean
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_job private.telegram_full_statement_jobs%rowtype;
begin
  select * into v_job from private.telegram_full_statement_jobs where id=p_job_id for update;
  if v_job.id is null then raise exception 'job_not_found'; end if;
  if v_job.status <> 'processing' then raise exception 'job_not_processing'; end if;

  if coalesce(p_has_more,false) and coalesce(p_sent_count,0) > 0 then
    update private.telegram_full_statement_jobs
    set status='queued', next_offset=next_offset+p_sent_count, run_after=now(), locked_at=null,
        last_error=null, updated_at=now()
    where id=p_job_id;
    return jsonb_build_object('status','queued','next_offset',v_job.next_offset+p_sent_count);
  else
    update private.telegram_full_statement_jobs
    set status='succeeded', next_offset=next_offset+greatest(coalesce(p_sent_count,0),0),
        locked_at=null,last_error=null,completed_at=now(),updated_at=now()
    where id=p_job_id;
    return jsonb_build_object('status','succeeded');
  end if;
end;
$$;

create or replace function public.retry_telegram_full_statement_job_service(p_job_id uuid,p_error text)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_status text;
begin
  update private.telegram_full_statement_jobs j
  set status=case when j.attempt_count >= j.max_attempts then 'dead_letter' else 'retrying' end,
      run_after=case when j.attempt_count >= j.max_attempts then j.run_after else now()+make_interval(mins => least(60,power(2,greatest(j.attempt_count,1))::integer)) end,
      locked_at=null,last_error=left(coalesce(p_error,'failed'),1000),updated_at=now()
  where j.id=p_job_id
  returning status into v_status;
  return v_status;
end;
$$;

create or replace function private.recover_stuck_telegram_full_statement_jobs()
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare v_count integer;
begin
  update private.telegram_full_statement_jobs j
  set status=case when j.attempt_count >= j.max_attempts then 'dead_letter' else 'retrying' end,
      run_after=now(),locked_at=null,last_error=coalesce(j.last_error,'stuck_processing_recovered'),updated_at=now()
  where j.status='processing' and j.locked_at < now()-interval '5 minutes';
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

create or replace function private.invoke_telegram_full_statement_worker_service()
returns bigint
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $$
declare
  v_config jsonb;
  v_secret text;
  v_request_id bigint;
begin
  v_config := public.get_customer_push_runtime_config_service();
  v_secret := nullif(v_config->>'customer_push_worker_secret','');
  if v_secret is null then raise exception 'customer_push_worker_secret_missing'; end if;
  select net.http_post(
    url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/telegram-full-statement-worker',
    body := '{}'::jsonb,
    params := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type','application/json','x-zhirox-push-worker',v_secret),
    timeout_milliseconds := 10000
  ) into v_request_id;
  return v_request_id;
end;
$$;

revoke all on function public.get_telegram_customer_statement_chunk_service(text,integer,integer) from public,anon,authenticated;
revoke all on function public.enqueue_telegram_full_statement_service(text) from public,anon,authenticated;
revoke all on function public.claim_telegram_full_statement_job_service() from public,anon,authenticated;
revoke all on function public.finish_telegram_full_statement_chunk_service(uuid,integer,boolean) from public,anon,authenticated;
revoke all on function public.retry_telegram_full_statement_job_service(uuid,text) from public,anon,authenticated;
grant execute on function public.get_telegram_customer_statement_chunk_service(text,integer,integer) to service_role;
grant execute on function public.enqueue_telegram_full_statement_service(text) to service_role;
grant execute on function public.claim_telegram_full_statement_job_service() to service_role;
grant execute on function public.finish_telegram_full_statement_chunk_service(uuid,integer,boolean) to service_role;
grant execute on function public.retry_telegram_full_statement_job_service(uuid,text) to service_role;

select cron.unschedule(jobid) from cron.job where jobname='zhirox-telegram-full-statement-worker';
select cron.unschedule(jobid) from cron.job where jobname='zhirox-telegram-full-statement-watchdog';
select cron.schedule('zhirox-telegram-full-statement-worker','* * * * *','select private.invoke_telegram_full_statement_worker_service();');
select cron.schedule('zhirox-telegram-full-statement-watchdog','*/5 * * * *','select private.recover_stuck_telegram_full_statement_jobs();');
