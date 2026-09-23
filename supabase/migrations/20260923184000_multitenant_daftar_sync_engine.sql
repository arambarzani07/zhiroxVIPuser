-- Multi-tenant Daftar sync engine.
-- Keeps protected account 28 on its dedicated guardian/cron while enabling generic tenant sources.

alter table public.daftar_sync_sources
  add column if not exists trigger_secret_vault_name text;

update public.daftar_sync_sources
set trigger_secret_vault_name = 'daftar_sync_account_28_trigger'
where legacy_user_id = 28
  and source_fingerprint = 'daftar-live-account-28-v1'
  and trigger_secret_vault_name is null;

create unique index if not exists daftar_sync_one_primary_outbound_per_admin
on public.daftar_sync_sources(admin_id)
where enabled = true
  and sync_mode = 'zhirox_primary'
  and outbound_sync_enabled = true;

create or replace function public.enqueue_daftar_outbound_mutation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_admin_id uuid;
  v_entity_kind text;
  v_entity_id uuid;
  v_operation text := case tg_op when 'INSERT' then 'create' when 'UPDATE' then 'update' else 'delete' end;
  v_source_id uuid;
  v_source_fingerprint text;
  v_remote_id text;
  v_payload jsonb;
  v_customer_id uuid;
  v_currency text;
begin
  if coalesce(current_setting('zhirox.daftar_inbound', true), '') = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_table_name = 'profiles' then
    if coalesce(v_row->>'role', '') <> 'customer'
       or nullif(v_row->>'admin_id', '') is null then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;
    if tg_op = 'UPDATE'
       and (new.name, new.phone) is not distinct from (old.name, old.phone) then
      return new;
    end if;
    v_admin_id := (v_row->>'admin_id')::uuid;
    v_entity_kind := 'customer';
    v_entity_id := (v_row->>'id')::uuid;
    v_payload := jsonb_build_object(
      'id', v_row->>'id',
      'name', coalesce(v_row->>'name', ''),
      'phone', coalesce(v_row->>'phone', ''),
      'created_at', v_row->>'created_at',
      'updated_at', coalesce(v_row->>'updated_at', v_row->>'created_at')
    );

  elsif tg_table_name = 'debts' then
    v_customer_id := (v_row->>'customer_id')::uuid;
    select p.admin_id into v_admin_id
    from public.profiles p
    where p.id = v_customer_id and p.role = 'customer';

    if v_admin_id is null then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    if tg_op = 'UPDATE' then
      if coalesce(old.is_deleted, false) = false
         and coalesce(new.is_deleted, false) = true then
        v_operation := 'delete';
      elsif coalesce(old.is_deleted, false) = true
            and coalesce(new.is_deleted, false) = false then
        v_operation := 'create';
      elsif (new.customer_id, new.amount, new.currency, new.description, new.custom_date)
            is not distinct from
            (old.customer_id, old.amount, old.currency, old.description, old.custom_date) then
        return new;
      else
        v_operation := 'update';
      end if;
    end if;

    v_entity_kind := 'debt';
    v_entity_id := (v_row->>'id')::uuid;
    v_payload := jsonb_build_object(
      'id', v_row->>'id',
      'customer_id', v_row->>'customer_id',
      'amount', v_row->'amount',
      'currency', coalesce(v_row->>'currency', 'IQD'),
      'description', coalesce(v_row->>'description', ''),
      'transaction_date', coalesce(v_row->>'custom_date', v_row->>'created_at'),
      'created_at', v_row->>'created_at',
      'updated_at', coalesce(v_row->>'updated_at', v_row->>'created_at'),
      'is_deleted', coalesce((v_row->>'is_deleted')::boolean, false)
    );

  elsif tg_table_name = 'payments' then
    select p.admin_id, d.customer_id, d.currency
      into v_admin_id, v_customer_id, v_currency
    from public.debts d
    join public.profiles p on p.id = d.customer_id and p.role = 'customer'
    where d.id = (v_row->>'debt_id')::uuid;

    if v_admin_id is null then
      if tg_op = 'DELETE' then return old; end if;
      return new;
    end if;

    if tg_op = 'UPDATE'
       and (new.debt_id, new.amount, new.note)
           is not distinct from (old.debt_id, old.amount, old.note) then
      return new;
    end if;

    v_entity_kind := 'payment';
    v_entity_id := (v_row->>'id')::uuid;
    v_payload := jsonb_build_object(
      'id', v_row->>'id',
      'debt_id', v_row->>'debt_id',
      'customer_id', v_customer_id,
      'amount', v_row->'amount',
      'currency', coalesce(v_currency, 'IQD'),
      'note', coalesce(v_row->>'note', ''),
      'transaction_date', v_row->>'created_at',
      'created_at', v_row->>'created_at'
    );
  else
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select s.id, s.source_fingerprint
    into v_source_id, v_source_fingerprint
  from public.daftar_sync_sources s
  where s.admin_id = v_admin_id
    and s.enabled = true
    and s.sync_mode = 'zhirox_primary'
    and s.outbound_sync_enabled = true
    and s.outbound_write_contract_status = 'verified'
  order by s.created_at
  limit 1;

  if v_source_id is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  select split_part(l.source_id, ':', 1) into v_remote_id
  from public.legacy_import_links l
  where l.admin_id = v_admin_id
    and l.source_fingerprint = v_source_fingerprint
    and l.entity_kind = v_entity_kind
    and l.target_id = v_entity_id
  order by l.created_at desc
  limit 1;

  insert into public.daftar_outbound_events(
    sync_source_id, entity_kind, entity_id, operation, idempotency_key,
    payload_snapshot, remote_id_snapshot, next_attempt_at
  ) values (
    v_source_id, v_entity_kind, v_entity_id, v_operation,
    'zhirox:' || v_source_id::text || ':' || v_entity_kind || ':' ||
      v_entity_id::text || ':' || v_operation || ':' ||
      md5(coalesce(v_payload::text, '{}')),
    coalesce(v_payload, '{}'::jsonb),
    v_remote_id,
    now() + interval '5 seconds'
  )
  on conflict (idempotency_key) do update
  set payload_snapshot = excluded.payload_snapshot,
      remote_id_snapshot = coalesce(
        excluded.remote_id_snapshot,
        public.daftar_outbound_events.remote_id_snapshot
      ),
      status = case
        when public.daftar_outbound_events.status in ('sent', 'skipped')
          then public.daftar_outbound_events.status
        else 'pending'
      end,
      next_attempt_at = least(
        public.daftar_outbound_events.next_attempt_at,
        excluded.next_attempt_at
      ),
      updated_at = now();

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

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
      url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
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
      url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-outbound-sync',
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

