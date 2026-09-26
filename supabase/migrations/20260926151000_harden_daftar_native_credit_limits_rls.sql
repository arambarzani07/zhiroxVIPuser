
do $$
begin
  if not exists (
    select 1
    from pg_policy p
    where p.polrelid = 'public.daftar_native_credit_limits'::regclass
      and p.polname = 'deny_direct_client_access'
  ) then
    create policy deny_direct_client_access
      on public.daftar_native_credit_limits
      for all
      to anon, authenticated
      using (false)
      with check (false);
  end if;
end $$;
