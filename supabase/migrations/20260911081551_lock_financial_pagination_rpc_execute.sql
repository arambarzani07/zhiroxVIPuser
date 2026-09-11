revoke execute on function public.get_customer_finance_snapshot(uuid) from anon;
revoke execute on function public.get_customer_financial_timeline_page(uuid, integer, timestamptz, smallint, uuid) from anon;
revoke execute on function public.get_customer_finance_snapshot(uuid) from public;
revoke execute on function public.get_customer_financial_timeline_page(uuid, integer, timestamptz, smallint, uuid) from public;
grant execute on function public.get_customer_finance_snapshot(uuid) to authenticated;
grant execute on function public.get_customer_financial_timeline_page(uuid, integer, timestamptz, smallint, uuid) to authenticated;
