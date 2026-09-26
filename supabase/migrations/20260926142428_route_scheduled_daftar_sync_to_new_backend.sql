-- Route scheduled sync requests to the active ZHIROX backend.
CREATE OR REPLACE FUNCTION private.dispatch_daftar_sync_sources()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_secret text;
  v_inbound_count integer := 0;
  v_outbound_count integer := 0;
  v_skipped_count integer := 0;
begin
  for r in
    select
      s.id,
      s.legacy_user_id,
      s.source_fingerprint,
      s.trigger_secret_hash,
      s.trigger_secret_vault_name,
      s.sync_mode,
      s.inbound_sync_enabled,
      s.outbound_sync_enabled,
      s.outbound_write_contract_status
    from public.daftar_sync_sources s
    where s.enabled = true
      and nullif(s.trigger_secret_vault_name, '') is not null
    order by s.created_at
  loop
    v_secret := null;

    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = r.trigger_secret_vault_name
    limit 1;

    if v_secret is null
       or encode(extensions.digest(v_secret, 'sha256'), 'hex')
          is distinct from r.trigger_secret_hash then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    if r.sync_mode = 'mirror'
       or (r.sync_mode = 'zhirox_primary' and r.inbound_sync_enabled = true) then
      perform net.http_post(
        url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-sync-gateway',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'x-daftar-sync-secret',v_secret
        ),
        body := jsonb_build_object('source_id',r.id),
        timeout_milliseconds := 120000
      );
      v_inbound_count := v_inbound_count + 1;
    end if;

    if r.sync_mode = 'zhirox_primary'
       and r.outbound_sync_enabled = true
       and r.outbound_write_contract_status = 'verified' then
      perform net.http_post(
        url := 'https://madoflmbretqghqbqaak.supabase.co/functions/v1/daftar-outbound-sync',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'x-daftar-sync-secret',v_secret
        ),
        body := jsonb_build_object(
          'source_id',r.id,
          'action','drain'
        ),
        timeout_milliseconds := 120000
      );
      v_outbound_count := v_outbound_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'inbound_dispatched',v_inbound_count,
    'outbound_dispatched',v_outbound_count,
    'skipped_missing_or_invalid_secret',v_skipped_count
  );
end;
$function$;
