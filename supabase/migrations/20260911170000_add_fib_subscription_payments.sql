create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  plan text not null check (plan in ('monthly', 'quarterly', 'semiannual', 'annual')),
  amount_iqd bigint not null check (amount_iqd > 0),
  fib_payment_id text unique,
  status text not null default 'pending' check (status in ('pending', 'paid', 'declined', 'expired', 'cancelled')),
  readable_code text,
  valid_until timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists subscription_payments_admin_created_idx
  on public.subscription_payments(admin_id, created_at desc);

alter table public.subscription_payments enable row level security;

drop policy if exists subscription_payments_select_own on public.subscription_payments;
create policy subscription_payments_select_own
  on public.subscription_payments for select
  to authenticated
  using (
    admin_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.is_system_owner = true
    )
  );

create or replace function public.activate_fib_subscription_payment(
  p_local_payment_id uuid,
  p_fib_payment_id text
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.subscription_payments%rowtype;
  v_days integer;
begin
  update public.subscription_payments
  set status = 'paid', paid_at = coalesce(paid_at, now()), updated_at = now()
  where id = p_local_payment_id
    and fib_payment_id = p_fib_payment_id
    and status <> 'paid'
  returning * into v_payment;

  if not found then
    return exists (
      select 1 from public.subscription_payments
      where id = p_local_payment_id
        and fib_payment_id = p_fib_payment_id
        and status = 'paid'
    );
  end if;

  v_days := case v_payment.plan
    when 'monthly' then 30
    when 'quarterly' then 90
    when 'semiannual' then 180
    when 'annual' then 365
  end;

  update public.profiles
  set subscription_plan = v_payment.plan,
      subscription_end = greatest(coalesce(subscription_end, now()), now())
        + make_interval(days => v_days),
      updated_at = now()
  where id = v_payment.admin_id and role = 'admin';

  return found;
end;
$$;

revoke all on function public.activate_fib_subscription_payment(uuid, text) from public;
revoke all on function public.activate_fib_subscription_payment(uuid, text) from anon;
revoke all on function public.activate_fib_subscription_payment(uuid, text) from authenticated;
grant execute on function public.activate_fib_subscription_payment(uuid, text) to service_role;
