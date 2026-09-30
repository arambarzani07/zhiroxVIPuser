create or replace function private.enforce_tenant_profile_plan_limits()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_limit bigint;
  v_count bigint;
  v_key text;
begin
  if new.is_system_owner=true or new.admin_id is null or new.active<>true then return new; end if;
  if new.role='employee' then v_key:='staff_limit';
  elsif new.role='customer' then v_key:='customer_limit';
  else return new; end if;

  v_limit:=private.get_effective_tenant_limit(new.admin_id,v_key);
  if v_limit=0 then return new; end if;

  select count(*) into v_count
  from public.profiles p
  where p.admin_id=new.admin_id
    and p.role=new.role
    and p.active=true
    and p.id<>new.id;

  if v_count>=v_limit then
    if new.role='employee' then
      raise exception 'tenant_staff_limit_reached' using errcode='P0001',detail=format('limit=%s,current=%s',v_limit,v_count);
    else
      raise exception 'tenant_customer_limit_reached' using errcode='P0001',detail=format('limit=%s,current=%s',v_limit,v_count);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_tenant_profile_plan_limits on public.profiles;
create trigger enforce_tenant_profile_plan_limits
before insert or update of role,admin_id,active on public.profiles
for each row execute function private.enforce_tenant_profile_plan_limits();
