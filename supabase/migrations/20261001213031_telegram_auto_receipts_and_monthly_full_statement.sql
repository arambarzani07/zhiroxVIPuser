create table if not exists private.telegram_auto_receipt_jobs (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null unique references public.notification_outbox(id) on delete cascade,
  market_id uuid not null references public.profiles(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in ('debt_created','payment_created')),
  event_record_id uuid not null,
  status text not null default 'queued' check (status in ('queued','processing','retrying','succeeded','failed','dead_letter','skipped')),
  attempt_count integer not null default 0,
  max_attempts integer not null default 5,
  run_after timestamptz not null default now(),
  locked_at timestamptz,
  last_error text,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists telegram_auto_receipt_jobs_ready_idx on private.telegram_auto_receipt_jobs(status,run_after,created_at);
create index if not exists telegram_auto_receipt_jobs_customer_idx on private.telegram_auto_receipt_jobs(customer_id);
create index if not exists telegram_auto_receipt_jobs_market_idx on private.telegram_auto_receipt_jobs(market_id);
alter table private.telegram_auto_receipt_jobs enable row level security;
revoke all on private.telegram_auto_receipt_jobs from public, anon, authenticated;

create or replace function private.enqueue_telegram_auto_documents()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_chat_id text; v_max_attempts integer:=5; v_monthly_enabled boolean:=true; v_autopilot_enabled boolean:=false; v_mode text:='manual'; v_entity_kind text;
begin
  select tc.chat_id into v_chat_id from private.telegram_credentials tc where tc.user_id=new.customer_id limit 1;
  if nullif(btrim(coalesce(v_chat_id,'')),'') is null then return new; end if;
  select coalesce(s.enabled,false),coalesce(s.mode,'manual'),coalesce(s.max_retry_attempts,5)
    into v_autopilot_enabled,v_mode,v_max_attempts from public.market_autopilot_settings s where s.market_id=new.market_id;
  if not coalesce(v_autopilot_enabled,false) or coalesce(v_mode,'manual')='manual' then return new; end if;
  if new.event_type in ('debt_created','payment_created') then
    v_entity_kind:=case when new.event_type='debt_created' then 'debt' else 'payment' end;
    if exists(select 1 from public.legacy_import_links l where l.target_id=new.event_record_id and l.entity_kind=v_entity_kind)
       or exists(select 1 from public.daftar_sync_seen s where s.target_id=new.event_record_id and s.entity_kind=v_entity_kind) then return new; end if;
    insert into private.telegram_auto_receipt_jobs(outbox_id,market_id,customer_id,event_type,event_record_id,max_attempts)
    values(new.id,new.market_id,new.customer_id,new.event_type,new.event_record_id,coalesce(v_max_attempts,5)) on conflict(outbox_id) do nothing;
  elsif new.event_type='monthly_statement' then
    select coalesce(p.monthly_statements,true) into v_monthly_enabled from public.customer_notification_preferences p where p.market_id=new.market_id and p.customer_id=new.customer_id;
    if coalesce(v_monthly_enabled,true) then perform public.enqueue_telegram_full_statement_service(v_chat_id); end if;
  end if;
  return new;
end;$$;
revoke all on function private.enqueue_telegram_auto_documents() from public,anon,authenticated;

drop trigger if exists trg_notification_outbox_telegram_auto_documents on public.notification_outbox;
create trigger trg_notification_outbox_telegram_auto_documents after insert on public.notification_outbox
for each row when (new.event_type in ('debt_created','payment_created','monthly_statement')) execute function private.enqueue_telegram_auto_documents();

create or replace function public.claim_telegram_auto_receipt_jobs_service(p_limit integer default 10)
returns table(job_id uuid,market_id uuid,customer_id uuid,event_type text,event_record_id uuid,chat_id text,attempt_count integer,max_attempts integer)
language sql security definer set search_path=''
as $$
with picked as (
 select j.id from private.telegram_auto_receipt_jobs j join public.market_autopilot_settings s on s.market_id=j.market_id
 where j.status in ('queued','retrying') and j.run_after<=now() and s.enabled=true and s.mode<>'manual'
 order by j.run_after,j.created_at for update of j skip locked limit greatest(1,least(coalesce(p_limit,10),50))
), claimed as (
 update private.telegram_auto_receipt_jobs j set status='processing',attempt_count=j.attempt_count+1,locked_at=now(),updated_at=now()
 from picked p where j.id=p.id returning j.*
)
select c.id,c.market_id,c.customer_id,c.event_type,c.event_record_id,tc.chat_id,c.attempt_count,c.max_attempts
from claimed c left join private.telegram_credentials tc on tc.user_id=c.customer_id order by c.created_at;
$$;

create or replace function public.finish_telegram_auto_receipt_job_service(p_job_id uuid,p_status text,p_error text default null)
returns text language plpgsql security definer set search_path=''
as $$ declare v_status text; begin
 if p_status not in ('succeeded','failed','skipped') then raise exception 'invalid_status'; end if;
 update private.telegram_auto_receipt_jobs set status=p_status,last_error=left(p_error,1000),locked_at=null,completed_at=now(),updated_at=now() where id=p_job_id returning status into v_status;
 return v_status;
end;$$;

create or replace function public.retry_telegram_auto_receipt_job_service(p_job_id uuid,p_error text)
returns text language plpgsql security definer set search_path=''
as $$ declare v_status text; begin
 update private.telegram_auto_receipt_jobs j set status=case when j.attempt_count>=j.max_attempts then 'dead_letter' else 'retrying' end,
 run_after=case when j.attempt_count>=j.max_attempts then j.run_after else now()+make_interval(mins=>least(60,power(2,greatest(j.attempt_count,1))::integer)) end,
 locked_at=null,last_error=left(coalesce(p_error,'failed'),1000),updated_at=now() where j.id=p_job_id returning status into v_status;
 return v_status;
end;$$;

create or replace function private.recover_stuck_telegram_auto_receipt_jobs()
returns integer language plpgsql security definer set search_path=''
as $$ declare v_count integer; begin
 update private.telegram_auto_receipt_jobs j set status=case when j.attempt_count>=j.max_attempts then 'dead_letter' else 'retrying' end,run_after=now(),locked_at=null,last_error=coalesce(j.last_error,'stuck_processing_recovered'),updated_at=now()
 where j.status='processing' and j.locked_at<now()-interval '5 minutes'; get diagnostics v_count=row_count; return v_count;
end;$$;

create or replace function private.invoke_telegram_auto_receipt_worker_service()
returns bigint language plpgsql security definer set search_path='pg_catalog','public'
as $$ declare v_config jsonb; v_secret text; v_request_id bigint; begin
 v_config:=public.get_customer_push_runtime_config_service(); v_secret:=nullif(v_config->>'customer_push_worker_secret',''); if v_secret is null then raise exception 'customer_push_worker_secret_missing'; end if;
 select net.http_post(url:='https://madoflmbretqghqbqaak.supabase.co/functions/v1/telegram-auto-receipt-worker',body:='{}'::jsonb,params:='{}'::jsonb,headers:=jsonb_build_object('Content-Type','application/json','x-zhirox-push-worker',v_secret),timeout_milliseconds:=10000) into v_request_id;
 return v_request_id;
end;$$;

revoke all on function public.claim_telegram_auto_receipt_jobs_service(integer) from public,anon,authenticated;
revoke all on function public.finish_telegram_auto_receipt_job_service(uuid,text,text) from public,anon,authenticated;
revoke all on function public.retry_telegram_auto_receipt_job_service(uuid,text) from public,anon,authenticated;
grant execute on function public.claim_telegram_auto_receipt_jobs_service(integer) to service_role;
grant execute on function public.finish_telegram_auto_receipt_job_service(uuid,text,text) to service_role;
grant execute on function public.retry_telegram_auto_receipt_job_service(uuid,text) to service_role;
revoke all on function private.recover_stuck_telegram_auto_receipt_jobs() from public,anon,authenticated;
revoke all on function private.invoke_telegram_auto_receipt_worker_service() from public,anon,authenticated;

select cron.unschedule(jobid) from cron.job where jobname in ('zhirox-telegram-auto-receipt-worker','zhirox-telegram-auto-receipt-watchdog');
select cron.schedule('zhirox-telegram-auto-receipt-worker','* * * * *','select private.invoke_telegram_auto_receipt_worker_service();');
select cron.schedule('zhirox-telegram-auto-receipt-watchdog','*/5 * * * *','select private.recover_stuck_telegram_auto_receipt_jobs();');