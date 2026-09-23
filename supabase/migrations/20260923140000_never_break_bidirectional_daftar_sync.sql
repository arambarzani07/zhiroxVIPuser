-- Never-break contract for the permanent Daftar Qarz <-> ZHIROX sync.
-- 1) Both inbound and outbound transports for account 28 are immutable-on.
-- 2) Explicit deletion tombstones are excluded from cutover mismatch counts.
-- 3) Outbound ambiguous DELETE retry behavior is implemented in the paired
--    daftar-outbound-sync Edge Function update.

create or replace function public.prevent_daftar_sync_account_28_breakage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_guardian boolean := coalesce(current_setting('zhirox.daftar_sync_guardian', true), '') = 'on';
  v_unlock boolean := coalesce(current_setting('zhirox.daftar_sync_unlock', true), '') = 'on';
begin
  if v_unlock or v_guardian then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if tg_op = 'DELETE' then
    if old.legacy_user_id = 28
       and old.source_fingerprint = 'daftar-live-account-28-v1' then
      raise exception 'daftar_sync_account_28_locked' using errcode = '42501';
    end if;
    return old;
  end if;

  if old.legacy_user_id = 28
     and old.source_fingerprint = 'daftar-live-account-28-v1' then
    if new.id is distinct from old.id
       or new.admin_id is distinct from old.admin_id
       or new.legacy_user_id is distinct from 28
       or new.source_name is distinct from 'Daftar Qarz / account 28'
       or new.source_fingerprint is distinct from 'daftar-live-account-28-v1'
       or new.api_base_url is distinct from 'https://api-daftar-qarz.kasbkar.net/api/v1'
       or new.trigger_secret_hash is distinct from old.trigger_secret_hash then
      raise exception 'daftar_sync_account_28_locked' using errcode = '42501';
    end if;

    if old.sync_mode = 'mirror' then
      if new.sync_mode is distinct from 'mirror'
         or new.enabled is distinct from true then
        raise exception 'daftar_sync_mirror_mode_locked' using errcode = '42501';
      end if;
    elsif old.sync_mode = 'zhirox_primary' then
      if new.sync_mode is distinct from 'zhirox_primary' then
        raise exception 'daftar_sync_primary_mode_locked' using errcode = '42501';
      end if;

      if new.enabled is distinct from true
         or new.inbound_sync_enabled is distinct from true
         or new.outbound_sync_enabled is distinct from true then
        raise exception 'daftar_bidirectional_sync_must_remain_enabled' using errcode = '42501';
      end if;

      if new.outbound_write_contract_status is distinct from 'verified' then
        raise exception 'daftar_outbound_write_contract_must_remain_verified' using errcode = '42501';
      end if;
    else
      raise exception 'daftar_sync_unknown_mode_locked' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_daftar_sync_account_28_breakage()
  from public, anon, authenticated;

