-- Mirrors production migration 20260924215323: audit40_backup_restore_v2.
-- v2 keeps v1 verification compatibility while expanding tenant business-state coverage.
-- Auth identities are a manifest dependency; audit logs and push credentials remain append-only/security scoped.

CREATE OR REPLACE FUNCTION private.backup_snapshot_counts(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_version integer := coalesce((p_snapshot->>'version')::integer, 0);
begin
  if v_version = 1 then
    return jsonb_build_object(
      'profiles', jsonb_array_length(coalesce(p_snapshot->'profiles','[]'::jsonb)),
      'debts', jsonb_array_length(coalesce(p_snapshot->'debts','[]'::jsonb)),
      'payments', jsonb_array_length(coalesce(p_snapshot->'payments','[]'::jsonb)),
      'employee_permissions', jsonb_array_length(coalesce(p_snapshot->'employee_permissions','[]'::jsonb))
    );
  elsif v_version = 2 then
    return jsonb_build_object(
      'profiles', jsonb_array_length(coalesce(p_snapshot->'profiles','[]'::jsonb)),
      'debts', jsonb_array_length(coalesce(p_snapshot->'debts','[]'::jsonb)),
      'payments', jsonb_array_length(coalesce(p_snapshot->'payments','[]'::jsonb)),
      'general_payments', jsonb_array_length(coalesce(p_snapshot->'general_payments','[]'::jsonb)),
      'employee_permissions', jsonb_array_length(coalesce(p_snapshot->'employee_permissions','[]'::jsonb)),
      'market_receipt_settings', jsonb_array_length(coalesce(p_snapshot->'market_receipt_settings','[]'::jsonb)),
      'customer_notification_preferences', jsonb_array_length(coalesce(p_snapshot->'customer_notification_preferences','[]'::jsonb)),
      'market_notification_settings', jsonb_array_length(coalesce(p_snapshot->'market_notification_settings','[]'::jsonb)),
      'debt_installments', jsonb_array_length(coalesce(p_snapshot->'debt_installments','[]'::jsonb)),
      'receipt_documents', jsonb_array_length(coalesce(p_snapshot->'receipt_documents','[]'::jsonb)),
      'receipt_template_versions', jsonb_array_length(coalesce(p_snapshot->'receipt_template_versions','[]'::jsonb))
    );
  end if;
  return '{}'::jsonb;
end;
$function$;
CREATE OR REPLACE FUNCTION private.build_tenant_backup_snapshot(p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with tenant_profiles as materialized (
    select p.*
    from public.profiles p
    where p.id = p_admin_id or p.admin_id = p_admin_id
  ),
  tenant_debts as materialized (
    select d.*
    from public.debts d
    join tenant_profiles p on p.id = d.customer_id
  ),
  tenant_payments as materialized (
    select pay.*
    from public.payments pay
    join tenant_debts d on d.id = pay.debt_id
  ),
  tenant_general_payments as materialized (
    select g.*
    from public.customer_general_payments g
    where g.admin_id = p_admin_id
  ),
  tenant_installments as materialized (
    select i.*
    from public.debt_installments i
    where i.admin_id = p_admin_id
  )
  select jsonb_build_object(
    'version', 2,
    'created_at', now(),
    'scope', jsonb_build_object(
      'auth_identities', 'manifest_only',
      'audit_logs', 'append_only_excluded',
      'push_credentials', 'security_credentials_excluded'
    ),
    'profiles', coalesce((
      select jsonb_agg(to_jsonb(p) order by p.id)
      from tenant_profiles p
    ), '[]'::jsonb),
    'debts', coalesce((
      select jsonb_agg(to_jsonb(d) order by d.id)
      from tenant_debts d
    ), '[]'::jsonb),
    'payments', coalesce((
      select jsonb_agg(to_jsonb(pay) order by pay.id)
      from tenant_payments pay
    ), '[]'::jsonb),
    'general_payments', coalesce((
      select jsonb_agg(to_jsonb(g) order by g.id)
      from tenant_general_payments g
    ), '[]'::jsonb),
    'employee_permissions', coalesce((
      select jsonb_agg(to_jsonb(ep) order by ep.employee_id)
      from public.employee_permissions ep
      where ep.admin_id = p_admin_id
    ), '[]'::jsonb),
    'market_receipt_settings', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.admin_id)
      from public.market_receipt_settings s
      where s.admin_id = p_admin_id
    ), '[]'::jsonb),
    'customer_notification_preferences', coalesce((
      select jsonb_agg(to_jsonb(pref) order by pref.customer_id)
      from public.customer_notification_preferences pref
      where pref.market_id = p_admin_id
    ), '[]'::jsonb),
    'market_notification_settings', coalesce((
      select jsonb_agg(to_jsonb(s) order by s.market_id)
      from public.market_notification_settings s
      where s.market_id = p_admin_id
    ), '[]'::jsonb),
    'debt_installments', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.id)
      from tenant_installments i
    ), '[]'::jsonb),
    'receipt_documents', coalesce((
      select jsonb_agg(to_jsonb(d) order by d.id)
      from public.receipt_documents d
      where d.admin_id = p_admin_id
    ), '[]'::jsonb),
    'receipt_template_versions', coalesce((
      select jsonb_agg(to_jsonb(v) order by v.id)
      from public.receipt_template_versions v
      where v.admin_id = p_admin_id
    ), '[]'::jsonb)
  );
