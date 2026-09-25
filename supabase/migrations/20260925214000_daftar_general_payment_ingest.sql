
-- Inbound Daftar PAYMENTs use the customer-wide/general ledger for IQD.
-- This keeps Daftar's customer-level PAYMENT semantics without mutating
-- individual debt rows.

create or replace function public.apply_daftar_inbound_general_payment(
  p_admin_id uuid,
  p_source_id uuid,
  p_remote_transaction_id text,
  p_customer_id uuid,
  p_amount numeric,
  p_currency text,
  p_note text,
  p_occurred_at timestamptz,
  p_payload_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_source_fingerprint text;
  v_payment_id uuid;
  v_existing_id uuid;
  v_note text := coalesce(p_note,'');
  v_occurred_at timestamptz := coalesce(p_occurred_at,now());
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode='22023';
  end if;
  if upper(coalesce(nullif(p_currency,''),'IQD')) <> 'IQD' then
    raise exception 'general_payment_currency_not_supported' using errcode='22023';
  end if;

  select s.source_fingerprint into v_source_fingerprint
  from public.daftar_sync_sources s
  where s.id=p_source_id
    and s.admin_id=p_admin_id
    and (s.enabled or s.inbound_sync_enabled or s.outbound_sync_enabled)
  limit 1;
  if v_source_fingerprint is null then
    raise exception 'sync_source_not_available' using errcode='P0002';
  end if;

  if not exists (
    select 1 from public.profiles p
    where p.id=p_customer_id and p.role='customer' and p.admin_id=p_admin_id
  ) then
    raise exception 'customer_not_found_or_forbidden' using errcode='42501';
  end if;

  perform set_config('zhirox.daftar_inbound','on',true);

  select g.id into v_existing_id
  from public.legacy_import_links l
  join public.customer_general_payments g
    on g.id=l.target_id and g.admin_id=p_admin_id
  where l.admin_id=p_admin_id
    and l.entity_kind='payment'
    and split_part(l.source_id,':',1)=p_remote_transaction_id
    and exists (
      select 1
      from private.daftar_source_fingerprint_aliases a
      where a.sync_source_id=p_source_id
        and a.source_fingerprint=l.source_fingerprint
    )
  order by l.created_at desc
  limit 1;

  if v_existing_id is null then
    select g.id into v_existing_id
    from public.customer_general_payments g
    where g.admin_id=p_admin_id
      and g.customer_id=p_customer_id
      and abs(g.amount-p_amount)<0.01
      and abs(extract(epoch from (g.created_at-v_occurred_at)))<=1
      and coalesce(g.note,'')=v_note
      and not exists (
        select 1
        from public.legacy_import_links l
        join public.daftar_mirror_transactions m
          on m.sync_source_id=p_source_id
         and m.source_id=split_part(l.source_id,':',1)
        where l.admin_id=p_admin_id
          and l.entity_kind='payment'
          and l.target_id=g.id
          and split_part(l.source_id,':',1)<>p_remote_transaction_id
      )
    order by g.created_at desc
    limit 1;
  end if;

  v_payment_id := coalesce(
    v_existing_id,
    extensions.uuid_generate_v5(
      '00000000-0000-0000-0000-000000000000'::uuid,
      p_admin_id::text || ':daftar-general:' || p_remote_transaction_id
    )
  );

  insert into public.customer_general_payments(
    id,admin_id,customer_id,amount,note,created_by,
    reference_kind,reference_id,reference_snapshot,created_at
  )
  values(
    v_payment_id,p_admin_id,p_customer_id,p_amount,v_note,p_admin_id,
    null,null,
    jsonb_build_object(
      'legacy_transaction_id',p_remote_transaction_id,
      'legacy_transaction_type','PAYMENT',
      'source','daftar_live_sync_general'
    ),
    v_occurred_at
  )
  on conflict(id) do update
    set customer_id=excluded.customer_id,
        amount=excluded.amount,
        note=excluded.note,
        reference_kind=null,
        reference_id=null,
        reference_snapshot=excluded.reference_snapshot,
        created_at=excluded.created_at;

  delete from public.legacy_import_links l
  where l.admin_id=p_admin_id
    and l.entity_kind='payment'
    and l.target_id=v_payment_id
    and split_part(l.source_id,':',1)<>p_remote_transaction_id
    and not exists (
      select 1
      from public.daftar_mirror_transactions m
      where m.sync_source_id=p_source_id
        and m.source_id=split_part(l.source_id,':',1)
    );

  insert into public.legacy_import_links(
    admin_id,source_fingerprint,entity_kind,source_id,target_id
  )
  values(
    p_admin_id,v_source_fingerprint,'payment',
    p_remote_transaction_id || ':1',v_payment_id
  )
  on conflict(admin_id,source_fingerprint,entity_kind,source_id)
  do update set target_id=excluded.target_id;

  insert into public.daftar_sync_seen(
    sync_source_id,entity_kind,source_id,target_id,payload_hash
  )
  values(p_source_id,'payment',p_remote_transaction_id,null,p_payload_hash)
  on conflict(sync_source_id,entity_kind,source_id)
  do update set target_id=null,payload_hash=excluded.payload_hash;

  insert into public.daftar_sync_seen(
    sync_source_id,entity_kind,source_id,target_id,payload_hash
  )
  values(
    p_source_id,'payment_allocation',
    p_remote_transaction_id || ':1',v_payment_id,p_payload_hash
  )
  on conflict(sync_source_id,entity_kind,source_id)
  do update set target_id=excluded.target_id,payload_hash=excluded.payload_hash;

  return v_payment_id;
end;
$function$;

revoke all on function public.apply_daftar_inbound_general_payment(
  uuid,uuid,text,uuid,numeric,text,text,timestamptz,text
) from public,anon,authenticated;
grant execute on function public.apply_daftar_inbound_general_payment(
  uuid,uuid,text,uuid,numeric,text,text,timestamptz,text
) to service_role;

create or replace function private.backfill_missing_daftar_general_payments(
  p_source_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_source public.daftar_sync_sources%rowtype;
  r record;
  v_customer_id uuid;
  v_payment_id uuid;
  v_count integer := 0;
begin
  select * into v_source
  from public.daftar_sync_sources
  where id=p_source_id
  limit 1;
  if v_source.id is null then
    raise exception 'sync_source_not_found' using errcode='P0002';
  end if;

  for r in
    select t.source_id,t.payload,t.payload_hash
    from public.daftar_mirror_transactions t
    where t.sync_source_id=p_source_id
      and upper(coalesce(t.payload->>'transaction_type',''))='PAYMENT'
      and coalesce(nullif(t.payload->>'amount','')::numeric,0)>0
      and not exists (
        select 1
        from public.legacy_import_links l
        left join public.payments p on p.id=l.target_id
        left join public.customer_general_payments g
          on g.id=l.target_id and g.admin_id=v_source.admin_id
        where l.admin_id=v_source.admin_id
          and l.entity_kind='payment'
          and split_part(l.source_id,':',1)=t.source_id
          and exists (
            select 1
            from private.daftar_source_fingerprint_aliases a
            where a.sync_source_id=p_source_id
              and a.source_fingerprint=l.source_fingerprint
          )
          and (p.id is not null or g.id is not null)
      )
    order by t.source_id::bigint
  loop
    select s.target_id into v_customer_id
    from public.daftar_sync_seen s
    join public.profiles p
      on p.id=s.target_id
     and p.role='customer'
     and p.admin_id=v_source.admin_id
    where s.sync_source_id=p_source_id
      and s.entity_kind='customer'
      and s.source_id=r.payload->>'contact_id'
    limit 1;

    if v_customer_id is null then
      continue;
    end if;

    v_payment_id := public.apply_daftar_inbound_general_payment(
      v_source.admin_id,p_source_id,r.source_id,v_customer_id,
      nullif(r.payload->>'amount','')::numeric,
      coalesce(r.payload->>'currency','IQD'),
      coalesce(r.payload->>'note',''),
      coalesce(
        nullif(r.payload->>'transaction_date','')::timestamptz,
        nullif(r.payload->>'created_at','')::timestamptz,
        now()
      ),
      r.payload_hash
    );

    if v_payment_id is not null then
      v_count := v_count + 1;
    end if;
  end loop;

  update public.daftar_outbound_events e
  set status='skipped',
      last_error='superseded_by_canonical_general_payment_mapping',
      sent_at=coalesce(sent_at,now()),
      updated_at=now()
  where e.sync_source_id=p_source_id
    and e.entity_kind='payment'
    and e.operation='delete'
    and e.status in ('pending','failed','blocked')
    and e.remote_id_snapshot is not null
    and exists (
      select 1
      from public.legacy_import_links l
      join public.customer_general_payments g
        on g.id=l.target_id and g.admin_id=v_source.admin_id
      where l.admin_id=v_source.admin_id
        and l.entity_kind='payment'
        and split_part(l.source_id,':',1)=e.remote_id_snapshot
        and exists (
          select 1
          from public.daftar_mirror_transactions m
          where m.sync_source_id=p_source_id
            and m.source_id=e.remote_id_snapshot
        )
    );

  return jsonb_build_object('backfilled_general_payments',v_count);
end;
$function$;

revoke all on function private.backfill_missing_daftar_general_payments(uuid)
  from public,anon,authenticated;
grant execute on function private.backfill_missing_daftar_general_payments(uuid)
  to service_role;
