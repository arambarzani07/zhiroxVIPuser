-- Tenant scoped customer directory filters and global pagination for both controls.
create or replace function public.get_customer_directory_page_advanced(
  p_search text default '', p_filter text default 'all',
  p_sort text default 'last_activity_desc', p_limit integer default 60,
  p_offset integer default 0, p_amount numeric default null,
  p_days integer default null
) returns jsonb language sql stable security invoker set search_path = '' as $$
with cfg as (
  select private.current_admin_id() tenant_id,
    greatest(1,least(coalesce(p_limit,60),100)) page_size,
    greatest(0,coalesce(p_offset,0)) page_offset,
    nullif(trim(coalesce(p_search,'')),'') search_text,
    (now() at time zone 'Asia/Baghdad')::date today,
    greatest(1,least(coalesce(p_days,30),3650)) days,
    greatest(0,coalesce(p_amount,100000)) amount
), base as materialized (
  select p.* from public.profiles p cross join cfg c
  where c.tenant_id is not null
    and (select private."current_role"()) in ('admin','employee')
    and p.admin_id=c.tenant_id and p.role='customer'
    and (c.search_text is null or lower(concat_ws(' ',p.name,p.father_name,p.grandfather_name,p.phone))
      like '%' || lower(c.search_text) || '%')
), metrics as materialized (
  select p.*, public.get_customer_effective_balance(p.id)::numeric remaining,
    d.debt_count,d.open_count,d.loan_total,d.loan_month,d.loan_today,
    d.last_debt_at,d.first_debt_at,d.last_debt_amount,d.max_debt_amount,
    d.overdue_count,d.iqd_count,d.usd_count,d.debt_note_count,
    d.month_debt_count,
    pay.payment_count,pay.payment_total,pay.payment_month,pay.payment_today,
    pay.payment_week,pay.last_payment_at,pay.first_payment_at,
    pay.last_payment_amount,pay.max_payment_amount,pay.payment_note_count,
    ev.last_event_at,ev.first_event_at,ev.event_count,ev.event_note_count,
    c.today,c.days,c.amount,
    (select count(*) from public.profiles peer where peer.admin_id=p.admin_id
      and peer.role='customer' and nullif(trim(peer.phone),'')=nullif(trim(p.phone),'')
      and nullif(trim(p.phone),'') is not null) duplicate_phone_count,
    (select count(*) from public.profiles peer where peer.admin_id=p.admin_id
      and peer.role='customer' and lower(trim(peer.name))=lower(trim(p.name))) duplicate_name_count
  from base p cross join cfg c
  cross join lateral (
    select count(*)::integer debt_count,
      count(*) filter(where d.remaining>0)::integer open_count,
      coalesce(sum(d.amount),0)::numeric loan_total,
      coalesce(sum(d.amount) filter(where (d.created_at at time zone 'Asia/Baghdad')::date >= date_trunc('month',c.today)::date),0)::numeric loan_month,
      count(*) filter(where (d.created_at at time zone 'Asia/Baghdad')::date=c.today)::integer loan_today,
      count(*) filter(where (d.created_at at time zone 'Asia/Baghdad')::date >= date_trunc('month',c.today)::date)::integer month_debt_count,
      max(coalesce(d.custom_date,d.created_at)) last_debt_at,
      min(coalesce(d.custom_date,d.created_at)) first_debt_at,
      (array_agg(d.amount order by coalesce(d.custom_date,d.created_at) desc,d.id desc))[1] last_debt_amount,
      max(d.amount) max_debt_amount,
      count(*) filter(where d.remaining>0 and d.due_date<c.today)::integer overdue_count,
      count(*) filter(where d.currency='IQD')::integer iqd_count,
      count(*) filter(where d.currency='USD')::integer usd_count,
      count(*) filter(where nullif(trim(d.description),'') is not null)::integer debt_note_count
    from public.debts d where d.customer_id=p.id and d.is_deleted=false
  ) d
  cross join lateral (
    select count(*)::integer payment_count,coalesce(sum(amount),0)::numeric payment_total,
      coalesce(sum(amount) filter(where (created_at at time zone 'Asia/Baghdad')::date >= date_trunc('month',c.today)::date),0)::numeric payment_month,
      count(*) filter(where (created_at at time zone 'Asia/Baghdad')::date=c.today)::integer payment_today,
      count(*) filter(where created_at >= now()-interval '7 days')::integer payment_week,
      max(created_at) last_payment_at,min(created_at) first_payment_at,
      (array_agg(amount order by created_at desc,id desc))[1] last_payment_amount,
      max(amount) max_payment_amount,
      count(*) filter(where nullif(trim(note),'') is not null)::integer payment_note_count
    from (
      select pay.id,pay.amount,pay.created_at,pay.note from public.payments pay
      join public.debts debt on debt.id=pay.debt_id
      where debt.customer_id=p.id and debt.is_deleted=false
      union all
      select gp.id,gp.amount,gp.created_at,gp.note from public.customer_general_payments gp
      where gp.customer_id=p.id and gp.admin_id=p.admin_id
    ) all_payments
  ) pay
  cross join lateral (
    select max(e.created_at) last_event_at,min(e.created_at) first_event_at,
      count(*)::integer event_count,
      count(*) filter(where nullif(trim(e.description),'') is not null)::integer event_note_count
    from public.financial_events e where e.customer_id=p.id
  ) ev
), enriched as materialized (
  select m.*, greatest(coalesce(m.last_debt_at,'-infinity'::timestamptz),
      coalesce(m.last_payment_at,'-infinity'::timestamptz),
      coalesce(m.last_event_at,'-infinity'::timestamptz)) activity_at,
    least(coalesce(m.first_debt_at,'infinity'::timestamptz),
      coalesce(m.first_payment_at,'infinity'::timestamptz),
      coalesce(m.first_event_at,'infinity'::timestamptz)) first_activity_at,
    (m.debt_count+m.payment_count)::integer transaction_count,
    case when m.loan_total>0 then m.payment_total/m.loan_total else null end payment_ratio
  from metrics m
), filtered as materialized (
  select m.* from enriched m where not exists (
    select 1 from unnest(string_to_array(coalesce(nullif(p_filter,''),'all'),',')) choice(filter_key)
    where not (case trim(choice.filter_key)
    when 'all' then true
    when 'with_debt' then m.remaining>0
    when 'debt_free' then m.remaining<=0
    when 'active' then m.active is true
    when 'inactive' then m.active is false
    when 'vip' then m.is_vip is true
    when 'no_transactions' then m.transaction_count=0
    when 'has_payment' then m.payment_count>0
    when 'no_payment' then m.payment_count=0
    when 'no_phone' then nullif(trim(m.phone),'') is null
    when 'has_phone' then nullif(trim(m.phone),'') is not null
    when 'multiple_open_debts' then m.open_count>1
    when 'more_than_3_open' then m.open_count>3
    when 'no_open_debt' then m.open_count=0
    when 'overdue' then m.overdue_count>0
    when 'fully_paid' then m.loan_total>0 and m.remaining<=0
    when 'partially_paid' then m.loan_total>0 and m.payment_total>0 and m.remaining>0
    when 'paid_with_debt' then m.payment_count>0 and m.remaining>0
    when 'debt_no_payment' then m.remaining>0 and m.payment_count=0
    when 'loan_only' then m.debt_count>0 and m.payment_count=0
    when 'payment_only' then m.debt_count=0 and m.payment_count>0
    when 'today_debt' then m.loan_today>0
    when 'today_payment' then m.payment_today>0
    when 'today_activity' then (m.activity_at at time zone 'Asia/Baghdad')::date=m.today
    when 'payment_week' then m.payment_week>0
    when 'both_week' then m.payment_week>0 and m.last_debt_at>=now()-interval '7 days'
    when 'no_payment_30' then m.last_payment_at is null or m.last_payment_at<now()-interval '30 days'
    when 'inactive_30' then m.activity_at='-infinity'::timestamptz or m.activity_at<now()-interval '30 days'
    when 'inactive_90' then m.activity_at='-infinity'::timestamptz or m.activity_at<now()-interval '90 days'
    when 'new_this_month' then (m.created_at at time zone 'Asia/Baghdad')::date>=date_trunc('month',m.today)::date
    when 'payment_this_month' then m.payment_month>0
    when 'no_payment_this_month' then m.payment_month=0
    when 'no_debt_this_month' then m.month_debt_count=0
    when 'debt_growth_month' then m.loan_month>m.payment_month
    when 'debt_decrease_month' then m.loan_month<m.payment_month
    when 'currency_iqd' then m.iqd_count>0
    when 'currency_usd' then m.usd_count>0
    when 'both_currencies' then m.iqd_count>0 and m.usd_count>0
    when 'has_note' then m.debt_note_count+m.payment_note_count+m.event_note_count>0
    when 'last_note' then (case when m.last_payment_at>m.last_debt_at then m.payment_note_count else m.debt_note_count end)>0
    when 'missing_names' then nullif(trim(m.father_name),'') is null or nullif(trim(m.grandfather_name),'') is null
    when 'incomplete_profile' then nullif(trim(m.phone),'') is null or nullif(trim(m.name),'') is null
    when 'duplicate_name' then m.duplicate_name_count>1
    when 'duplicate_phone' then m.duplicate_phone_count>1
    when 'one_transaction' then m.transaction_count=1
    when 'last_debt' then m.last_debt_at>coalesce(m.last_payment_at,'-infinity'::timestamptz)
    when 'last_payment' then m.last_payment_at>coalesce(m.last_debt_at,'-infinity'::timestamptz)
    when 'balance_over_100k' then m.remaining>100000
    when 'balance_over_1m' then m.remaining>1000000
    when 'balance_over_amount' then m.remaining>m.amount
    when 'balance_under_amount' then m.remaining<m.amount
    when 'activity_within_days' then m.activity_at>=now()-make_interval(days=>m.days)
    when 'activity_outside_days' then m.activity_at<now()-make_interval(days=>m.days)
    when 'payment_within_days' then m.last_payment_at>=now()-make_interval(days=>m.days)
    when 'payment_outside_days' then m.last_payment_at is null or m.last_payment_at<now()-make_interval(days=>m.days)
    when 'last_payment_after_debt' then m.last_payment_at>m.last_debt_at
    when 'last_debt_after_payment' then m.last_debt_at>m.last_payment_at
    else false end)
  )
), ranked as (
  select m.*,row_number() over(order by
    case when p_sort='name_asc' then lower(m.name) end asc nulls last,
    case when p_sort='name_desc' then lower(m.name) end desc nulls last,
    case when p_sort in ('newest','profile_updated_newest') then
      case when p_sort='newest' then m.created_at else m.updated_at end end desc nulls last,
    case when p_sort='oldest' then m.created_at end asc nulls last,
    case when p_sort in ('last_activity_desc','last_debt_newest','last_payment_newest','first_activity_newest') then
      case p_sort when 'last_debt_newest' then m.last_debt_at
        when 'last_payment_newest' then m.last_payment_at
        when 'first_activity_newest' then m.first_activity_at else m.activity_at end end desc nulls last,
    case when p_sort in ('last_activity_asc','last_debt_oldest','last_payment_oldest','first_activity_oldest') then
      case p_sort when 'last_debt_oldest' then m.last_debt_at
        when 'last_payment_oldest' then m.last_payment_at
        when 'first_activity_oldest' then m.first_activity_at else m.activity_at end end asc nulls last,
    case when p_sort in ('balance_high','loan_total_high','payment_total_high','transaction_count_high',
      'open_count_high','last_debt_amount_high','last_payment_amount_high','month_loan_high',
      'month_payment_high','avg_debt_high','avg_payment_high','payment_ratio_high',
      'max_debt_high','max_payment_high','days_since_activity_high','days_since_payment_high') then
      case p_sort when 'balance_high' then m.remaining when 'loan_total_high' then m.loan_total
        when 'payment_total_high' then m.payment_total when 'transaction_count_high' then m.transaction_count
        when 'open_count_high' then m.open_count when 'last_debt_amount_high' then m.last_debt_amount
        when 'last_payment_amount_high' then m.last_payment_amount when 'month_loan_high' then m.loan_month
        when 'month_payment_high' then m.payment_month when 'avg_debt_high' then m.loan_total/nullif(m.debt_count,0)
        when 'avg_payment_high' then m.payment_total/nullif(m.payment_count,0)
        when 'payment_ratio_high' then m.payment_ratio when 'max_debt_high' then m.max_debt_amount
        when 'max_payment_high' then m.max_payment_amount
        when 'days_since_activity_high' then extract(epoch from now()-nullif(m.activity_at,'-infinity'::timestamptz))
        else extract(epoch from now()-m.last_payment_at) end end desc nulls last,
    case when p_sort in ('balance_low','loan_total_low','payment_total_low','transaction_count_low',
      'open_count_low','last_debt_amount_low','last_payment_amount_low','avg_debt_low',
      'avg_payment_low','payment_ratio_low','max_debt_low','max_payment_low',
      'days_since_activity_low','days_since_payment_low') then
      case p_sort when 'balance_low' then m.remaining when 'loan_total_low' then m.loan_total
        when 'payment_total_low' then m.payment_total when 'transaction_count_low' then m.transaction_count
        when 'open_count_low' then m.open_count when 'last_debt_amount_low' then m.last_debt_amount
        when 'last_payment_amount_low' then m.last_payment_amount when 'avg_debt_low' then m.loan_total/nullif(m.debt_count,0)
        when 'avg_payment_low' then m.payment_total/nullif(m.payment_count,0)
        when 'payment_ratio_low' then m.payment_ratio when 'max_debt_low' then m.max_debt_amount
        when 'max_payment_low' then m.max_payment_amount
        when 'days_since_activity_low' then extract(epoch from now()-nullif(m.activity_at,'-infinity'::timestamptz))
        else extract(epoch from now()-m.last_payment_at) end end asc nulls last,
    m.id desc) row_no
  from filtered m
), page as (
  select r.* from ranked r,cfg c
  where r.row_no>c.page_offset and r.row_no<=c.page_offset+c.page_size
), total as (select count(*) total_count from filtered)
select jsonb_build_object(
  'items',coalesce((select jsonb_agg(
    to_jsonb(p)-'duplicate_phone_count'-'duplicate_name_count'-'today'-'days'-'amount'
      || jsonb_build_object('open_debt_count',p.open_count,
        'last_activity_at',nullif(p.activity_at,'-infinity'::timestamptz),
        'last_kind',case when p.last_payment_at>p.last_debt_at then 'payment' else 'debt' end,
        'last_amount',case when p.last_payment_at>p.last_debt_at then p.last_payment_amount else p.last_debt_amount end,
        'last_preview','', 'last_event_type','', 'unread',false)
    order by p.row_no) from page p),'[]'::jsonb),
  'total_count',(select total_count from total),
  'has_more',(select total_count>c.page_offset+c.page_size from total,cfg c),
  'next_cursor',(select case when total_count>c.page_offset+c.page_size
    then jsonb_build_object('offset',c.page_offset+c.page_size) else null end from total,cfg c)
);
$$;
revoke all on function public.get_customer_directory_page_advanced(text,text,text,integer,integer,numeric,integer) from public,anon;
grant execute on function public.get_customer_directory_page_advanced(text,text,text,integer,integer,numeric,integer) to authenticated;
