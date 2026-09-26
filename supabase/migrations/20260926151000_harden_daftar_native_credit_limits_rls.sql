do $$
begin
  if to_regclass('public.daftar_native_credit_limits') is not null
     and not exists (
       select 1
       from pg_policy p
       where p.polrelid = to_regclass('public.daftar_native_credit_limits')
         and p.polname = 'deny_direct_client_access'
     ) then
    execute 'create policy deny_direct_client_access
      on public.daftar_native_credit_limits
      for all
      to anon, authenticated
      using (false)
      with check (false)';
  end if;
end $$;
