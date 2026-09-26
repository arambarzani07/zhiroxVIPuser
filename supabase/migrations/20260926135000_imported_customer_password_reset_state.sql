alter table public.profiles
  add column if not exists password_reset_required boolean not null default false;

create or replace function private.guard_profile_password_reset_required()
returns trigger
language plpgsql
set search_path = 'pg_catalog','public','private','auth'
as $function$
begin
  if auth.role() = 'service_role'
     or current_user in ('postgres','supabase_admin','service_role') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.password_reset_required := false;
    return new;
  end if;

  if new.password_reset_required is distinct from old.password_reset_required then
    raise exception 'protected_password_reset_required';
  end if;
  return new;
end;
$function$;

drop trigger if exists profiles_guard_password_reset_required on public.profiles;
create trigger profiles_guard_password_reset_required
before insert or update on public.profiles
for each row execute function private.guard_profile_password_reset_required();

revoke all on function private.guard_profile_password_reset_required() from public, anon, authenticated;
grant execute on function private.guard_profile_password_reset_required() to service_role;
