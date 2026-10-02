alter table private.owner_telegram_os_context
  add column if not exists last_intent text not null default 'none',
  add column if not exists last_market_id uuid null references public.profiles(id) on delete set null,
  add column if not exists last_market_name text null,
  add column if not exists last_question text null,
  add column if not exists last_evidence jsonb not null default '{}'::jsonb,
  add column if not exists expires_at timestamptz null;

update private.owner_telegram_os_context
set expires_at = coalesce(expires_at, updated_at + interval '30 minutes')
where expires_at is null;

alter table private.owner_telegram_os_context
  alter column expires_at set default (now() + interval '30 minutes');

create index if not exists owner_telegram_os_context_market_idx
  on private.owner_telegram_os_context(last_market_id)
  where last_market_id is not null;

alter table private.owner_telegram_os_context enable row level security;
revoke all on private.owner_telegram_os_context from public, anon, authenticated;
grant select, insert, update, delete on private.owner_telegram_os_context to service_role;

create or replace function public.get_owner_telegram_os_context_service(p_owner_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.owner_telegram_os_context%rowtype;
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = p_owner_user_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    return jsonb_build_object('active', false, 'last_intent', 'none');
  end if;

  select * into v_row
  from private.owner_telegram_os_context c
  where c.owner_user_id = p_owner_user_id;

  if not found or v_row.expires_at is null or v_row.expires_at <= now() then
    return jsonb_build_object(
      'active', false,
      'last_intent', 'none',
      'expires_at', v_row.expires_at
    );
  end if;

  return jsonb_build_object(
    'active', true,
    'last_intent', v_row.last_intent,
    'last_market_id', v_row.last_market_id,
    'last_market_name', v_row.last_market_name,
    'last_question', v_row.last_question,
    'last_evidence', v_row.last_evidence,
    'updated_at', v_row.updated_at,
    'expires_at', v_row.expires_at
  );
end;
$$;

create or replace function public.set_owner_telegram_os_context_service(
  p_owner_user_id uuid,
  p_last_intent text,
  p_last_market_id uuid default null,
  p_last_market_name text default null,
  p_last_question text default null,
  p_last_evidence jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = p_owner_user_id
      and p.is_system_owner = true
      and p.active = true
      and p.approved = true
  ) then
    raise exception 'owner_not_authorized' using errcode = '42501';
  end if;

  insert into private.owner_telegram_os_context(
    owner_user_id, last_intent, last_market_id, last_market_name,
    last_question, last_evidence, updated_at, expires_at
  ) values (
    p_owner_user_id,
    left(coalesce(nullif(btrim(p_last_intent), ''), 'none'), 64),
    p_last_market_id,
    nullif(left(btrim(coalesce(p_last_market_name, '')), 180), ''),
    nullif(left(btrim(coalesce(p_last_question, '')), 500), ''),
    coalesce(p_last_evidence, '{}'::jsonb),
    now(),
    now() + interval '30 minutes'
  )
  on conflict (owner_user_id) do update set
    last_intent = excluded.last_intent,
    last_market_id = excluded.last_market_id,
    last_market_name = excluded.last_market_name,
    last_question = excluded.last_question,
    last_evidence = excluded.last_evidence,
    updated_at = excluded.updated_at,
    expires_at = excluded.expires_at;
end;
$$;

revoke all on function public.get_owner_telegram_os_context_service(uuid) from public, anon, authenticated;
revoke all on function public.set_owner_telegram_os_context_service(uuid,text,uuid,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.get_owner_telegram_os_context_service(uuid) to service_role;
grant execute on function public.set_owner_telegram_os_context_service(uuid,text,uuid,text,text,jsonb) to service_role;
