-- Keep account-28 customer identity mapping one-to-one and prune stale
-- technical mappings without deleting customer or financial records.

create table if not exists public.daftar_customer_link_archive (
  archive_id uuid primary key default gen_random_uuid(),
  sync_source_id uuid not null references public.daftar_sync_sources(id) on delete cascade,
  admin_id uuid not null references public.profiles(id) on delete cascade,
  source_fingerprint text not null,
  source_id text not null,
  target_id uuid not null references public.profiles(id) on delete cascade,
  archived_reason text not null,
  source_contact_count integer not null,
  archived_at timestamptz not null default now()
);

alter table public.daftar_customer_link_archive enable row level security;
revoke all on table public.daftar_customer_link_archive from public, anon, authenticated;
grant select on table public.daftar_customer_link_archive to service_role;

create unique index if not exists legacy_import_links_customer_target_unique
on public.legacy_import_links (admin_id, source_fingerprint, target_id)
where entity_kind = 'customer';

create unique index if not exists daftar_sync_seen_customer_target_unique
on public.daftar_sync_seen (sync_source_id, target_id)
where entity_kind = 'customer' and target_id is not null;

create or replace function public.reconcile_daftar_customer_identity_links(
  p_source_id uuid,
  p_current_contact_ids text[],
  p_expected_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_distinct_count integer := 0;
  v_archived integer := 0;
  v_seen_removed integer := 0;
  v_mirror_removed integer := 0;
  v_active_links integer := 0;
  v_missing_links integer := 0;
begin
  select *
    into v_source
  from public.daftar_sync_sources
  where id = p_source_id
    and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
  for update;

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  if p_expected_count is null or p_expected_count <= 0
     or p_current_contact_ids is null
     or cardinality(p_current_contact_ids) = 0 then
    raise exception 'daftar_customer_identity_input_empty' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(p_current_contact_ids) x(id)
    where nullif(trim(id), '') is null
  ) then
    raise exception 'daftar_customer_identity_blank_source_id' using errcode = '22023';
  end if;

  select count(distinct trim(id))::integer
    into v_distinct_count
  from unnest(p_current_contact_ids) x(id);

  if v_distinct_count <> p_expected_count then
    raise exception
      'daftar_customer_identity_count_mismatch: ids %, expected %',
      v_distinct_count, p_expected_count
      using errcode = '22023';
  end if;

  if v_source.official_total_customers is null
     or v_source.official_total_customers <> p_expected_count then
    raise exception
      'daftar_customer_identity_official_count_mismatch: official %, expected %',
      v_source.official_total_customers, p_expected_count
      using errcode = '22023';
  end if;

  insert into public.daftar_customer_link_archive (
    sync_source_id,
    admin_id,
    source_fingerprint,
    source_id,
    target_id,
    archived_reason,
    source_contact_count
  )
  select
    v_source.id,
    l.admin_id,
    l.source_fingerprint,
    l.source_id,
    l.target_id,
    'source_contact_absent_from_current_daftar_snapshot',
    p_expected_count
  from public.legacy_import_links l
  where l.admin_id = v_source.admin_id
    and l.source_fingerprint = v_source.source_fingerprint
    and l.entity_kind = 'customer'
    and not (l.source_id = any(p_current_contact_ids));

  get diagnostics v_archived = row_count;

  delete from public.legacy_import_links l
  where l.admin_id = v_source.admin_id
    and l.source_fingerprint = v_source.source_fingerprint
    and l.entity_kind = 'customer'
    and not (l.source_id = any(p_current_contact_ids));

  delete from public.daftar_sync_seen s
  where s.sync_source_id = v_source.id
    and s.entity_kind = 'customer'
    and not (s.source_id = any(p_current_contact_ids));

  get diagnostics v_seen_removed = row_count;

  delete from public.daftar_mirror_contacts m
  where m.sync_source_id = v_source.id
    and not (m.source_id = any(p_current_contact_ids));

  get diagnostics v_mirror_removed = row_count;

  select count(*)::integer
    into v_active_links
  from public.legacy_import_links l
  where l.admin_id = v_source.admin_id
    and l.source_fingerprint = v_source.source_fingerprint
    and l.entity_kind = 'customer';

  select count(*)::integer
    into v_missing_links
  from unnest(p_current_contact_ids) x(id)
  where not exists (
    select 1
    from public.legacy_import_links l
    where l.admin_id = v_source.admin_id
      and l.source_fingerprint = v_source.source_fingerprint
      and l.entity_kind = 'customer'
      and l.source_id = trim(x.id)
  );

  return jsonb_build_object(
    'source_id', v_source.id,
    'expected_contacts', p_expected_count,
    'active_customer_links', v_active_links,
    'missing_customer_links', v_missing_links,
    'archived_stale_links', v_archived,
    'removed_stale_seen_rows', v_seen_removed,
    'removed_stale_mirror_rows', v_mirror_removed,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.reconcile_daftar_customer_identity_links(uuid,text[],integer)
  from public, anon, authenticated;
grant execute on function public.reconcile_daftar_customer_identity_links(uuid,text[],integer)
  to service_role;
