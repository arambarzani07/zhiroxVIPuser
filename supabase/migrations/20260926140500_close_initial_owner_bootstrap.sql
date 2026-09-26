-- Close the one-time System Owner bootstrap after production owner creation.
revoke execute on function public.claim_initial_system_owner(text,text)
  from public, anon, authenticated;
grant execute on function public.claim_initial_system_owner(text,text)
  to service_role;
