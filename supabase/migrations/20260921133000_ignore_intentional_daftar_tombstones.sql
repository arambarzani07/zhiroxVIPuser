-- A legacy transaction can remain in Daftar after its contact was deleted.
-- An explicit local tombstone is authoritative and must not keep account
-- reconciliation degraded forever.
create or replace function public.reconcile_daftar_account_28(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_tx record;
  v_customer_id uuid;
  v_event_id uuid;
  v_backfilled integer := 0;
  v_mirrored_contacts bigint := 0;
  v_mirrored_transactions bigint := 0;
  v_missing_contacts bigint := 0;
  v_missing_transactions bigint := 0;
  v_status text;
begin
  select * into v_source
  from public.daftar_sync_sources
  where id = p_source_id and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1' and enabled = true;
  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  for v_tx in
    select t.source_id, t.payload, t.payload_hash,
      t.payload->>'transaction_type' as transaction_type,
      coalesce(t.payload->>'transaction_date', t.payload->>'created_at') as occurred_at,
      coalesce(t.payload->>'currency', 'IQD') as currency,
      coalesce(t.payload->>'note', '') as note,
      t.payload->>'contact_id' as contact_source_id
    from public.daftar_mirror_transactions t
    where t.sync_source_id = v_source.id
      and coalesce(nullif(t.payload->>'amount','')::numeric, 0) = 0
      and not exists (
        select 1 from public.daftar_sync_seen z
        where z.sync_source_id = v_source.id and z.entity_kind = 'zero_event'
          and z.source_id = t.source_id
      )
    order by t.source_id::bigint
  loop
    select seen.target_id into v_customer_id
    from public.daftar_sync_seen seen
    join public.profiles p on p.id = seen.target_id
    where seen.sync_source_id = v_source.id and seen.entity_kind = 'customer'
      and seen.source_id = v_tx.contact_source_id and p.role = 'customer'
      and p.admin_id = v_source.admin_id limit 1;
    if v_customer_id is null then continue; end if;
    insert into public.financial_events(
      customer_id,event_type,actor_id,actor_name,actor_role,amount,remaining,
      currency,description,metadata,created_at
    ) values (
      v_customer_id,
      case when v_tx.transaction_type='PAYMENT' then 'payment_created' else 'debt_created' end,
      v_source.admin_id,'Daftar Qarz Sync','admin',0,0,v_tx.currency,v_tx.note,
      jsonb_build_object('legacy_zero_amount',true,'legacy_transaction_id',v_tx.source_id,
        'legacy_contact_id',v_tx.contact_source_id,'source','daftar_live_sync_reconcile'),
      coalesce(v_tx.occurred_at::timestamptz,now())
    ) returning id into v_event_id;
    insert into public.daftar_sync_seen(sync_source_id,entity_kind,source_id,target_id,payload_hash)
    values(v_source.id,'zero_event',v_tx.source_id,v_event_id,v_tx.payload_hash)
    on conflict(sync_source_id,entity_kind,source_id) do nothing;
    if v_tx.transaction_type='PAYMENT' then
      insert into public.daftar_sync_seen(sync_source_id,entity_kind,source_id,target_id,payload_hash)
      values(v_source.id,'payment',v_tx.source_id,v_event_id,v_tx.payload_hash)
      on conflict(sync_source_id,entity_kind,source_id) do nothing;
    end if;
    v_backfilled := v_backfilled + 1;
  end loop;

  select count(*) into v_mirrored_contacts from public.daftar_mirror_contacts c
  where c.sync_source_id=v_source.id;
  select count(*) into v_missing_contacts from public.daftar_mirror_contacts c
  where c.sync_source_id=v_source.id and not exists(
    select 1 from public.daftar_sync_seen seen join public.profiles p on p.id=seen.target_id
    where seen.sync_source_id=v_source.id and seen.entity_kind='customer'
      and seen.source_id=c.source_id and p.role='customer' and p.admin_id=v_source.admin_id
  );
  select count(*) into v_mirrored_transactions from public.daftar_mirror_transactions t
  where t.sync_source_id=v_source.id;
  select count(*) into v_missing_transactions from public.daftar_mirror_transactions t
  where t.sync_source_id=v_source.id
    and not exists(
      select 1 from public.daftar_sync_seen tombstone
      where tombstone.sync_source_id=v_source.id
        and tombstone.source_id=t.source_id
        and tombstone.entity_kind in ('debt','payment')
        and tombstone.payload_hash='__deleted__'
    )
    and case
      when coalesce(nullif(t.payload->>'amount','')::numeric,0)=0 then not exists(
        select 1 from public.daftar_sync_seen z join public.financial_events f on f.id=z.target_id
        where z.sync_source_id=v_source.id and z.entity_kind='zero_event' and z.source_id=t.source_id)
      when t.payload->>'transaction_type'='LOAN' then not exists(
        select 1 from public.legacy_import_links l join public.debts d on d.id=l.target_id
        where l.admin_id=v_source.admin_id and l.entity_kind='debt' and l.source_id=t.source_id)
      when t.payload->>'transaction_type'='PAYMENT' then not exists(
        select 1 from public.legacy_import_links l join public.payments p on p.id=l.target_id
        where l.admin_id=v_source.admin_id and l.entity_kind='payment'
          and split_part(l.source_id,':',1)=t.source_id)
      else true end;
  v_status := case when v_missing_contacts=0 and v_missing_transactions=0 then 'clean' else 'gap' end;
  update public.daftar_sync_sources set reconciliation_status=v_status,
    reconciliation_missing_contacts=v_missing_contacts,
    reconciliation_missing_transactions=v_missing_transactions,
    last_reconciled_at=now(),updated_at=now() where id=v_source.id;
  insert into public.daftar_reconciliation_runs(
    sync_source_id,mirrored_contacts,mirrored_transactions,missing_contacts,
    missing_transactions,backfilled_zero_events,status
  ) values(v_source.id,v_mirrored_contacts,v_mirrored_transactions,
    v_missing_contacts,v_missing_transactions,v_backfilled,v_status);
  return jsonb_build_object('status',v_status,'mirrored_contacts',v_mirrored_contacts,
    'mirrored_transactions',v_mirrored_transactions,'missing_contacts',v_missing_contacts,
    'missing_transactions',v_missing_transactions,'backfilled_zero_events',v_backfilled);
end;
$$;

revoke all on function public.reconcile_daftar_account_28(uuid) from public, anon, authenticated;
grant execute on function public.reconcile_daftar_account_28(uuid) to service_role;
