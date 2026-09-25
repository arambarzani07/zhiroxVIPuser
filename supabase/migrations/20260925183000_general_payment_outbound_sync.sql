-- Keep customer-wide general payments consistent with the Daftar primary source.
-- General payments remain independent account-credit entries in ZHIROX; when a
-- tenant uses Daftar as the bidirectional primary source they are transported as
-- PAYMENT transactions without mutating any individual debt row.

do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid='public.daftar_outbound_events'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) ilike '%entity_kind%'
  loop
    execute format(
      'alter table public.daftar_outbound_events drop constraint %I',
      r.conname
    );
  end loop;

  alter table public.daftar_outbound_events
    add constraint daftar_outbound_events_entity_kind_check
    check (entity_kind in ('customer','debt','payment','general_payment'));

  for r in
    select conname
    from pg_constraint
    where conrelid='public.legacy_import_links'::regclass
      and contype='c'
      and pg_get_constraintdef(oid) ilike '%entity_kind%'
  loop
    execute format(
      'alter table public.legacy_import_links drop constraint %I',
      r.conname
    );
  end loop;

  alter table public.legacy_import_links
    add constraint legacy_import_links_entity_kind_check
    check (entity_kind in ('customer','debt','payment','general_payment'));
end;
$$;

create or replace function public.enqueue_daftar_general_payment_mutation()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_row jsonb := case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_admin_id uuid := (v_row->>'admin_id')::uuid;
  v_customer_id uuid := (v_row->>'customer_id')::uuid;
  v_entity_id uuid := (v_row->>'id')::uuid;
  v_operation text := case tg_op
    when 'INSERT' then 'create'
    when 'UPDATE' then 'update'
    else 'delete'
  end;
  v_source_id uuid;
  v_source_fingerprint text;
  v_remote_id text;
  v_payload jsonb;
begin
  if coalesce(current_setting('zhirox.daftar_inbound',true),'')='on' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if v_admin_id is null or v_customer_id is null or v_entity_id is null then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if tg_op='UPDATE'
     and (new.customer_id,new.amount,new.note)
         is not distinct from (old.customer_id,old.amount,old.note) then
    return new;
  end if;

  select s.id,s.source_fingerprint
    into v_source_id,v_source_fingerprint
  from public.daftar_sync_sources s
  where s.admin_id=v_admin_id
    and s.enabled=true
    and s.sync_mode='zhirox_primary'
    and s.outbound_sync_enabled=true
    and s.outbound_write_contract_status='verified'
  order by s.created_at
  limit 1;

  if v_source_id is null then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  select l.source_id
    into v_remote_id
  from public.legacy_import_links l
  where l.admin_id=v_admin_id
    and l.source_fingerprint=v_source_fingerprint
    and l.entity_kind='general_payment'
    and l.target_id=v_entity_id
  order by l.created_at desc
  limit 1;

  v_payload := jsonb_build_object(
    'id',v_row->>'id',
    'customer_id',v_row->>'customer_id',
    'amount',v_row->'amount',
    'currency','IQD',
    'note',coalesce(v_row->>'note',''),
    'transaction_date',v_row->>'created_at',
    'created_at',v_row->>'created_at',
    'payment_scope','general'
  );

  insert into public.daftar_outbound_events(
    sync_source_id,entity_kind,entity_id,operation,idempotency_key,
    payload_snapshot,remote_id_snapshot,next_attempt_at
  ) values (
    v_source_id,'general_payment',v_entity_id,v_operation,
    'zhirox:'||v_source_id::text||':general_payment:'||
      v_entity_id::text||':'||v_operation||':'||md5(v_payload::text),
    v_payload,v_remote_id,now()+interval '5 seconds'
  )
  on conflict(idempotency_key) do update
  set payload_snapshot=excluded.payload_snapshot,
      remote_id_snapshot=coalesce(
        excluded.remote_id_snapshot,
        public.daftar_outbound_events.remote_id_snapshot
      ),
      status=case
        when public.daftar_outbound_events.status in ('sent','skipped')
          then public.daftar_outbound_events.status
        else 'pending'
      end,
      next_attempt_at=least(
        public.daftar_outbound_events.next_attempt_at,
        excluded.next_attempt_at
      ),
      updated_at=now();

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function public.enqueue_daftar_general_payment_mutation()
  from public,anon,authenticated;

drop trigger if exists daftar_outbound_general_payment_mutation
  on public.customer_general_payments;
create trigger daftar_outbound_general_payment_mutation
after insert or update or delete on public.customer_general_payments
for each row execute function public.enqueue_daftar_general_payment_mutation();

