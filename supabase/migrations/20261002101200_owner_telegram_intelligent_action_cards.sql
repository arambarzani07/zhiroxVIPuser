create table if not exists private.owner_telegram_action_tokens (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references public.profiles(id) on delete cascade,
  token_hash text not null unique,
  action text not null check (action in ('evidence','recommend','market','decision','ack','decisions')),
  entity_type text null check (entity_type is null or entity_type in ('market','decision')),
  entity_id uuid null,
  payload jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  used_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint owner_telegram_action_tokens_hash_check check (token_hash ~ '^[0-9a-f]{64}$')
);

alter table private.owner_telegram_action_tokens enable row level security;
revoke all on table private.owner_telegram_action_tokens from public, anon, authenticated;
grant select, insert, update, delete on table private.owner_telegram_action_tokens to service_role;

drop policy if exists owner_telegram_action_tokens_deny_client on private.owner_telegram_action_tokens;
create policy owner_telegram_action_tokens_deny_client
on private.owner_telegram_action_tokens
for all
to anon, authenticated
using (false)
with check (false);

create index if not exists owner_telegram_action_tokens_owner_created_idx
  on private.owner_telegram_action_tokens(owner_user_id, created_at desc);
create index if not exists owner_telegram_action_tokens_expiry_idx
  on private.owner_telegram_action_tokens(expires_at)
  where used_at is null;

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

create or replace function public.consume_owner_telegram_action_token_service(
  p_owner_user_id uuid,
  p_token_hash text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v private.owner_telegram_action_tokens%rowtype;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
  ) then
    raise exception 'owner_required' using errcode='42501';
  end if;
  select * into v
  from private.owner_telegram_action_tokens t
  where t.owner_user_id=p_owner_user_id
    and t.token_hash=lower(btrim(coalesce(p_token_hash,'')))
    and t.used_at is null
    and t.expires_at > now()
  for update skip locked;
  if not found then return jsonb_build_object('ok',false,'reason','expired_or_used'); end if;
  update private.owner_telegram_action_tokens set used_at=now() where id=v.id;
  return jsonb_build_object(
    'ok',true,'action',v.action,'entity_type',v.entity_type,'entity_id',v.entity_id,
    'payload',v.payload,'expires_at',v.expires_at
  );
end;
$$;

create or replace function public.get_owner_decision_by_id_service(
  p_owner_user_id uuid,
  p_decision_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v jsonb;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
  ) then raise exception 'owner_required' using errcode='42501'; end if;
  perform private.refresh_owner_decisions_for(p_owner_user_id);
  select to_jsonb(d) into v from private.owner_decisions d
  where d.owner_user_id=p_owner_user_id and d.id=p_decision_id limit 1;
  return v;
end;
$$;

create or replace function public.acknowledge_owner_decision_service(
  p_owner_user_id uuid,
  p_decision_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_status text; v_title text;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id=p_owner_user_id and p.is_system_owner=true and p.active=true and p.approved=true
  ) then raise exception 'owner_required' using errcode='42501'; end if;
  update private.owner_decisions d
  set status='acknowledged', updated_at=now()
  where d.owner_user_id=p_owner_user_id and d.id=p_decision_id and d.status='open'
  returning d.status,d.title into v_status,v_title;
  if found then
    perform public.log_owner_telegram_os_command_service(
      p_owner_user_id,'decision_ack','ok',jsonb_build_object('decision_id',p_decision_id,'title',v_title)
    );
    return jsonb_build_object('ok',true,'status',v_status,'title',v_title,'already_acknowledged',false);
  end if;
  select d.status,d.title into v_status,v_title
  from private.owner_decisions d where d.owner_user_id=p_owner_user_id and d.id=p_decision_id;
  if not found then return jsonb_build_object('ok',false,'reason','not_found'); end if;
  if v_status='acknowledged' then
    return jsonb_build_object('ok',true,'status',v_status,'title',v_title,'already_acknowledged',true);
  end if;
  return jsonb_build_object('ok',false,'reason','not_acknowledgeable','status',v_status,'title',v_title);
end;
$$;

revoke all on function public.create_owner_telegram_action_token_service(uuid,text,text,text,uuid,jsonb,integer) from public, anon, authenticated;
revoke all on function public.consume_owner_telegram_action_token_service(uuid,text) from public, anon, authenticated;
revoke all on function public.get_owner_decision_by_id_service(uuid,uuid) from public, anon, authenticated;
revoke all on function public.acknowledge_owner_decision_service(uuid,uuid) from public, anon, authenticated;
grant execute on function public.create_owner_telegram_action_token_service(uuid,text,text,text,uuid,jsonb,integer) to service_role;
grant execute on function public.consume_owner_telegram_action_token_service(uuid,text) to service_role;
grant execute on function public.get_owner_decision_by_id_service(uuid,uuid) to service_role;
grant execute on function public.acknowledge_owner_decision_service(uuid,uuid) to service_role;
