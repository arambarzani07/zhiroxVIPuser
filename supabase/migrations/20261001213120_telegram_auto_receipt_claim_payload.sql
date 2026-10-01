drop function if exists public.claim_telegram_auto_receipt_jobs_service(integer);
create function public.claim_telegram_auto_receipt_jobs_service(p_limit integer default 10)
returns table(
  job_id uuid,
  outbox_id uuid,
  market_id uuid,
  customer_id uuid,
  event_type text,
  event_record_id uuid,
  payload jsonb,
  chat_id text,
  attempt_count integer,
  max_attempts integer
)
language sql
security definer
set search_path=''
as $$
with picked as (
  select j.id
  from private.telegram_auto_receipt_jobs j
  join public.market_autopilot_settings s on s.market_id=j.market_id
  where j.status in ('queued','retrying')
    and j.run_after<=now()
    and s.enabled=true
    and s.mode<>'manual'
  order by j.run_after,j.created_at
  for update of j skip locked
  limit greatest(1,least(coalesce(p_limit,10),50))
), claimed as (
  update private.telegram_auto_receipt_jobs j
  set status='processing',attempt_count=j.attempt_count+1,locked_at=now(),updated_at=now()
  from picked p
  where j.id=p.id
  returning j.*
)
select c.id,c.outbox_id,c.market_id,c.customer_id,c.event_type,c.event_record_id,
       o.payload,tc.chat_id,c.attempt_count,c.max_attempts
from claimed c
join public.notification_outbox o on o.id=c.outbox_id
left join private.telegram_credentials tc on tc.user_id=c.customer_id
order by c.created_at;
$$;
revoke all on function public.claim_telegram_auto_receipt_jobs_service(integer) from public,anon,authenticated;
grant execute on function public.claim_telegram_auto_receipt_jobs_service(integer) to service_role;