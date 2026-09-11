begin;

do $$
begin
  if has_function_privilege(
    'authenticated',
    'public.get_system_owner_admins_page(integer,integer)',
    'execute'
  ) then raise exception 'Admin list RPC is still exposed'; end if;

  if has_function_privilege(
    'authenticated',
    'public.renew_system_owner_admin_subscription(uuid,integer)',
    'execute'
  ) then raise exception 'Subscription RPC is still exposed'; end if;

  if has_function_privilege(
    'authenticated',
    'public.record_payment(uuid,numeric,text,text,uuid)',
    'execute'
  ) then raise exception 'Legacy payment RPC is still exposed'; end if;

  if has_function_privilege(
    'authenticated',
    'public.record_payment_service(uuid,uuid,numeric,text,text,uuid)',
    'execute'
  ) then raise exception 'Service payment RPC is exposed to authenticated'; end if;
end
$$;

create temporary table payment_service_fixture as
select case when c.role = 'admin' then c.id else c.admin_id end actor_id,
       d.id debt_id
from public.debts d
join public.profiles c on c.id = d.customer_id
join public.profiles a
  on a.id = case when c.role = 'admin' then c.id else c.admin_id end
where d.remaining > 0
  and a.active
  and a.approved
  and (a.subscription_end is null or a.subscription_end >= now())
limit 1;

do $$
begin
  if not exists (select 1 from payment_service_fixture) then
    raise exception 'Regression fixture missing: no open debt';
  end if;
end
$$;

grant select on payment_service_fixture to service_role;
set local role service_role;
select (public.record_payment_service(
  (select actor_id from payment_service_fixture),
  (select debt_id from payment_service_fixture),
  1,
  'security gateway regression',
  null,
  null
)).id is not null as payment_created;

rollback;
select 'privileged RPC gateway regression passed' as result;
