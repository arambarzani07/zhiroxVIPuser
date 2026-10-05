-- The first A11 prototype finalizer used source identity only. The v2 flow is
-- fenced with a per-attempt random token, so revoke and remove the prototype
-- entry points before enabling the provider in production.

revoke all on function public.a11_video_complete_service(text,uuid,text,bigint,integer,text,jsonb)
  from public, anon, authenticated;
revoke all on function private.a11_complete_video(text,uuid,text,bigint,integer,text,jsonb)
  from public, anon, authenticated;

drop function if exists public.a11_video_complete_service(text,uuid,text,bigint,integer,text,jsonb);
drop function if exists private.a11_complete_video(text,uuid,text,bigint,integer,text,jsonb);
