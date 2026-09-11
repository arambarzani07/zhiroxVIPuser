alter table public.profiles
  add column if not exists subscription_plan text;

update public.profiles
set subscription_plan = 'custom'
where role = 'admin'
  and is_system_owner = false
  and subscription_plan is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_subscription_plan_check'
  ) then
    alter table public.profiles
      add constraint profiles_subscription_plan_check
      check (
        (role = 'admin' and subscription_plan in (
          'monthly',
          'quarterly',
          'semiannual',
          'annual',
          'custom'
        ))
        or (role <> 'admin' and subscription_plan is null)
        or is_system_owner = true
      );
  end if;
end
$$;
