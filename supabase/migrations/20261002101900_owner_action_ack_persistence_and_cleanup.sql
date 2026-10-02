create or replace function private.preserve_owner_decision_ack_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'acknowledged' and new.status = 'open' then
    new.status := 'acknowledged';
  end if;
  return new;
end;
$$;

drop trigger if exists preserve_owner_decision_ack_status on private.owner_decisions;
create trigger preserve_owner_decision_ack_status
before update of status on private.owner_decisions
for each row
execute function private.preserve_owner_decision_ack_status();

create or replace function public.create_owner_telegram_action_token_service(
  p_owner_user_id uuid,
  p_token_hash text,
  p_action text,
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_ttl_seconds integer default 300
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_expires timestamptz;
  v_action text := lower(btrim(coalesce(p_action,'')));
  v_entity_type text := nullif(lower(btrim(coalesce(p_entity_type,''))), '');
  v_hash text := lower(btrim(coalesce(p_token_hash,'')));
  v_ttl integer := least(greatest(coalesce(p_ttl_seconds,300),60),900);
begin
  if not exists (
    select 1 from public.profiles p
    where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
  ) then
    raise exception 'owner_required' using errcode='42501';
  end if;

  delete from private.owner_telegram_action_tokens t
  where t.expires_at < now() - interval '1 day'
     or (t.used_at is not null and t.used_at < now() - interval '1 day');

  if v_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalid_token_hash' using errcode='22023'; end if;
  if v_action not in ('evidence','recommend','market','decision','ack','decisions') then
    raise exception 'invalid_action' using errcode='22023';
  end if;
  if v_entity_type is not null and v_entity_type not in ('market','decision') then
    raise exception 'invalid_entity_type' using errcode='22023';
  end if;

  v_expires := now() + make_interval(secs => v_ttl);
  insert into private.owner_telegram_action_tokens(
    owner_user_id, token_hash, action, entity_type, entity_id, payload, expires_at
  ) values (
    p_owner_user_id, v_hash, v_action, v_entity_type, p_entity_id, coalesce(p_payload,'{}'::jsonb), v_expires
  ) returning id into v_id;

  return jsonb_build_object('id',v_id,'expires_at',v_expires,'ttl_seconds',v_ttl);
end;
$$;

revoke all on function public.create_owner_telegram_action_token_service(uuid,text,text,text,uuid,jsonb,integer) from public, anon, authenticated;
grant execute on function public.create_owner_telegram_action_token_service(uuid,text,text,text,uuid,jsonb,integer) to service_role;