-- Queue account-credit rows that predate this transport. A mapping proves the
-- remote transaction already exists, so mapped rows are never backfilled twice.
insert into public.daftar_outbound_events(
  sync_source_id,entity_kind,entity_id,operation,idempotency_key,
  payload_snapshot,remote_id_snapshot,next_attempt_at
)
select
  s.id,
  'general_payment',
  g.id,
  'create',
  'zhirox:'||s.id::text||':general_payment:'||g.id::text||':create:'||
    md5(jsonb_build_object(
      'id',g.id,
      'customer_id',g.customer_id,
      'amount',g.amount,
      'currency','IQD',
      'note',coalesce(g.note,''),
      'transaction_date',g.created_at,
      'created_at',g.created_at,
      'payment_scope','general'
    )::text),
  jsonb_build_object(
    'id',g.id,
    'customer_id',g.customer_id,
    'amount',g.amount,
    'currency','IQD',
    'note',coalesce(g.note,''),
    'transaction_date',g.created_at,
    'created_at',g.created_at,
    'payment_scope','general'
  ),
  null,
  now()+interval '5 seconds'
from public.customer_general_payments g
join public.daftar_sync_sources s
  on s.admin_id=g.admin_id
 and s.enabled=true
 and s.sync_mode='zhirox_primary'
 and s.outbound_sync_enabled=true
 and s.outbound_write_contract_status='verified'
where not exists (
  select 1
  from public.legacy_import_links l
  where l.admin_id=g.admin_id
    and l.source_fingerprint=s.source_fingerprint
    and l.entity_kind='general_payment'
    and l.target_id=g.id
)
on conflict(idempotency_key) do nothing;

