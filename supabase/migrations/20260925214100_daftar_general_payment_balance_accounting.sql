-- Avoid double-counting customer-wide payments already present in official Daftar totals.


create or replace function private.customer_unmirrored_general_paid_total(
  p_customer_id uuid
)
returns numeric
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(sum(g.amount),0)::numeric
  from public.customer_general_payments g
  where g.customer_id=p_customer_id
    and not exists (
      select 1
      from public.daftar_sync_sources s
      join public.legacy_import_links l
        on l.admin_id=g.admin_id
       and l.entity_kind='payment'
       and l.target_id=g.id
       and exists (
         select 1
         from private.daftar_source_fingerprint_aliases a
         where a.sync_source_id=s.id
           and a.source_fingerprint=l.source_fingerprint
       )
      join public.daftar_mirror_transactions m
        on m.sync_source_id=s.id
       and m.source_id=split_part(l.source_id,':',1)
       and upper(coalesce(m.payload->>'transaction_type',''))='PAYMENT'
      where s.admin_id=g.admin_id
        and s.sync_mode='zhirox_primary'
        and coalesce(s.inbound_sync_enabled,false)=true
        and s.official_totals_at is not null
    );
$function$;

revoke all on function private.customer_unmirrored_general_paid_total(uuid)
  from public,anon,authenticated;
grant execute on function private.customer_unmirrored_general_paid_total(uuid)
  to service_role;


