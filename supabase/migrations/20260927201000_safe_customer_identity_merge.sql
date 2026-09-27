-- A reversible identity merge. Ledger and Daftar IDs are immutable: records
-- remain on the original profile and are accessed through the linked group.
create table if not exists public.customer_identity_merges (
  duplicate_id uuid primary key references public.profiles(id) on delete cascade,
  canonical_id uuid not null references public.profiles(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  merged_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  check (duplicate_id <> canonical_id)
);
create index if not exists customer_identity_merges_canonical_idx
  on public.customer_identity_merges(canonical_id);
alter table public.customer_identity_merges enable row level security;
revoke all on public.customer_identity_merges from public, anon, authenticated;

create or replace function public.find_my_duplicate_customers(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_customer public.profiles%rowtype;
begin
  select * into v_customer from public.profiles p where p.id = p_customer_id
    and p.admin_id = (select auth.uid()) and p.role = 'customer';
  if not found or not exists (select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin' and p.active) then
    raise exception 'customer_not_found' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.name, 'phone', p.phone,
    'already_linked', m.duplicate_id is not null) order by p.name), '[]'::jsonb)
    from public.profiles p
    left join public.customer_identity_merges m on m.duplicate_id = p.id
    where p.admin_id = v_customer.admin_id and p.role = 'customer'
      and p.id <> v_customer.id
      and ((nullif(trim(v_customer.phone), '') is not null
        and trim(p.phone) = trim(v_customer.phone))
        or (nullif(trim(v_customer.name), '') is not null
          and lower(trim(p.name)) = lower(trim(v_customer.name)))));
end;
$$;
revoke all on function public.find_my_duplicate_customers(uuid) from public, anon;
grant execute on function public.find_my_duplicate_customers(uuid) to authenticated;

create or replace function public.merge_my_duplicate_customer(
  p_canonical_id uuid, p_duplicate_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare a public.profiles%rowtype; b public.profiles%rowtype;
begin
  if p_canonical_id = p_duplicate_id then
    raise exception 'same_customer' using errcode = '22023';
  end if;
  -- Serialize merges for a market; prevents cycles from concurrent requests.
  if not exists (select 1 from public.profiles p where p.id = (select auth.uid())
    and p.role = 'admin' and p.active) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  perform 1 from public.profiles p where p.id = (select auth.uid()) for update;
  select * into a from public.profiles p where p.id = p_canonical_id
    and p.admin_id = (select auth.uid()) and p.role = 'customer' for update;
  if not found then raise exception 'canonical_customer_not_found' using errcode = '42501'; end if;
  select * into b from public.profiles p where p.id = p_duplicate_id
    and p.admin_id = a.admin_id and p.role = 'customer' for update;
  if not found then raise exception 'duplicate_customer_not_found' using errcode = '42501'; end if;
  if exists (select 1 from public.customer_identity_merges m
    where m.duplicate_id in (a.id, b.id) or m.canonical_id = b.id) then
    raise exception 'customer_already_in_merge_group' using errcode = '23505';
  end if;
  if not ((nullif(trim(a.phone), '') is not null and trim(a.phone) = trim(b.phone))
     or (nullif(trim(a.name), '') is not null and lower(trim(a.name)) = lower(trim(b.name)))) then
    raise exception 'customers_do_not_match' using errcode = '22023';
  end if;
  insert into public.customer_identity_merges(duplicate_id, canonical_id, admin_id, merged_by)
  values(b.id, a.id, a.admin_id, (select auth.uid()));
  insert into public.audit_logs(admin_id, actor_id, action, entity_type, entity_id, changed_fields, after_data)
  values(a.admin_id, (select auth.uid()), 'update', 'customer_identity_merges', a.id::text,
    array['duplicate_id','canonical_id'],
    jsonb_build_object('duplicate_id', b.id, 'canonical_id', a.id));
  return jsonb_build_object('canonical_id', a.id, 'duplicate_id', b.id);
end;
$$;
revoke all on function public.merge_my_duplicate_customer(uuid,uuid) from public, anon;
grant execute on function public.merge_my_duplicate_customer(uuid,uuid) to authenticated;

create or replace function public.get_my_customer_merge_group(p_customer_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_root uuid;
begin
  if not exists (select 1 from public.profiles p where p.id = (select auth.uid())
    and p.role = 'admin' and p.active) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  select coalesce(m.canonical_id, p.id) into v_root
  from public.profiles p left join public.customer_identity_merges m on m.duplicate_id = p.id
  where p.id = p_customer_id and p.admin_id = (select auth.uid()) and p.role = 'customer';
  if v_root is null then raise exception 'customer_not_found' using errcode = '42501'; end if;
  return (select jsonb_build_object(
    'canonical_id', v_root,
    'customers', coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id, 'name', p.name, 'phone', p.phone,
      'remaining_iqd', public.get_customer_effective_balance(p.id)
    ) order by (p.id = v_root) desc, p.name), '[]'::jsonb),
    'total_remaining_iqd', coalesce(sum(public.get_customer_effective_balance(p.id)), 0)
  ) from public.profiles p
  where p.id = v_root or p.id in (select m.duplicate_id
    from public.customer_identity_merges m where m.canonical_id = v_root));
end;
$$;
revoke all on function public.get_my_customer_merge_group(uuid) from public, anon;
grant execute on function public.get_my_customer_merge_group(uuid) to authenticated;

create or replace function public.unmerge_my_duplicate_customer(p_duplicate_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_root uuid;
begin
  if not exists (select 1 from public.profiles p where p.id = (select auth.uid())
    and p.role = 'admin' and p.active) then
    raise exception 'admin_required' using errcode = '42501';
  end if;
  delete from public.customer_identity_merges m
    where m.duplicate_id = p_duplicate_id and m.admin_id = (select auth.uid())
    returning m.canonical_id into v_root;
  if v_root is null then raise exception 'merge_not_found' using errcode = 'P0002'; end if;
  insert into public.audit_logs(admin_id, actor_id, action, entity_type, entity_id, changed_fields, before_data)
  values((select auth.uid()), (select auth.uid()), 'delete', 'customer_identity_merges', v_root::text,
    array['duplicate_id','canonical_id'],
    jsonb_build_object('duplicate_id', p_duplicate_id, 'canonical_id', v_root));
end;
$$;
revoke all on function public.unmerge_my_duplicate_customer(uuid) from public, anon;
grant execute on function public.unmerge_my_duplicate_customer(uuid) to authenticated;