$function$;
CREATE OR REPLACE FUNCTION private.create_tenant_backup_impl(p_label text, p_type text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  tenant_id uuid;
  backup_id uuid;
  snapshot jsonb;
  counts jsonb;
  checksum text;
begin
  if private."current_role"() <> 'admin' then
    raise exception 'admin_required' using errcode='42501';
  end if;
  if p_type not in ('manual','automatic','before_restore') then
    raise exception 'invalid_backup_type' using errcode='22023';
  end if;
  tenant_id := private.current_admin_id();
  snapshot := private.build_tenant_backup_snapshot(tenant_id);
  counts := private.backup_snapshot_counts(snapshot);
  checksum := encode(extensions.digest(snapshot::text,'sha256'),'hex');
  insert into public.tenant_backups(
    admin_id, created_by, label, backup_type, payload,
    record_counts, payload_sha256, expires_at
  )
  values(
    tenant_id, auth.uid(),
    left(coalesce(nullif(trim(p_label),''),'Backup'),120),
    p_type, snapshot, counts, checksum,
    case when p_type='automatic' then now()+interval '7 days' else null end
  )
  returning id into backup_id;
  insert into public.audit_logs(
    admin_id, actor_id, action, entity_type, entity_id, after_data
  )
  values(
    tenant_id, auth.uid(), 'backup', 'tenant_backups', backup_id::text,
    counts || jsonb_build_object(
      'backup_version', 2, 'payload_sha256', checksum
    )
  );
  return backup_id;
end;
$function$;
CREATE OR REPLACE FUNCTION private.create_tenant_backup_for_admin(p_admin_id uuid, p_label text DEFAULT 'Automatic daily backup'::text, p_type text DEFAULT 'automatic'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  backup_id uuid;
  snapshot jsonb;
  counts jsonb;
  checksum text;
begin
  if p_type not in ('automatic','before_restore') then
    raise exception 'service_backup_type_not_allowed' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.profiles p
    where p.id=p_admin_id and p.role='admin'
  ) then
    raise exception 'admin_not_found' using errcode='P0002';
  end if;
  if p_type='automatic' then
    select b.id into backup_id
    from public.tenant_backups b
    where b.admin_id=p_admin_id
      and b.backup_type='automatic'
      and b.created_at>=date_trunc('day',now())
      and coalesce((b.payload->>'version')::integer,0)=2
    order by b.created_at desc
    limit 1;
    if backup_id is not null then return backup_id; end if;
  end if;
  snapshot := private.build_tenant_backup_snapshot(p_admin_id);
  counts := private.backup_snapshot_counts(snapshot);
  checksum := encode(extensions.digest(snapshot::text,'sha256'),'hex');
  insert into public.tenant_backups(
    admin_id, created_by, label, backup_type, payload,
    record_counts, payload_sha256, expires_at
  )
  values(
    p_admin_id, null,
    left(coalesce(nullif(trim(p_label),''),'Automatic backup'),120),
    p_type, snapshot, counts, checksum,
    case when p_type='automatic' then now()+interval '7 days' else null end
  )
  returning id into backup_id;
  insert into public.audit_logs(
    admin_id, actor_id, action, entity_type, entity_id, after_data
  )
  values(
    p_admin_id, null, 'backup', 'tenant_backups', backup_id::text,
    counts || jsonb_build_object(
      'backup_version', 2, 'backup_type', p_type,
      'automatic', true, 'payload_sha256', checksum
    )
  );
  return backup_id;
end;
$function$;
CREATE OR REPLACE FUNCTION private.verify_tenant_backup_for_admin(p_backup_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  snapshot jsonb;
  expected_counts jsonb;
  stored_checksum text;
  calculated_checksum text;
  actual_counts jsonb;
  v_version integer := 0;
  structure_valid boolean := false;
  counts_valid boolean := false;
  checksum_valid boolean := false;
  profiles_valid boolean := false;
  identities_available boolean := false;
  debts_valid boolean := false;
  debt_financial_valid boolean := false;
  payments_valid boolean := false;
  payment_amounts_valid boolean := false;
  general_payments_valid boolean := true;
  permissions_valid boolean := false;
  settings_valid boolean := true;
  preferences_valid boolean := true;
  installments_valid boolean := true;
  receipt_history_valid boolean := true;
  restorable boolean := false;
  result jsonb;
begin
  select b.payload,b.record_counts,b.payload_sha256
    into snapshot,expected_counts,stored_checksum
  from public.tenant_backups b
  where b.id=p_backup_id and b.admin_id=p_admin_id;
  if snapshot is null then
    raise exception 'backup_not_found' using errcode='P0002';
  end if;
  v_version := coalesce((snapshot->>'version')::integer,0);
  if v_version = 1 then
    structure_valid :=
      jsonb_typeof(snapshot->'profiles')='array'
      and jsonb_typeof(snapshot->'debts')='array'
      and jsonb_typeof(snapshot->'payments')='array'
      and jsonb_typeof(snapshot->'employee_permissions')='array';
  elsif v_version = 2 then
    structure_valid :=
      jsonb_typeof(snapshot->'profiles')='array'
      and jsonb_typeof(snapshot->'debts')='array'
      and jsonb_typeof(snapshot->'payments')='array'
      and jsonb_typeof(snapshot->'general_payments')='array'
      and jsonb_typeof(snapshot->'employee_permissions')='array'
      and jsonb_typeof(snapshot->'market_receipt_settings')='array'
      and jsonb_typeof(snapshot->'customer_notification_preferences')='array'
      and jsonb_typeof(snapshot->'market_notification_settings')='array'
      and jsonb_typeof(snapshot->'debt_installments')='array'
      and jsonb_typeof(snapshot->'receipt_documents')='array'
      and jsonb_typeof(snapshot->'receipt_template_versions')='array';
  end if;

  if structure_valid then
    actual_counts := private.backup_snapshot_counts(snapshot);
    counts_valid := actual_counts = expected_counts;
    select not exists(
      select 1
      from jsonb_to_recordset(snapshot->'profiles')
        as p(id uuid, role text, admin_id uuid)
      where (p.id = p_admin_id and p.role is distinct from 'admin')
        or (p.id <> p_admin_id and (
          p.role not in ('customer','employee')
          or p.admin_id is distinct from p_admin_id
        ))
    ) into profiles_valid;
    select not exists(
      select 1
      from jsonb_to_recordset(snapshot->'profiles')
        as saved(id uuid, role text, admin_id uuid)
      left join public.profiles live on live.id=saved.id
      where live.id is null
        or live.role is distinct from saved.role
        or live.admin_id is distinct from saved.admin_id
    ) into identities_available;
    select not exists(
      select 1
      from jsonb_to_recordset(snapshot->'debts')
        as d(id uuid,customer_id uuid,amount numeric,remaining numeric,status text)
      left join jsonb_to_recordset(snapshot->'profiles')
        as p(id uuid) on p.id=d.customer_id
      where p.id is null
    ) into debts_valid;
    select not exists(
      select 1
      from jsonb_to_recordset(snapshot->'debts')
        as d(amount numeric,remaining numeric,status text)
      where d.amount is null or d.amount<=0
        or d.remaining is null or d.remaining<0 or d.remaining>d.amount
        or d.status is distinct from case
          when d.remaining=0 then 'paid'
          when d.remaining<d.amount then 'partial'
          else 'pending'
        end
    ) into debt_financial_valid;
    select not exists(
      select 1
      from jsonb_to_recordset(snapshot->'payments')
        as pay(id uuid,debt_id uuid)
      left join jsonb_to_recordset(snapshot->'debts')
        as d(id uuid) on d.id=pay.debt_id
      where d.id is null
    ) into payments_valid;
    select not exists(
      select 1
      from jsonb_to_recordset(snapshot->'payments')
        as pay(amount numeric)
      where pay.amount is null or pay.amount<=0
    ) into payment_amounts_valid;
    select not exists(
      select 1
      from jsonb_to_recordset(snapshot->'employee_permissions')
        as ep(employee_id uuid,admin_id uuid)
      left join jsonb_to_recordset(snapshot->'profiles')
        as p(id uuid,role text,admin_id uuid) on p.id=ep.employee_id
      where ep.admin_id is distinct from p_admin_id
        or p.id is null or p.role is distinct from 'employee'
        or p.admin_id is distinct from p_admin_id
    ) into permissions_valid;

    if v_version = 2 then
      select not exists(
        select 1
        from jsonb_to_recordset(snapshot->'general_payments')
          as g(id uuid,admin_id uuid,customer_id uuid,amount numeric)
        left join jsonb_to_recordset(snapshot->'profiles')
          as p(id uuid,role text,admin_id uuid) on p.id=g.customer_id
        where g.admin_id is distinct from p_admin_id
          or g.amount is null or g.amount<=0
          or p.id is null or p.role is distinct from 'customer'
          or p.admin_id is distinct from p_admin_id
      ) into general_payments_valid;
      select
        not exists(
          select 1
          from jsonb_to_recordset(snapshot->'market_receipt_settings')
            as s(admin_id uuid)
          where s.admin_id is distinct from p_admin_id
        )
        and not exists(
          select 1
          from jsonb_to_recordset(snapshot->'market_notification_settings')
            as s(market_id uuid)
          where s.market_id is distinct from p_admin_id
        )
      into settings_valid;
      select not exists(
        select 1
        from jsonb_to_recordset(snapshot->'customer_notification_preferences')
          as pref(customer_id uuid,market_id uuid)
        left join jsonb_to_recordset(snapshot->'profiles')
          as p(id uuid,role text,admin_id uuid) on p.id=pref.customer_id
        where pref.market_id is distinct from p_admin_id
          or p.id is null or p.role is distinct from 'customer'
          or p.admin_id is distinct from p_admin_id
      ) into preferences_valid;
      select not exists(
        select 1
        from jsonb_to_recordset(snapshot->'debt_installments')
          as i(id uuid,admin_id uuid,customer_id uuid,debt_id uuid,amount numeric)
        left join jsonb_to_recordset(snapshot->'profiles')
          as p(id uuid,role text,admin_id uuid) on p.id=i.customer_id
        left join jsonb_to_recordset(snapshot->'debts')
          as d(id uuid,customer_id uuid) on d.id=i.debt_id
        where i.admin_id is distinct from p_admin_id
          or i.amount is null or i.amount<=0
          or p.id is null or p.role is distinct from 'customer'
          or p.admin_id is distinct from p_admin_id
          or d.id is null or d.customer_id is distinct from i.customer_id
      ) into installments_valid;
      select
        not exists(
          select 1
          from jsonb_to_recordset(snapshot->'receipt_documents')
            as d(admin_id uuid)
          where d.admin_id is distinct from p_admin_id
        )
        and not exists(
          select 1
          from jsonb_to_recordset(snapshot->'receipt_template_versions')
            as v(admin_id uuid)
          where v.admin_id is distinct from p_admin_id
        )
      into receipt_history_valid;
    end if;
  else
    actual_counts := '{}'::jsonb;
  end if;

  calculated_checksum:=encode(extensions.digest(snapshot::text,'sha256'),'hex');
  checksum_valid:=stored_checksum is not null and stored_checksum=calculated_checksum;
  restorable :=
    structure_valid and counts_valid and checksum_valid
    and profiles_valid and identities_available
    and debts_valid and debt_financial_valid
    and payments_valid and payment_amounts_valid
    and permissions_valid and general_payments_valid
    and settings_valid and preferences_valid
    and installments_valid and receipt_history_valid;

  result:=jsonb_build_object(
    'restorable',restorable,'backup_version',v_version,
    'structure_valid',structure_valid,'counts_valid',counts_valid,
    'checksum_valid',checksum_valid,'profiles_valid',profiles_valid,
    'identities_available',identities_available,'debts_valid',debts_valid,
    'debt_financial_valid',debt_financial_valid,
    'payments_valid',payments_valid,
    'payment_amounts_valid',payment_amounts_valid,
    'general_payments_valid',general_payments_valid,
    'permissions_valid',permissions_valid,'settings_valid',settings_valid,
    'preferences_valid',preferences_valid,
    'installments_valid',installments_valid,
    'receipt_history_valid',receipt_history_valid,
    'record_counts',actual_counts,'verified_at',now()
  );
  update public.tenant_backups
  set last_verified_at=now(),verification=result
  where id=p_backup_id and admin_id=p_admin_id;
  return result;
end;
$function$;
CREATE OR REPLACE FUNCTION private.restore_tenant_backup_impl(p_backup_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  tenant_id uuid;
  snapshot jsonb;
  v_version integer;
  verification_result jsonb;
  permission_rows jsonb;
  safety_backup uuid;
  changed_profiles integer := 0;
  disabled_new_profiles integer := 0;
  removed_extra_payments integer := 0;
  removed_extra_general_payments integer := 0;
  archived_extra_debts integer := 0;
  restored_debts integer := 0;
  restored_payments integer := 0;
  restored_general_payments integer := 0;
  restored_permissions integer := 0;
  restored_receipt_settings integer := 0;
  restored_notification_preferences integer := 0;
  restored_notification_settings integer := 0;
  restored_installments integer := 0;
  restored_receipt_documents integer := 0;
  restored_receipt_versions integer := 0;
begin
  if private."current_role"()<>'admin' then
    raise exception 'admin_required' using errcode='42501';
  end if;
  tenant_id:=private.current_admin_id();
  perform 1 from public.profiles p
  where p.id=tenant_id and p.role='admin' for update;

  select b.payload into snapshot
  from public.tenant_backups b
  where b.id=p_backup_id and b.admin_id=tenant_id
  for share;
  if snapshot is null then
    raise exception 'backup_not_found' using errcode='P0002';
  end if;
  v_version:=coalesce((snapshot->>'version')::integer,0);
  verification_result:=private.verify_tenant_backup_for_admin(
    p_backup_id,tenant_id
  );
  if coalesce((verification_result->>'restorable')::boolean,false) is not true then
    raise exception 'backup_failed_restore_verification' using errcode='22023';
  end if;

  safety_backup:=public.create_tenant_backup(
    'Automatic safety backup before restore','before_restore'
  );
  perform set_config('zhirox.backup_restore','on',true);

  if v_version = 2 then
    update public.profiles live
    set name=saved.name,
        father_name=saved.father_name,
        grandfather_name=saved.grandfather_name,
        market_name=case when live.id=tenant_id then saved.market_name else live.market_name end,
        approved=case when live.id=tenant_id then live.approved else saved.approved end,
        active=case when live.id=tenant_id then live.active else saved.active end,
        debt_limit=case when live.id=tenant_id then live.debt_limit else saved.debt_limit end,
        debt_duration=case when live.id=tenant_id then live.debt_duration else saved.debt_duration end,
        can_add_customers=case when live.id=tenant_id then live.can_add_customers else saved.can_add_customers end,
        can_set_debt_limit=case when live.id=tenant_id then live.can_set_debt_limit else saved.can_set_debt_limit end,
        can_set_due_date=case when live.id=tenant_id then live.can_set_due_date else saved.can_set_due_date end,
        can_edit_debts=case when live.id=tenant_id then live.can_edit_debts else saved.can_edit_debts end,
        can_send_notifications=case when live.id=tenant_id then live.can_send_notifications else saved.can_send_notifications end,
        can_view_customers=case when live.id=tenant_id then live.can_view_customers else saved.can_view_customers end,
        can_edit_customers=case when live.id=tenant_id then live.can_edit_customers else saved.can_edit_customers end,
        can_delete_customers=case when live.id=tenant_id then live.can_delete_customers else saved.can_delete_customers end,
        can_view_debts=case when live.id=tenant_id then live.can_view_debts else saved.can_view_debts end,
        can_add_debts=case when live.id=tenant_id then live.can_add_debts else saved.can_add_debts end,
        can_delete_debts=case when live.id=tenant_id then live.can_delete_debts else saved.can_delete_debts end,
        can_record_payments=case when live.id=tenant_id then live.can_record_payments else saved.can_record_payments end,
        can_view_financial_reports=case when live.id=tenant_id then live.can_view_financial_reports else saved.can_view_financial_reports end,
        can_export_data=case when live.id=tenant_id then live.can_export_data else saved.can_export_data end,
        can_import_data=case when live.id=tenant_id then live.can_import_data else saved.can_import_data end,
        is_pinned=case when live.id=tenant_id then live.is_pinned else saved.is_pinned end,
        pinned_at=case when live.id=tenant_id then live.pinned_at else saved.pinned_at end,
        is_vip=case when live.id=tenant_id then live.is_vip else saved.is_vip end,
        updated_at=now()
    from jsonb_to_recordset(snapshot->'profiles') as saved(
      id uuid,name text,father_name text,grandfather_name text,market_name text,
      approved boolean,active boolean,debt_limit numeric,debt_duration integer,
      can_add_customers boolean,can_set_debt_limit boolean,can_set_due_date boolean,
      can_edit_debts boolean,can_send_notifications boolean,
      can_view_customers boolean,can_edit_customers boolean,
      can_delete_customers boolean,can_view_debts boolean,can_add_debts boolean,
      can_delete_debts boolean,can_record_payments boolean,
      can_view_financial_reports boolean,can_export_data boolean,
      can_import_data boolean,is_pinned boolean,pinned_at timestamptz,is_vip boolean
    )
    where live.id=saved.id
      and (live.id=tenant_id or live.admin_id=tenant_id);
    get diagnostics changed_profiles=row_count;

    update public.profiles p
    set active=false,approved=false,is_pinned=false,pinned_at=null,updated_at=now()
    where p.admin_id=tenant_id
      and p.role in ('customer','employee')
      and not exists(
        select 1 from jsonb_to_recordset(snapshot->'profiles') as saved(id uuid)
        where saved.id=p.id
      );
    get diagnostics disabled_new_profiles=row_count;

    delete from public.customer_general_payments g
    where g.admin_id=tenant_id
      and not exists(
        select 1 from jsonb_to_recordset(snapshot->'general_payments') as saved(id uuid)
        where saved.id=g.id
      );
    get diagnostics removed_extra_general_payments=row_count;
  end if;

  delete from public.payments pay
  using public.debts d
  where pay.debt_id=d.id
    and private.profile_tenant_id(d.customer_id)=tenant_id
    and not exists(
      select 1 from jsonb_to_recordset(snapshot->'payments') as saved(id uuid)
      where saved.id=pay.id
    );
  get diagnostics removed_extra_payments=row_count;

  update public.debts d
  set is_deleted=true,
      deleted_at=coalesce(d.deleted_at,now()),
      deleted_by=coalesce(d.deleted_by,auth.uid()),
      updated_at=now()
  where private.profile_tenant_id(d.customer_id)=tenant_id
    and not exists(
      select 1 from jsonb_to_recordset(snapshot->'debts') as saved(id uuid)
      where saved.id=d.id
    )
    and d.is_deleted=false;
  get diagnostics archived_extra_debts=row_count;

  restored_debts:=private.restore_backup_rows_bulk(
    'public.debts'::regclass,snapshot->'debts','id',array['updated_at']
  );
  restored_payments:=private.restore_backup_rows_bulk(
    'public.payments'::regclass,snapshot->'payments','id','{}'::text[]
  );

  if v_version = 2 then
    restored_general_payments:=private.restore_backup_rows_bulk(
      'public.customer_general_payments'::regclass,
      snapshot->'general_payments','id','{}'::text[]
    );

    delete from public.debt_installments i
    where i.admin_id=tenant_id
      and not exists(
        select 1 from jsonb_to_recordset(snapshot->'debt_installments') as saved(id uuid)
        where saved.id=i.id
      );
    restored_installments:=private.restore_backup_rows_bulk(
      'public.debt_installments'::regclass,
      snapshot->'debt_installments','id','{}'::text[]
    );

    delete from public.employee_permissions ep
    where ep.admin_id=tenant_id
      and not exists(
        select 1 from jsonb_to_recordset(snapshot->'employee_permissions')
          as saved(employee_id uuid)
        where saved.employee_id=ep.employee_id
      );
    select coalesce(
      jsonb_agg(value||jsonb_build_object(
        'updated_by',auth.uid(),'updated_at',now()
      )),
      '[]'::jsonb
    )
    into permission_rows
    from jsonb_array_elements(snapshot->'employee_permissions');
    restored_permissions:=private.restore_backup_rows_bulk(
      'public.employee_permissions'::regclass,
      permission_rows,'employee_id','{}'::text[]
    );

    delete from public.market_receipt_settings s
    where s.admin_id=tenant_id
      and jsonb_array_length(snapshot->'market_receipt_settings')=0;
    restored_receipt_settings:=private.restore_backup_rows_bulk(
      'public.market_receipt_settings'::regclass,
      snapshot->'market_receipt_settings','admin_id','{}'::text[]
    );

    delete from public.customer_notification_preferences pref
    where pref.market_id=tenant_id
      and not exists(
        select 1
        from jsonb_to_recordset(snapshot->'customer_notification_preferences')
          as saved(customer_id uuid)
        where saved.customer_id=pref.customer_id
      );
    restored_notification_preferences:=private.restore_backup_rows_bulk(
      'public.customer_notification_preferences'::regclass,
      snapshot->'customer_notification_preferences','customer_id','{}'::text[]
    );

    delete from public.market_notification_settings s
    where s.market_id=tenant_id
      and jsonb_array_length(snapshot->'market_notification_settings')=0;
    restored_notification_settings:=private.restore_backup_rows_bulk(
      'public.market_notification_settings'::regclass,
      snapshot->'market_notification_settings','market_id','{}'::text[]
    );

    restored_receipt_documents:=private.restore_backup_rows_bulk(
      'public.receipt_documents'::regclass,
      snapshot->'receipt_documents','id','{}'::text[]
    );
    restored_receipt_versions:=private.restore_backup_rows_bulk(
      'public.receipt_template_versions'::regclass,
      snapshot->'receipt_template_versions','id','{}'::text[]
    );
  else
    select coalesce(
      jsonb_agg(value||jsonb_build_object(
        'updated_by',auth.uid(),'updated_at',now()
      )),
      '[]'::jsonb
    )
    into permission_rows
    from jsonb_array_elements(snapshot->'employee_permissions');
    restored_permissions:=private.restore_backup_rows_bulk(
      'public.employee_permissions'::regclass,
      permission_rows,'employee_id','{}'::text[]
    );
  end if;

  perform set_config('zhirox.backup_restore','off',true);

  insert into public.audit_logs(
    admin_id,actor_id,action,entity_type,entity_id,after_data
  )
  values(
    tenant_id,auth.uid(),'backup_restore','tenant_backups',p_backup_id::text,
    jsonb_build_object(
      'backup_version',v_version,'safety_backup_id',safety_backup,
      'profile_rows_changed',changed_profiles,
      'new_profiles_disabled',disabled_new_profiles,
      'extra_payments_removed',removed_extra_payments,
      'extra_general_payments_removed',removed_extra_general_payments,
      'extra_debts_archived',archived_extra_debts,
      'debt_rows_changed',restored_debts,
      'payment_rows_changed',restored_payments,
      'general_payment_rows_changed',restored_general_payments,
      'permission_rows_changed',restored_permissions,
      'receipt_settings_rows_changed',restored_receipt_settings,
      'notification_preferences_rows_changed',restored_notification_preferences,
      'notification_settings_rows_changed',restored_notification_settings,
      'installment_rows_changed',restored_installments,
      'receipt_document_rows_changed',restored_receipt_documents,
      'receipt_template_version_rows_changed',restored_receipt_versions,
      'source_counts',verification_result->'record_counts'
    )
  );

  return jsonb_build_object(
    'success',true,'backup_version',v_version,'safety_backup_id',safety_backup,
    'profile_rows_changed',changed_profiles,
    'new_profiles_disabled',disabled_new_profiles,
    'extra_payments_removed',removed_extra_payments,
    'extra_general_payments_removed',removed_extra_general_payments,
    'extra_debts_archived',archived_extra_debts,
    'debt_rows_changed',restored_debts,
    'payment_rows_changed',restored_payments,
    'general_payment_rows_changed',restored_general_payments,
    'permission_rows_changed',restored_permissions,
    'receipt_settings_rows_changed',restored_receipt_settings,
    'notification_preferences_rows_changed',restored_notification_preferences,
    'notification_settings_rows_changed',restored_notification_settings,
    'installment_rows_changed',restored_installments,
    'receipt_document_rows_changed',restored_receipt_documents,
    'receipt_template_version_rows_changed',restored_receipt_versions,
    'source_counts',verification_result->'record_counts'
  );
exception when others then
  perform set_config('zhirox.backup_restore','off',true);
  raise;
end;
$function$;
CREATE OR REPLACE FUNCTION private.get_tenant_export_impl()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  tenant_id uuid;
  snapshot jsonb;
begin
  if private."current_role"() <> 'admin'
     and not private.employee_has_permission('export_data') then
    raise exception 'export_permission_required' using errcode='42501';
  end if;
  tenant_id:=private.current_admin_id();
  snapshot:=private.build_tenant_backup_snapshot(tenant_id);
  return snapshot||jsonb_build_object('exported_at',now(),'export_version',2);
end;
$function$;
CREATE OR REPLACE FUNCTION private.run_all_tenant_backups()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_ok integer:=0; v_errors integer:=0;
begin
  for r in
    select p.id as admin_id
    from public.profiles p
    where p.role='admin' and coalesce(p.is_system_owner,false)=false
    order by p.id
  loop
    begin
      perform private.run_scheduled_tenant_backup(r.admin_id);
      v_ok:=v_ok+1;
    exception when others then
      v_errors:=v_errors+1;
    end;
  end loop;
  return jsonb_build_object(
    'backed_up_tenants',v_ok,'backup_errors',v_errors,
    'scope','all_non_owner_admin_tenants'
  );
end;
$function$;
revoke all on function private.backup_snapshot_counts(jsonb)
  from public, anon, authenticated;
revoke all on function private.build_tenant_backup_snapshot(uuid)
  from public, anon, authenticated;

revoke all on function private.create_tenant_backup_for_admin(uuid,text,text)
  from public, anon, authenticated;
grant execute on function private.create_tenant_backup_for_admin(uuid,text,text)
  to service_role;

revoke all on function private.verify_tenant_backup_for_admin(uuid,uuid)
  from public, anon, authenticated;
grant execute on function private.verify_tenant_backup_for_admin(uuid,uuid)
  to service_role;

revoke all on function private.restore_tenant_backup_impl(uuid)
  from public, anon;
grant execute on function private.restore_tenant_backup_impl(uuid)
  to authenticated, service_role;

revoke all on function private.get_tenant_export_impl()
  from public, anon;
grant execute on function private.get_tenant_export_impl()
  to authenticated, service_role;

revoke all on function private.run_all_tenant_backups()
  from public, anon, authenticated;
grant execute on function private.run_all_tenant_backups()
  to service_role;

do $block$
declare v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job where jobname='daily-daftar-tenant-backup-all' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;

  select jobid into v_jobid
  from cron.job where jobname='daily-tenant-backup-all' limit 1;
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;

  perform cron.schedule(
    'daily-tenant-backup-all',
    '30 2 * * *',
    $cron$select private.run_all_tenant_backups();$cron$
  );
end
$block$;