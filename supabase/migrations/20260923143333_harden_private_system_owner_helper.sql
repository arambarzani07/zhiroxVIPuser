-- Harden the private System Owner authorization helper.
-- All public callers that depend on this helper are SECURITY DEFINER functions
-- owned by postgres, so client roles do not need direct EXECUTE on the helper.

revoke execute on function private.require_system_owner()
  from public, anon, authenticated;
