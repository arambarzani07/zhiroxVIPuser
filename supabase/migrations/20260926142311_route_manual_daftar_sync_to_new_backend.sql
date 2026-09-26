-- Route manual sync requests to the active ZHIROX backend.
create or replace function public.request_my_daftar_sync()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_source_id uuid;
  v_vault_secret_name text;
  v_secret text;
  v_inbound_enabled boolean := false;
  v_outbound_enabled boolean := false;
  v_inbound_request_id bigint;
  v_outbound_request_id bigint;
begin
  if v_uid is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select s.id, s.trigger_secret_vault_name,
         coalesce(s.inbound_sync_enabled, false),
         coalesce(s.outbound_sync_enabled, false)
    into v_source_id, v_vault_secret_name, v_inbound_enabled, v_outbound_enabled
  from public.daftar_sync_sources s
  where s.admin_id = v_uid
    and s.enabled = true
    and s.sync_mode = 'zhirox_primary'
  order by s.created_at
  limit 1;

  if v_source_id is null then
    raise exception 'sync_source_not_available' using errcode = '42501';
  end if;

  if nullif(v_vault_secret_name, '') is null then
    raise exception 'sync_secret_not_configured';
  end if;

  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = v_vault_secret_name
  limit 1;

  if v_secret is null then
    raise exception 'sync_secret_not_configured';
  end if;

  if v_inbound_enabled then
    select net.http_post(
      url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-sync-gateway',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'x-daftar-sync-secret',v_secret
      ),
      body := jsonb_build_object('source_id',v_source_id),
      timeout_milliseconds := 120000
    ) into v_inbound_request_id;
  end if;

  if v_outbound_enabled then
    select net.http_post(
      url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-outbound-sync',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'x-daftar-sync-secret',v_secret
      ),
      body := jsonb_build_object('source_id',v_source_id,'action','drain'),
      timeout_milliseconds := 120000
    ) into v_outbound_request_id;
  end if;

  return jsonb_build_object(
    'accepted',true,
    'source_id',v_source_id,
    'inbound_request_id',v_inbound_request_id,
    'outbound_request_id',v_outbound_request_id
  );
end;
$function$;