create or replace function public.run_daftar_cutover_rehearsal(p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.daftar_sync_sources%rowtype;
  v_nonzero_loans bigint := 0;
  v_missing_loans bigint := 0;
  v_loan_target_conflicts bigint := 0;
  v_loan_amount_mismatches bigint := 0;
  v_loan_currency_mismatches bigint := 0;
  v_nonzero_payments bigint := 0;
  v_missing_payments bigint := 0;
  v_payment_amount_mismatches bigint := 0;
  v_payment_currency_mismatches bigint := 0;
  v_zero_event_mismatches bigint := 0;
  v_total_mismatches bigint := 0;
  v_status text := 'fail';
  v_details jsonb := '{}'::jsonb;
begin
  select *
    into v_source
  from public.daftar_sync_sources
  where id = p_source_id
    and legacy_user_id = 28
    and source_fingerprint = 'daftar-live-account-28-v1'
    and enabled = true;

  if v_source.id is null then
    raise exception 'daftar_source_not_available' using errcode = '42501';
  end if;

  with raw as (
    select
      t.source_id,
      coalesce(nullif(t.payload->>'amount','')::numeric, 0) as raw_amount,
      upper(coalesce(nullif(t.payload->>'currency',''), 'IQD')) as raw_currency
    from public.daftar_mirror_transactions t
    where t.sync_source_id = v_source.id
      and t.payload->>'transaction_type' = 'LOAN'
      and coalesce(nullif(t.payload->>'amount','')::numeric, 0) <> 0
      and not exists (
        select 1
        from public.daftar_sync_seen tombstone
        where tombstone.sync_source_id = v_source.id
          and tombstone.entity_kind = 'debt'
          and tombstone.source_id = t.source_id
          and tombstone.payload_hash = '__deleted__'
      )
  ),
  links as (
    select
      l.source_id,
      count(distinct l.target_id) as target_count,
      min(l.target_id::text)::uuid as target_id
    from public.legacy_import_links l
    where l.admin_id = v_source.admin_id
      and l.entity_kind = 'debt'
    group by l.source_id
  ),
  cmp as (
    select
      r.source_id,
      r.raw_amount,
      r.raw_currency,
      coalesce(l.target_count, 0) as target_count,
      d.id as debt_id,
      d.amount as zhirox_amount,
      upper(coalesce(d.currency, 'IQD')) as zhirox_currency
    from raw r
    left join links l on l.source_id = r.source_id
    left join public.debts d on d.id = l.target_id
  )
  select
    count(*),
    count(*) filter (where target_count = 0 or debt_id is null),
    count(*) filter (where target_count > 1),
    count(*) filter (
      where target_count = 1
        and debt_id is not null
        and abs(raw_amount - zhirox_amount) > 0.009
    ),
    count(*) filter (
      where target_count = 1
        and debt_id is not null
        and raw_currency <> zhirox_currency
    )
  into
    v_nonzero_loans,
    v_missing_loans,
    v_loan_target_conflicts,
    v_loan_amount_mismatches,
    v_loan_currency_mismatches
  from cmp;

  with raw as (
    select
      t.source_id,
      coalesce(nullif(t.payload->>'amount','')::numeric, 0) as raw_amount,
      upper(coalesce(nullif(t.payload->>'currency',''), 'IQD')) as raw_currency
    from public.daftar_mirror_transactions t
    where t.sync_source_id = v_source.id
      and t.payload->>'transaction_type' = 'PAYMENT'
      and coalesce(nullif(t.payload->>'amount','')::numeric, 0) <> 0
      and not exists (
        select 1
        from public.daftar_sync_seen tombstone
        where tombstone.sync_source_id = v_source.id
          and tombstone.entity_kind = 'payment'
          and tombstone.source_id = t.source_id
          and tombstone.payload_hash = '__deleted__'
      )
  ),
  targets as (
    select distinct
      split_part(l.source_id, ':', 1) as source_id,
      l.target_id
    from public.legacy_import_links l
    where l.admin_id = v_source.admin_id
      and l.entity_kind = 'payment'
  ),
  agg as (
    select
      r.source_id,
      r.raw_amount,
      r.raw_currency,
      count(p.id) as allocation_count,
      coalesce(sum(p.amount), 0) as zhirox_amount,
      count(*) filter (
        where p.id is not null
          and upper(coalesce(d.currency, 'IQD')) <> r.raw_currency
      ) as currency_mismatch_allocations
    from raw r
    left join targets t on t.source_id = r.source_id
    left join public.payments p on p.id = t.target_id
    left join public.debts d on d.id = p.debt_id
    group by r.source_id, r.raw_amount, r.raw_currency
  )
  select
    count(*),
    count(*) filter (where allocation_count = 0),
    count(*) filter (
      where allocation_count > 0
        and abs(raw_amount - zhirox_amount) > 0.009
    ),
    count(*) filter (where currency_mismatch_allocations > 0)
  into
    v_nonzero_payments,
    v_missing_payments,
    v_payment_amount_mismatches,
    v_payment_currency_mismatches
  from agg;

  select count(*)
    into v_zero_event_mismatches
  from public.daftar_mirror_transactions t
  where t.sync_source_id = v_source.id
    and coalesce(nullif(t.payload->>'amount','')::numeric, 0) = 0
    and not exists (
      select 1
      from public.daftar_sync_seen z
      join public.financial_events f on f.id = z.target_id
      where z.sync_source_id = v_source.id
        and z.entity_kind = 'zero_event'
        and z.source_id = t.source_id
        and f.amount = 0
        and f.remaining = 0
        and f.event_type = case
          when t.payload->>'transaction_type' = 'PAYMENT'
            then 'payment_created'
          else 'debt_created'
        end
    );

  v_total_mismatches :=
      v_missing_loans
    + v_loan_target_conflicts
    + v_loan_amount_mismatches
    + v_loan_currency_mismatches
    + v_missing_payments
    + v_payment_amount_mismatches
    + v_payment_currency_mismatches
    + v_zero_event_mismatches;

  v_status := case when v_total_mismatches = 0 then 'pass' else 'fail' end;

  v_details := jsonb_build_object(
    'nonzero_loans', v_nonzero_loans,
    'missing_loans', v_missing_loans,
    'loan_target_conflicts', v_loan_target_conflicts,
    'loan_amount_mismatches', v_loan_amount_mismatches,
    'loan_currency_mismatches', v_loan_currency_mismatches,
    'nonzero_payments', v_nonzero_payments,
    'missing_payments', v_missing_payments,
    'payment_amount_mismatches', v_payment_amount_mismatches,
    'payment_currency_mismatches', v_payment_currency_mismatches,
    'zero_event_mismatches', v_zero_event_mismatches,
    'total_mismatches', v_total_mismatches
  );

  update public.daftar_sync_sources
  set cutover_rehearsal_status = v_status,
      cutover_rehearsal_mismatches = v_total_mismatches,
      last_cutover_rehearsal_at = now(),
      updated_at = now()
  where id = v_source.id;

  insert into public.daftar_cutover_rehearsal_runs(
    sync_source_id,
    nonzero_loans,
    missing_loans,
    loan_target_conflicts,
    loan_amount_mismatches,
    loan_currency_mismatches,
    nonzero_payments,
    missing_payments,
    payment_amount_mismatches,
    payment_currency_mismatches,
    zero_event_mismatches,
    total_mismatches,
    status,
    details
  ) values (
    v_source.id,
    v_nonzero_loans,
    v_missing_loans,
    v_loan_target_conflicts,
    v_loan_amount_mismatches,
    v_loan_currency_mismatches,
    v_nonzero_payments,
    v_missing_payments,
    v_payment_amount_mismatches,
    v_payment_currency_mismatches,
    v_zero_event_mismatches,
    v_total_mismatches,
    v_status,
    v_details
  );

  return jsonb_build_object(
    'status', v_status,
    'details', v_details
  );
end;
$$;

revoke all on function public.run_daftar_cutover_rehearsal(uuid)
  from public, anon, authenticated;
grant execute on function public.run_daftar_cutover_rehearsal(uuid)
  to service_role;
