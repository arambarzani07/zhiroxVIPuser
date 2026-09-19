begin;

do $$
begin
  if has_function_privilege('anon', 'public.get_my_daftar_sync_dashboard()', 'execute') then
    raise exception 'anonymous users must not read the sync dashboard';
  end if;
  if not has_function_privilege('authenticated', 'public.get_my_daftar_sync_dashboard()', 'execute') then
    raise exception 'authenticated admins must be able to read their sync dashboard';
  end if;
  if has_function_privilege('anon', 'public.request_my_daftar_sync()', 'execute') then
    raise exception 'anonymous users must not trigger sync';
  end if;
  if not has_function_privilege('authenticated', 'public.request_my_daftar_sync()', 'execute') then
    raise exception 'authenticated tenant admins must be able to request their sync';
  end if;
end;
$$;

rollback;
