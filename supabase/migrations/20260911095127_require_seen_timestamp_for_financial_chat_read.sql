create or replace function public.mark_financial_chat_read_through(
  p_customer_id uuid,
  p_read_through timestamptz
)
returns void
language sql
set search_path to ''
as $function$
  insert into public.financial_chat_reads(viewer_id, customer_id, last_read_at)
  select
    (select auth.uid()),
    p_customer_id,
    least(p_read_through, now())
  where p_read_through is not null
  on conflict (viewer_id, customer_id)
  do update set last_read_at = greatest(
    public.financial_chat_reads.last_read_at,
    excluded.last_read_at
  );
$function$;

revoke all on function public.mark_financial_chat_read_through(uuid, timestamptz) from public, anon;
grant execute on function public.mark_financial_chat_read_through(uuid, timestamptz) to authenticated;