create or replace function private.dispatch_daftar_sync_sources()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  r record;
  v_secret text;
  v_inbound_count integer := 0;
  v_outbound_count integer := 0;
  v_skipped_count integer := 0;
begin
  for r in
    select s.id,s.legacy_user_id,s.source_fingerprint,s.trigger_secret_hash,
           s.trigger_secret_vault_name,s.sync_mode,s.inbound_sync_enabled,
           s.outbound_sync_enabled,s.outbound_write_contract_status
    from public.daftar_sync_sources s
    where s.enabled = true
      and nullif(s.trigger_secret_vault_name,'') is not null
      and not (
        s.legacy_user_id = 28
        and s.source_fingerprint = 'daftar-live-account-28-v1'
      )
    order by s.created_at
  loop
    v_secret := null;

    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name = r.trigger_secret_vault_name
    limit 1;

    if v_secret is null
       or encode(extensions.digest(v_secret,'sha256'),'hex')
          is distinct from r.trigger_secret_hash then
      v_skipped_count := v_skipped_count + 1;
      continue;
    end if;

    if r.sync_mode = 'mirror'
       or (r.sync_mode = 'zhirox_primary' and r.inbound_sync_enabled = true) then
      perform net.http_post(
        url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-sync-gateway',
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
        url := 'https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-outbound-sync',
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'x-daftar-sync-secret',v_secret
        ),
        body := jsonb_build_object('source_id',r.id,'action','drain'),
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

revoke all on function private.dispatch_daftar_sync_sources() from public;
revoke all on function private.dispatch_daftar_sync_sources() from anon;
revoke all on function private.dispatch_daftar_sync_sources() from authenticated;
grant execute on function private.dispatch_daftar_sync_sources() to postgres;

select cron.schedule(
  'daftar-sync-multitenant-dispatch',
  '* * * * *',
  'select private.dispatch_daftar_sync_sources();'
);
