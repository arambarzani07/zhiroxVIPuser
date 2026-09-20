-- Backfill the missing Daftar contact -> ZHIROX customer identity links.
-- Historical bootstrap data existed before customer links were persisted for
-- every contact. Exact-projection reads therefore saw only the few contacts
-- touched after that change. This migration reconstructs all 517 links using
-- unique phone matches first and unique normalized-name matches as a fallback.

do $$
declare
  v_source_id uuid;
  v_admin_id uuid;
  v_contacts integer;
  v_resolved integer;
  v_ambiguous integer;
begin
  select id, admin_id
    into v_source_id, v_admin_id
  from public.daftar_sync_sources
  where legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  order by created_at
  limit 1;

  if v_source_id is null or v_admin_id is null then
    raise exception 'daftar_source_not_available';
  end if;

  create temporary table tmp_daftar_customer_link_map
  on commit drop
  as
  with mirror_contacts as (
    select
      c.source_id,
      lower(trim(regexp_replace(coalesce(c.payload->>'name', ''), '\s+', ' ', 'g'))) as norm_name,
      nullif(regexp_replace(coalesce(c.payload->>'phone', ''), '\D', '', 'g'), '') as norm_phone
    from public.daftar_mirror_contacts c
    where c.sync_source_id = v_source_id
  ),
  profiles as (
    select
      p.id,
      lower(trim(regexp_replace(coalesce(p.name, ''), '\s+', ' ', 'g'))) as norm_name,
      nullif(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), '') as norm_phone
    from public.profiles p
    where p.admin_id = v_admin_id
      and p.role = 'customer'
  ),
  candidates as (
    select
      mc.source_id,
      p.id as target_id,
      case
        when mc.norm_phone is not null and p.norm_phone = mc.norm_phone then 1
        when mc.norm_name <> '' and p.norm_name = mc.norm_name then 2
        else 99
      end as rank
    from mirror_contacts mc
    join profiles p
      on (mc.norm_phone is not null and p.norm_phone = mc.norm_phone)
      or (mc.norm_name <> '' and p.norm_name = mc.norm_name)
  ),
  ranked as (
    select
      source_id,
      target_id,
      rank,
      min(rank) over (partition by source_id) as best_rank
    from candidates
  ),
  best as (
    select source_id, target_id
    from ranked
    where rank = best_rank
  ),
  unique_best as (
    select source_id, min(target_id::text)::uuid as target_id, count(*) as matches
    from best
    group by source_id
  )
  select source_id, target_id
  from unique_best
  where matches = 1;

  select count(*) into v_contacts
  from public.daftar_mirror_contacts
  where sync_source_id = v_source_id;

  select count(*) into v_resolved
  from tmp_daftar_customer_link_map;

  select count(*) into v_ambiguous
  from (
    select c.source_id
    from public.daftar_mirror_contacts c
    where c.sync_source_id = v_source_id
      and not exists (
        select 1
        from tmp_daftar_customer_link_map m
        where m.source_id = c.source_id
      )
  ) x;

  if v_contacts = 0 then
    raise exception 'daftar_contact_mirror_empty';
  end if;

  if v_resolved <> v_contacts or v_ambiguous <> 0 then
    raise exception 'daftar_customer_link_backfill_not_safe: contacts %, resolved %, unresolved_or_ambiguous %',
      v_contacts, v_resolved, v_ambiguous;
  end if;

  insert into public.legacy_import_links (
    admin_id,
    source_fingerprint,
    entity_kind,
    source_id,
    target_id
  )
  select
    v_admin_id,
    'daftar-live-account-28-v1',
    'customer',
    m.source_id,
    m.target_id
  from tmp_daftar_customer_link_map m
  on conflict (admin_id, source_fingerprint, entity_kind, source_id)
  do update set target_id = excluded.target_id;
end;
$$;
