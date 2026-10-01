create or replace function public.get_customer_effective_balance(p_customer_id uuid)
returns numeric
language sql
stable
set search_path to ''
as $function$
  with official as (
    select o.balance_iqd
    from private.get_daftar_official_customer_totals(p_customer_id) o
    limit 1
  ),
  local_balance as (
    select coalesce(sum(d.remaining), 0)::numeric as amount
    from public.debts d
    where d.customer_id = p_customer_id
      and d.is_deleted = false
      and d.remaining > 0
      and upper(coalesce(d.currency, 'IQD')) <> 'USD'
  ),
  all_general_paid as (
    select coalesce(sum(g.amount), 0)::numeric as amount
    from public.customer_general_payments g
    where g.customer_id = p_customer_id
  ),
  unmirrored_general_paid as (
    select private.customer_unmirrored_general_paid_total(p_customer_id)::numeric as amount
  )
  select greatest(
    case
      when (select balance_iqd from official) is not null then
        coalesce((select balance_iqd from official), 0)
        - coalesce((select amount from unmirrored_general_paid), 0)
      else
        coalesce((select amount from local_balance), 0)
        - coalesce((select amount from all_general_paid), 0)
    end,
    0
  )::numeric;
$function$;
