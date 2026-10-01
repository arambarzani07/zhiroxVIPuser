create or replace function public.get_telegram_customer_snapshot_service(p_chat_id text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_customer public.profiles%rowtype;
  v_market public.profiles%rowtype;
  v_balance numeric := 0;
  v_last_payment jsonb := null;
  v_recent jsonb := '[]'::jsonb;
  v_risk jsonb := null;
begin
  if nullif(btrim(p_chat_id), '') is null then return null; end if;

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

  select to_jsonb(x) into v_last_payment
  from (
    select amount, created_at, note, payment_scope
    from (
      select p.amount, p.created_at, p.note, 'debt'::text as payment_scope
      from public.payments p
      join public.debts d on d.id = p.debt_id
      where d.customer_id = v_customer.id and d.is_deleted = false
      union all
      select g.amount, g.created_at, g.note, 'general'::text as payment_scope
      from public.customer_general_payments g
      where g.customer_id = v_customer.id
    ) q
    order by created_at desc
    limit 1
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at desc, x.kind, x.id), '[]'::jsonb)
  into v_recent
  from (
    select * from (
      select d.id, 'debt'::text as kind, d.amount, coalesce(d.custom_date,d.created_at) as occurred_at, d.description as note
      from public.debts d
      where d.customer_id = v_customer.id and d.is_deleted = false
      union all
      select p.id, 'payment'::text, p.amount, p.created_at, p.note
      from public.payments p
      join public.debts d on d.id = p.debt_id
      where d.customer_id = v_customer.id and d.is_deleted = false
      union all
      select g.id, 'payment'::text, g.amount, g.created_at, g.note
      from public.customer_general_payments g
      where g.customer_id = v_customer.id
    ) all_rows
    order by occurred_at desc, kind, id
    limit 10
  ) x;

  select jsonb_build_object('score', r.score, 'level', r.level, 'reasons', r.reasons)
  into v_risk
  from public.customer_risk_scores r
  where r.customer_id = v_customer.id
  limit 1;

  return jsonb_build_object(
    'customer_id', v_customer.id,
    'customer_name', v_customer.name,
    'market_id', v_market.id,
    'market_name', coalesce(nullif(v_market.market_name,''), 'ZHIROX'),
    'remaining_iqd', coalesce(v_balance,0),
    'last_payment', v_last_payment,
    'recent', v_recent,
    'risk', v_risk,
    'as_of', now()
  );
end;
$$;

create or replace function public.create_telegram_customer_read_link_service(
  p_chat_id text,
  p_token_hash text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_customer_id uuid;
  v_admin_id uuid;
begin
  if nullif(btrim(p_chat_id), '') is null
     or p_token_hash !~ '^[a-f0-9]{64}$'
     or p_expires_at is null
     or p_expires_at <= now()
     or p_expires_at > now() + interval '30 minutes' then
    raise exception 'invalid_input';
  end if;

  select p.id, p.admin_id into v_customer_id, v_admin_id
  from private.telegram_credentials tc
  join public.profiles p on p.id = tc.user_id
  join public.profiles a on a.id = p.admin_id
  where tc.chat_id = p_chat_id
    and p.role = 'customer'
    and p.active = true
    and p.approved = true
    and a.role = 'admin'
    and a.active = true
    and a.approved = true
    and (a.is_system_owner or a.subscription_end is null or a.subscription_end >= now())
  limit 1;

  if v_customer_id is null or v_admin_id is null then raise exception 'telegram_not_connected'; end if;

  delete from public.customer_read_links
  where customer_id = v_customer_id and expires_at < now();

  insert into public.customer_read_links(customer_id, admin_id, token_hash, expires_at)
  values (v_customer_id, v_admin_id, p_token_hash, p_expires_at);

  return jsonb_build_object('customer_id', v_customer_id, 'market_id', v_admin_id, 'expires_at', p_expires_at);
end;
$$;

revoke all on function public.get_telegram_customer_snapshot_service(text) from public, anon, authenticated;
revoke all on function public.create_telegram_customer_read_link_service(text,text,timestamptz) from public, anon, authenticated;
grant execute on function public.get_telegram_customer_snapshot_service(text) to service_role;
grant execute on function public.create_telegram_customer_read_link_service(text,text,timestamptz) to service_role;
