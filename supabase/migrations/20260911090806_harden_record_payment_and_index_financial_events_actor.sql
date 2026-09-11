revoke execute on function public.record_payment(uuid,numeric,text,text,uuid) from anon;
grant execute on function public.record_payment(uuid,numeric,text,text,uuid) to authenticated;

create index if not exists idx_financial_events_actor_id
  on public.financial_events(actor_id);