CREATE OR REPLACE FUNCTION public.get_customer_effective_balance(p_customer_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
  general_paid as (
    select private.customer_unmirrored_general_paid_total(p_customer_id)::numeric as amount
  )
  select greatest(
    coalesce(
      (select balance_iqd from official),
      (select amount from local_balance),
      0
    ) - coalesce((select amount from general_paid), 0),
    0
  )::numeric;
$function$;

CREATE OR REPLACE FUNCTION public.get_customer_finance_snapshot(p_customer_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with official as (
    select * from private.get_daftar_official_customer_totals(p_customer_id) limit 1
  ), debt_rows as materialized (
    select d.* from public.debts d where d.customer_id=p_customer_id and d.is_deleted=false
  ), virtual as materialized (
    select * from private.get_customer_virtual_debt_balances(p_customer_id)
  ), summary as (
    select
      coalesce(sum(d.amount) filter(where upper(coalesce(d.currency,'IQD'))<>'USD'),0)::numeric local_total_debt_iqd,
      coalesce(sum(d.remaining) filter(where upper(coalesce(d.currency,'IQD'))<>'USD'),0)::numeric local_gross_remaining_iqd,
      count(*) filter(where coalesce(v.effective_remaining,d.remaining)>0)::bigint open_debt_count
    from debt_rows d left join virtual v on v.debt_id=d.id
  ), local_paid as (
    select private.customer_lifetime_paid_total(p_customer_id)::numeric total_paid_iqd
  ), general_paid as (
    select private.customer_unmirrored_general_paid_total(p_customer_id)::numeric amount
  ), open_debts as (
    select coalesce(jsonb_agg(
      to_jsonb(d)||jsonb_build_object(
        'effective_remaining',coalesce(v.effective_remaining,d.remaining),
        'general_credit_applied',coalesce(v.applied_general_credit,0)
      ) order by coalesce(d.custom_date,d.created_at) desc,d.id desc
    ),'[]'::jsonb) items
    from debt_rows d left join virtual v on v.debt_id=d.id
    where coalesce(v.effective_remaining,d.remaining)>0
  )
  select jsonb_build_object(
    'total_debt_iqd',coalesce((select loan_iqd from official),s.local_total_debt_iqd),
    'total_remaining_iqd',greatest(coalesce((select balance_iqd from official),s.local_gross_remaining_iqd)-gp.amount,0),
    'total_paid_iqd',case when exists(select 1 from official)
      then coalesce((select payment_iqd from official),0)+gp.amount else lp.total_paid_iqd end,
    'general_paid_iqd',gp.amount,
    'gross_remaining_iqd',coalesce((select balance_iqd from official),s.local_gross_remaining_iqd),
    'open_debt_count',s.open_debt_count,'open_debts',o.items,'complete',true,
    'general_payment_policy','account_credit_no_debt_mutation'
  )
  from summary s cross join local_paid lp cross join general_paid gp cross join open_debts o
$function$;

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_result jsonb;
  v_admin_id uuid := auth.uid();
  v_projection jsonb := private.get_daftar_projection_summary();
  v_use_daftar_projection boolean := v_projection <> '{}'::jsonb;
begin
  if private."current_role"() is distinct from 'admin' then
    raise insufficient_privilege using message = 'admin role required';
  end if;

  with official_customer_ids as materialized (
    select x.customer_id
    from private.get_daftar_official_customer_totals(null) x
  ),
  visible_customer_ids as materialized (
    select p.id
    from public.profiles p
    where p.admin_id = v_admin_id
      and p.role = 'customer'
      and (
        not v_use_daftar_projection
        or exists (
          select 1
          from official_customer_ids o
          where o.customer_id = p.id
        )
      )
  ),
  general_paid as materialized (
    select coalesce(
      sum(private.customer_unmirrored_general_paid_total(visible.id)),
      0
    )::numeric as amount
    from visible_customer_ids visible
  ),
  recent_rows as materialized (
    select
      d.created_at,
      d.id::text as sort_id,
      jsonb_build_object(
        'id', d.id,
        'event_type', 'debt',
        'amount', d.amount,
        'currency', coalesce(d.currency, 'IQD'),
        'created_at', d.created_at,
        'customer_id', d.customer_id,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.debts d
    join visible_customer_ids visible on visible.id = d.customer_id
    join public.profiles customer on customer.id = d.customer_id
    left join public.profiles creator on creator.id = d.created_by
    where d.is_deleted = false
      and d.created_at >= now() - interval '24 hours'
      and d.created_at <= now()

    union all

    select
      pay.created_at,
      pay.id::text as sort_id,
      jsonb_build_object(
        'id', pay.id,
        'event_type', 'payment',
        'payment_scope', 'debt',
        'amount', pay.amount,
        'currency', coalesce(d.currency, 'IQD'),
        'created_at', pay.created_at,
        'customer_id', d.customer_id,
        'debt_id', pay.debt_id,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.payments pay
    join public.debts d on d.id = pay.debt_id
    join visible_customer_ids visible on visible.id = d.customer_id
    join public.profiles customer on customer.id = d.customer_id
    left join public.profiles creator on creator.id = pay.created_by
    where d.is_deleted = false
      and pay.created_at >= now() - interval '24 hours'
      and pay.created_at <= now()

    union all

    select
      g.created_at,
      g.id::text as sort_id,
      jsonb_build_object(
        'id', g.id,
        'event_type', 'payment',
        'payment_scope', 'general',
        'amount', g.amount,
        'currency', 'IQD',
        'created_at', g.created_at,
        'customer_id', g.customer_id,
        'debt_id', null,
        'customer', jsonb_build_object(
          'id', customer.id,
          'name', customer.name,
          'role', customer.role,
          'created_at', customer.created_at,
          'updated_at', customer.updated_at
        ),
        'created_by', case when creator.id is null then null else jsonb_build_object(
          'id', creator.id,
          'name', creator.name,
          'role', creator.role,
          'created_at', creator.created_at,
          'updated_at', creator.updated_at
        ) end
      ) as payload
    from public.customer_general_payments g
    join visible_customer_ids visible on visible.id = g.customer_id
    join public.profiles customer on customer.id = g.customer_id
    left join public.profiles creator on creator.id = g.created_by
    where g.created_at >= now() - interval '24 hours'
      and g.created_at <= now()
  ),
  limited_recent_rows as materialized (
    select r.created_at, r.sort_id, r.payload
    from recent_rows r
    order by r.created_at desc, r.sort_id desc
    limit 250
  )
  select jsonb_build_object(
    'total_customers', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_customers')::integer, 0)
      else (select count(*) from visible_customer_ids)
    end,
    'pending_requests', (
      select count(*)
      from public.profiles p
      where p.admin_id = v_admin_id
        and p.role = 'customer'
        and p.approved = false
    ),
    'total_debt', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_iqd')::numeric, 0)
      else coalesce((
        select sum(d.amount)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ), 0)
    end,
    'total_remaining', greatest(
      case
        when v_use_daftar_projection
          then coalesce((v_projection->>'official_balance_iqd')::numeric, 0)
        else coalesce((
          select sum(d.remaining)
          from public.debts d
          join visible_customer_ids visible on visible.id = d.customer_id
          where d.is_deleted = false
            and upper(coalesce(d.currency, 'IQD')) <> 'USD'
        ), 0)
      end - (select amount from general_paid),
      0
    ),
    'total_payments', (
      case
        when v_use_daftar_projection
          then coalesce((v_projection->>'official_total_payment_iqd')::numeric, 0)
        else coalesce((
          select sum(pay.amount)
          from public.payments pay
          join public.debts d on d.id = pay.debt_id
          join visible_customer_ids visible on visible.id = d.customer_id
          where d.is_deleted = false
            and upper(coalesce(d.currency, 'IQD')) <> 'USD'
        ), 0)
      end + (select amount from general_paid)
    ),
    'total_debt_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_loan_usd')::numeric, 0)
      else coalesce((
        select sum(d.amount)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'total_remaining_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_balance_usd')::numeric, 0)
      else coalesce((
        select sum(d.remaining)
        from public.debts d
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'total_payments_usd', case
      when v_use_daftar_projection
        then coalesce((v_projection->>'official_total_payment_usd')::numeric, 0)
      else coalesce((
        select sum(pay.amount)
        from public.payments pay
        join public.debts d on d.id = pay.debt_id
        join visible_customer_ids visible on visible.id = d.customer_id
        where d.is_deleted = false
          and upper(coalesce(d.currency, 'IQD')) = 'USD'
      ), 0)
    end,
    'pending_debts', (
      select count(*)
      from visible_customer_ids visible
      cross join lateral private.get_customer_virtual_debt_balances(visible.id) v
      where v.effective_remaining > 0
    ),
    'recent_activity', coalesce((
      select jsonb_agg(r.payload order by r.created_at desc, r.sort_id desc)
      from limited_recent_rows r
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_customer_payment_service(p_actor_id uuid, p_customer_id uuid, p_amount numeric, p_note text DEFAULT ''::text, p_reference_kind text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
  v_admin_id uuid;
  v_customer_admin_id uuid;
  v_can_record boolean := false;
  v_gross_remaining numeric := 0;
  v_general_paid_before numeric := 0;
  v_effective_before numeric := 0;
  v_effective_after numeric := 0;
  v_market_name text := '';
  v_general public.customer_general_payments%rowtype;
begin
  if p_actor_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end,
         case
           when p.role = 'admin' then true
           when p.role = 'employee' then coalesce(p.can_record_payments, false)
           else false
         end
    into v_role, v_admin_id, v_can_record
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (
     tenant.is_system_owner
     or tenant.subscription_end is null
     or tenant.subscription_end >= now()
   )
  where p.id = p_actor_id
    and p.role in ('admin', 'employee')
    and p.active = true
    and p.approved = true;

  if v_role is null or v_admin_id is null or not v_can_record then
    raise exception 'payment_forbidden' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select customer.admin_id
    into v_customer_admin_id
  from public.profiles customer
  where customer.id = p_customer_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
  for update;

  if v_customer_admin_id is null or v_customer_admin_id <> v_admin_id then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  select coalesce(
    (
      select o.balance_iqd
      from private.get_daftar_official_customer_totals(p_customer_id) o
      limit 1
    ),
    (
      select coalesce(sum(d.remaining), 0)::numeric
      from public.debts d
      where d.customer_id = p_customer_id
        and d.is_deleted = false
        and d.remaining > 0
        and upper(coalesce(d.currency, 'IQD')) <> 'USD'
    ),
    0
  )
  into v_gross_remaining;

  select private.customer_unmirrored_general_paid_total(p_customer_id)
    into v_general_paid_before;

  v_effective_before := greatest(v_gross_remaining - v_general_paid_before, 0);

  if v_effective_before <= 0 then
    raise exception 'customer_balance_already_paid' using errcode = '22023';
  end if;

  if p_amount > v_effective_before + 0.0001 then
    raise exception 'payment_exceeds_customer_balance' using errcode = '22023';
  end if;

  insert into public.customer_general_payments(
    admin_id, customer_id, amount, note, created_by, reference_kind, reference_id
  ) values (
    v_admin_id, p_customer_id, p_amount, coalesce(p_note, ''),
    p_actor_id, p_reference_kind, p_reference_id
  )
  returning * into v_general;

  v_effective_after := greatest(v_effective_before - p_amount, 0);

  select coalesce(p.market_name, '')
    into v_market_name
  from public.profiles p
  where p.id = v_admin_id;

  perform public.enqueue_customer_push_event_service(
    v_admin_id,
    p_customer_id,
    'payment_created',
    v_general.id,
    'payment_created:' || v_general.id::text,
    jsonb_build_object(
      'amount', v_general.amount,
      'currency', 'IQD',
      'remaining_iqd', v_effective_after,
      'market_name', v_market_name,
      'occurred_at', coalesce(v_general.created_at, now()),
      'payment_scope', 'general'
    )
  );

  return jsonb_build_object(
    'id', v_general.id,
    'customer_id', p_customer_id,
    'payment_scope', 'general',
    'amount', v_general.amount,
    'note', v_general.note,
    'created_by', v_general.created_by,
    'created_at', v_general.created_at,
    'allocation_count', 0,
    'remaining', v_effective_after,
    'gross_remaining', v_gross_remaining,
    'general_paid_total', v_general_paid_before + p_amount,
    'payments', '[]'::jsonb
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_payment_service(p_actor_id uuid, p_debt_id uuid, p_amount numeric, p_note text DEFAULT ''::text, p_reference_kind text DEFAULT NULL::text, p_reference_id uuid DEFAULT NULL::uuid)
 RETURNS payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
  v_admin_id uuid;
  v_can_record boolean := false;
  v_customer_id uuid;
  v_debt public.debts%rowtype;
  v_payment public.payments%rowtype;
  v_gross_remaining numeric := 0;
  v_general_paid numeric := 0;
  v_effective_before numeric := 0;
  v_new_remaining numeric;
  v_total_remaining numeric := 0;
  v_market_name text := '';
  v_currency text := 'IQD';
  v_display_amount numeric := 0;
begin
  if p_actor_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select p.role,
         case when p.role = 'admin' then p.id else p.admin_id end,
         case
           when p.role = 'admin' then true
           when p.role = 'employee' then coalesce(p.can_record_payments, false)
           else false
         end
    into v_role, v_admin_id, v_can_record
  from public.profiles p
  join public.profiles tenant
    on tenant.id = case when p.role = 'admin' then p.id else p.admin_id end
   and tenant.role = 'admin'
   and tenant.active = true
   and tenant.approved = true
   and (
     tenant.is_system_owner
     or tenant.subscription_end is null
     or tenant.subscription_end >= now()
   )
  where p.id = p_actor_id
    and p.role in ('admin', 'employee')
    and p.active = true
    and p.approved = true;

  if v_role is null or v_admin_id is null or not v_can_record then
    raise exception 'payment_forbidden' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  select d.customer_id
    into v_customer_id
  from public.debts d
  join public.profiles customer on customer.id = d.customer_id
  where d.id = p_debt_id
    and d.is_deleted = false
    and customer.role = 'customer'
    and customer.admin_id = v_admin_id;

  if v_customer_id is null then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  perform 1
  from public.profiles customer
  where customer.id = v_customer_id
    and customer.role = 'customer'
    and customer.active = true
    and customer.approved = true
  for update;

  if not found then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  select d.*
    into v_debt
  from public.debts d
  where d.id = p_debt_id
    and d.customer_id = v_customer_id
    and d.is_deleted = false
  for update;

  if not found then
    raise exception 'debt_not_found_or_forbidden' using errcode = '42501';
  end if;

  if v_debt.remaining <= 0 then
    raise exception 'debt_already_paid' using errcode = '22023';
  end if;

  if p_amount > v_debt.remaining + 0.0001 then
    raise exception 'payment_exceeds_debt_balance' using errcode = '22023';
  end if;

  if upper(coalesce(v_debt.currency, 'IQD')) <> 'USD' then
    select coalesce(
      (
        select o.balance_iqd
        from private.get_daftar_official_customer_totals(v_customer_id) o
        limit 1
      ),
      (
        select coalesce(sum(d.remaining), 0)::numeric
        from public.debts d
        where d.customer_id = v_customer_id
          and d.is_deleted = false
          and d.remaining > 0
          and upper(coalesce(d.currency, 'IQD')) <> 'USD'
      ),
      0
    )
    into v_gross_remaining;

    select private.customer_unmirrored_general_paid_total(v_customer_id)
      into v_general_paid;

    v_effective_before := greatest(v_gross_remaining - v_general_paid, 0);

    if p_amount > v_effective_before + 0.0001 then
      raise exception 'payment_exceeds_customer_balance' using errcode = '22023';
    end if;
  end if;

  perform set_config('zhirox.payment_rpc', 'on', true);

  v_new_remaining := greatest(v_debt.remaining - p_amount, 0);

  insert into public.payments(
    debt_id, amount, note, created_by, reference_kind, reference_id
  ) values (
    p_debt_id, p_amount, coalesce(p_note, ''),
    p_actor_id, p_reference_kind, p_reference_id
  )
  returning * into v_payment;

  update public.debts
  set remaining = v_new_remaining,
      status = case when v_new_remaining <= 0 then 'paid' else 'partial' end,
      updated_at = now()
  where id = p_debt_id;

  v_total_remaining := public.get_customer_effective_balance(v_customer_id);

  select coalesce(p.market_name, '')
    into v_market_name
  from public.profiles p
  where p.id = v_admin_id;

  if upper(coalesce(v_debt.currency, 'IQD')) = 'USD'
     and coalesce(v_debt.dollar_rate, 0) > 0 then
    v_currency := 'USD';
    v_display_amount := round((v_payment.amount / v_debt.dollar_rate)::numeric, 2);
  elsif upper(coalesce(v_debt.currency, 'IQD')) = 'USD' then
    v_currency := 'USD';
    v_display_amount := v_payment.amount;
  else
    v_currency := 'IQD';
    v_display_amount := v_payment.amount;
  end if;

  perform public.enqueue_customer_push_event_service(
    v_admin_id,
    v_customer_id,
    'payment_created',
    v_payment.id,
    'payment_created:' || v_payment.id::text,
    jsonb_build_object(
      'amount', v_display_amount,
      'currency', v_currency,
      'remaining_iqd', v_total_remaining,
      'market_name', v_market_name,
      'occurred_at', coalesce(v_payment.created_at, now()),
      'payment_scope', 'debt'
    )
  );

  return v_payment;
end;
$function$;