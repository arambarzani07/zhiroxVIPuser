revoke all on table public.financial_chat_reads from anon;
revoke all on table public.financial_chat_reads from authenticated;
grant select, insert, update on table public.financial_chat_reads to authenticated;

revoke execute on function public.get_customer_inbox_rows(uuid[]) from public, anon;
grant execute on function public.get_customer_inbox_rows(uuid[]) to authenticated;

revoke execute on function public.mark_financial_chat_read(uuid) from public, anon;
grant execute on function public.mark_financial_chat_read(uuid) to authenticated;
