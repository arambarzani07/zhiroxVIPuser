create or replace function public.legacy_import_apply_general_payment(
  p_admin_id uuid,
  p_customer_id uuid,
  p_source_fingerprint text,
  p_source_id text,
  p_amount numeric,
  p_note text,
  p_created_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payment_id uuid;
begin
  if p_admin_id is null
     or p_customer_id is null
     or nullif(trim(coalesce(p_source_fingerprint, '')), '') is null
     or nullif(trim(coalesce(p_source_id, '')), '') is null then
    raise exception 'invalid_general_payment_import_input' using errcode = '22023';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_payment_amount' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.profiles p
    where p.id = p_customer_id
      and p.role = 'customer'
      and p.admin_id = p_admin_id
  ) then
    raise exception 'customer_not_found_or_forbidden' using errcode = '42501';
  end if;

  v_payment_id := extensions.uuid_generate_v5(
    '00000000-0000-0000-0000-000000000000'::uuid,
    p_admin_id::text || ':legacy-general:' ||
      p_source_fingerprint || ':' || p_source_id
  );

  perform set_config('zhirox.daftar_inbound', 'on', true);

  insert into public.customer_general_payments(
    id,
    admin_id,
    customer_id,
    amount,
    note,
    created_by,
    reference_kind,
    reference_id,
    reference_snapshot,
    created_at
  )
  values(
    v_payment_id,
    p_admin_id,
    p_customer_id,
    p_amount,
    coalesce(p_note, ''),
    p_admin_id,
    null,
    null,
    jsonb_build_object(
      'source', 'legacy_import',
      'payment_scope', 'general',
      'source_id', p_source_id,
      'source_fingerprint', p_source_fingerprint
    ),
    coalesce(p_created_at, now())
  )
  on conflict(id) do update
  set customer_id = excluded.customer_id,
      amount = excluded.amount,
      note = excluded.note,
      created_by = excluded.created_by,
      reference_kind = null,
      reference_id = null,
      reference_snapshot = excluded.reference_snapshot,
      created_at = excluded.created_at
  where customer_general_payments.admin_id = p_admin_id;

  return v_payment_id;
end;
$function$;

revoke all on function public.legacy_import_apply_general_payment(
  uuid, uuid, text, text, numeric, text, timestamptz
) from public, anon, authenticated;

grant execute on function public.legacy_import_apply_general_payment(
  uuid, uuid, text, text, numeric, text, timestamptz
) to service_role;