create or replace function public.apply_daftar_inbound_general_payment_update(
  p_admin_id uuid,
  p_source_id uuid,
  p_remote_transaction_id text,
  p_amount numeric,
  p_note text,
  p_occurred_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_target_id uuid;
begin
  if p_amount is null or p_amount<=0 then
    raise exception 'invalid_general_payment_amount' using errcode='22023';
  end if;

  select g.id
    into v_target_id
  from public.legacy_import_links l
  join public.customer_general_payments g on g.id=l.target_id
  where l.admin_id=p_admin_id
    and l.entity_kind='general_payment'
    and l.source_id=p_remote_transaction_id
    and g.admin_id=p_admin_id
    and exists (
      select 1
      from private.daftar_source_fingerprint_aliases a
      where a.sync_source_id=p_source_id
        and a.source_fingerprint=l.source_fingerprint
    )
  order by l.created_at desc
  limit 1;

  if v_target_id is null then return false; end if;

  perform set_config('zhirox.daftar_inbound','on',true);
  update public.customer_general_payments
  set amount=p_amount,
      note=coalesce(p_note,''),
      created_at=coalesce(p_occurred_at,created_at)
  where id=v_target_id
    and admin_id=p_admin_id;
  return found;
end;
$function$;

create or replace function public.remove_daftar_inbound_general_payment(
  p_admin_id uuid,
  p_source_id uuid,
  p_remote_transaction_id text
)
returns boolean
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_target_id uuid;
begin
  select g.id
    into v_target_id
  from public.legacy_import_links l
  join public.customer_general_payments g on g.id=l.target_id
  where l.admin_id=p_admin_id
    and l.entity_kind='general_payment'
    and l.source_id=p_remote_transaction_id
    and g.admin_id=p_admin_id
    and exists (
      select 1
      from private.daftar_source_fingerprint_aliases a
      where a.sync_source_id=p_source_id
        and a.source_fingerprint=l.source_fingerprint
    )
  order by l.created_at desc
  limit 1;

  if v_target_id is null then return false; end if;

  perform set_config('zhirox.daftar_inbound','on',true);
  delete from public.customer_general_payments
  where id=v_target_id and admin_id=p_admin_id;
  return found;
end;
$function$;

revoke all on function public.apply_daftar_inbound_general_payment_update(
  uuid,uuid,text,numeric,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.apply_daftar_inbound_general_payment_update(
  uuid,uuid,text,numeric,text,timestamptz
) to service_role;

revoke all on function public.remove_daftar_inbound_general_payment(
  uuid,uuid,text
) from public,anon,authenticated;
grant execute on function public.remove_daftar_inbound_general_payment(
  uuid,uuid,text
) to service_role;

-- A mapped general payment is only considered reflected in official Daftar
-- totals after inbound sync has confirmed the remote PAYMENT (non-null hash).
create or replace function private.get_confirmed_synced_general_payment_total(
  p_sync_source_id uuid,
  p_customer_id uuid default null
)
returns numeric
language sql
stable
security definer
set search_path=''
as $function$
  select coalesce(sum(g.amount),0)::numeric
  from public.daftar_sync_sources s
  join public.customer_general_payments g
    on g.admin_id=s.admin_id
  join public.legacy_import_links l
    on l.admin_id=s.admin_id
   and l.entity_kind='general_payment'
   and l.target_id=g.id
   and exists (
     select 1
     from private.daftar_source_fingerprint_aliases a
     where a.sync_source_id=s.id
       and a.source_fingerprint=l.source_fingerprint
   )
  join public.daftar_sync_seen seen
    on seen.sync_source_id=s.id
   and seen.entity_kind='payment'
   and seen.source_id=l.source_id
   and seen.payload_hash is not null
   and seen.payload_hash not in ('__deleted__','__credit_limit_rejected__')
  where s.id=p_sync_source_id
    and (p_customer_id is null or g.customer_id=p_customer_id);
$function$;

revoke all on function private.get_confirmed_synced_general_payment_total(uuid,uuid)
  from public,anon,authenticated;
grant execute on function private.get_confirmed_synced_general_payment_total(uuid,uuid)
  to service_role;

-- Normalize the raw official projection so downstream general-credit-aware
-- functions can keep subtracting/adding ALL local general payments without
-- double-counting rows already reflected in Daftar.
create or replace function private.get_daftar_projection_summary()
returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  with tenant as (
    select private.current_admin_id() as admin_id
  )
  select coalesce((
    select jsonb_build_object(
      'source_id',s.id,
      'admin_id',s.admin_id,
      'source_fingerprint',s.source_fingerprint,
      'legacy_user_id',s.legacy_user_id,
      'official_total_customers',coalesce(s.official_total_customers,0),
      'official_total_loan_iqd',coalesce(s.official_total_loan_iqd,0),
      'official_total_payment_iqd',greatest(
        coalesce(s.official_total_payment_iqd,0)
          - private.get_confirmed_synced_general_payment_total(s.id,null),
        0
      ),
      'official_balance_iqd',
        coalesce(s.official_balance_iqd,0)
          + private.get_confirmed_synced_general_payment_total(s.id,null),
      'official_total_loan_usd',coalesce(s.official_total_loan_usd,0),
      'official_total_payment_usd',coalesce(s.official_total_payment_usd,0),
      'official_balance_usd',coalesce(s.official_balance_usd,0),
      'official_totals_at',s.official_totals_at,
      'confirmed_synced_general_payment_iqd',
        private.get_confirmed_synced_general_payment_total(s.id,null)
    )
    from public.daftar_sync_sources s
    cross join tenant t
    where t.admin_id is not null
      and s.admin_id=t.admin_id
      and s.sync_mode='zhirox_primary'
      and coalesce(s.inbound_sync_enabled,false)
      and s.official_totals_at is not null
    order by s.official_totals_at desc nulls last,s.created_at
    limit 1
  ),'{}'::jsonb);
$function$;

revoke all on function private.get_daftar_projection_summary()
  from public,anon;
grant execute on function private.get_daftar_projection_summary()
  to authenticated,service_role;

create or replace function private.get_daftar_official_customer_totals(
  p_customer_id uuid default null
)
returns table(
  customer_id uuid,
  source_contact_id text,
  loan_iqd numeric,
  payment_iqd numeric,
  balance_iqd numeric,
  loan_usd numeric,
  payment_usd numeric,
  balance_usd numeric
)
language sql
stable
security definer
set search_path=''
as $function$
  with tenant as (
    select private.current_admin_id() as admin_id
  ),
  source_row as (
    select s.id,s.admin_id,s.source_fingerprint
    from public.daftar_sync_sources s
    cross join tenant t
    where t.admin_id is not null
      and s.admin_id=t.admin_id
      and s.sync_mode='zhirox_primary'
      and coalesce(s.inbound_sync_enabled,false)
      and s.official_totals_at is not null
    order by s.official_totals_at desc nulls last,s.created_at
    limit 1
  )
  select
    l.target_id as customer_id,
    l.source_id as source_contact_id,
    oct.loan_iqd,
    greatest(
      oct.payment_iqd
        - private.get_confirmed_synced_general_payment_total(sr.id,l.target_id),
      0
    )::numeric as payment_iqd,
    (
      oct.balance_iqd
        + private.get_confirmed_synced_general_payment_total(sr.id,l.target_id)
    )::numeric as balance_iqd,
    oct.loan_usd,
    oct.payment_usd,
    oct.balance_usd
  from source_row sr
  join public.legacy_import_links l
    on l.admin_id=sr.admin_id
   and l.entity_kind='customer'
   and exists (
     select 1
     from private.daftar_source_fingerprint_aliases a
     where a.sync_source_id=sr.id
       and a.source_fingerprint=l.source_fingerprint
   )
  join public.daftar_official_contact_totals oct
    on oct.sync_source_id=sr.id
   and oct.source_contact_id=l.source_id
  join public.profiles p
    on p.id=l.target_id
   and p.admin_id=sr.admin_id
   and p.role='customer'
  where p_customer_id is null or l.target_id=p_customer_id;
$function$;

revoke all on function private.get_daftar_official_customer_totals(uuid)
  from public,anon;
grant execute on function private.get_daftar_official_customer_totals(uuid)
  to authenticated,service_role;
