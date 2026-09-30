alter table public.profiles
  add column if not exists can_view_customer_phone boolean not null default false,
  add column if not exists can_view_customer_notes boolean not null default false,
  add column if not exists can_edit_customer_notes boolean not null default false,
  add column if not exists can_view_customer_balances boolean not null default false,
  add column if not exists can_view_payment_history boolean not null default false,
  add column if not exists can_create_receipts boolean not null default false,
  add column if not exists can_edit_receipts boolean not null default false,
  add column if not exists can_delete_receipts boolean not null default false,
  add column if not exists can_export_receipts boolean not null default false,
  add column if not exists can_view_report_summary boolean not null default false,
  add column if not exists can_export_reports boolean not null default false,
  add column if not exists can_view_sync_logs boolean not null default false,
  add column if not exists can_retry_failed_sync boolean not null default false,
  add column if not exists can_run_manual_backup boolean not null default false,
  add column if not exists can_restore_backup boolean not null default false,
  add column if not exists can_manage_notification_templates boolean not null default false,
  add column if not exists can_send_bulk_notifications boolean not null default false,
  add column if not exists can_manage_market_rate_refresh boolean not null default false,
  add column if not exists can_manage_security_settings boolean not null default false;

alter table public.employee_permissions
  add column if not exists can_view_customer_phone boolean not null default false,
  add column if not exists can_view_customer_notes boolean not null default false,
  add column if not exists can_edit_customer_notes boolean not null default false,
  add column if not exists can_view_customer_balances boolean not null default false,
  add column if not exists can_view_payment_history boolean not null default false,
  add column if not exists can_create_receipts boolean not null default false,
  add column if not exists can_edit_receipts boolean not null default false,
  add column if not exists can_delete_receipts boolean not null default false,
  add column if not exists can_export_receipts boolean not null default false,
  add column if not exists can_view_report_summary boolean not null default false,
  add column if not exists can_export_reports boolean not null default false,
  add column if not exists can_view_sync_logs boolean not null default false,
  add column if not exists can_retry_failed_sync boolean not null default false,
  add column if not exists can_run_manual_backup boolean not null default false,
  add column if not exists can_restore_backup boolean not null default false,
  add column if not exists can_manage_notification_templates boolean not null default false,
  add column if not exists can_send_bulk_notifications boolean not null default false,
  add column if not exists can_manage_market_rate_refresh boolean not null default false,
  add column if not exists can_manage_security_settings boolean not null default false;

create or replace function private.employee_has_permission(permission_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  permission_key text;
  allowed boolean := false;
begin
  if private.current_role() = 'admin' then return true; end if;
  if private.current_role() <> 'employee' then return false; end if;
  permission_key := case
    when permission_name like 'can\_%' escape '\\' then permission_name
    else 'can_' || permission_name
  end;
  if permission_key !~ '^can_[a-z0-9_]+$' then return false; end if;
  select coalesce((to_jsonb(ep)->>permission_key)::boolean, false)
    into allowed
  from public.employee_permissions ep
  where ep.employee_id = auth.uid()
    and ep.admin_id = private.current_admin_id();
  return coalesce(allowed, false);
exception
  when invalid_text_representation then return false;
end;
$$;

create or replace function public.set_employee_permissions_v2(p_employee_id uuid, p_permissions jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  requester public.profiles%rowtype;
  allowed_columns constant text[] := array[
    'can_view_customers','can_add_customers','can_edit_customers','can_delete_customers',
    'can_view_debts','can_add_debts','can_edit_debts','can_delete_debts',
    'can_record_payments','can_view_financial_reports','can_export_data','can_send_notifications',
    'can_set_debt_limit','can_set_due_date','can_import_data','can_refund_payments','can_restore_debts',
    'can_manage_receipts','can_manage_notifications','can_approve_customers','can_manage_employees',
    'can_view_audit_log','can_manage_backup','can_manage_daftar_sync','can_manage_subscription',
    'can_view_dashboard','can_view_recent_activity','can_view_transactions','can_edit_payments',
    'can_delete_payments','can_create_statements','can_manage_customer_links','can_pin_customers',
    'can_manage_vip_customers','can_merge_customer_identities','can_view_market_rates',
    'can_view_intelligence','can_manage_collections','can_view_expiry','can_manage_expiry','can_manage_settings',
    'can_view_customer_phone','can_view_customer_notes','can_edit_customer_notes','can_view_customer_balances',
    'can_view_payment_history','can_create_receipts','can_edit_receipts','can_delete_receipts','can_export_receipts',
    'can_view_report_summary','can_export_reports','can_view_sync_logs','can_retry_failed_sync',
    'can_run_manual_backup','can_restore_backup','can_manage_notification_templates','can_send_bulk_notifications',
    'can_manage_market_rate_refresh','can_manage_security_settings'
  ];
  invalid_key text;
  invalid_type text;
  set_clause text;
begin
  if auth.uid() is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  select * into requester from public.profiles where id = auth.uid();
  if requester.id is null or requester.role <> 'admin' or requester.active is not true or requester.approved is not true then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = p_employee_id and p.role = 'employee' and p.admin_id = requester.id
  ) then
    raise exception 'employee_not_found_or_forbidden' using errcode = '42501';
  end if;
  if p_permissions is null or jsonb_typeof(p_permissions) <> 'object' then
    raise exception 'invalid_permissions_payload' using errcode = '22023';
  end if;
  select key into invalid_key from jsonb_object_keys(p_permissions) key where not (key = any(allowed_columns)) limit 1;
  if invalid_key is not null then raise exception 'unknown_permission:%', invalid_key using errcode = '22023'; end if;
  select e.key into invalid_type from jsonb_each(p_permissions) e where jsonb_typeof(e.value) <> 'boolean' limit 1;
  if invalid_type is not null then raise exception 'permission_must_be_boolean:%', invalid_type using errcode = '22023'; end if;
  select string_agg(format('%I = %L::boolean', e.key, e.value #>> '{}'), ', ') into set_clause from jsonb_each(p_permissions) e;
  if set_clause is null or btrim(set_clause) = '' then return; end if;
  execute format('update public.profiles set %s, updated_at = now() where id = $1', set_clause) using p_employee_id;
  execute format('update public.employee_permissions set %s, updated_at = now(), updated_by = $1 where employee_id = $2 and admin_id = $1', set_clause)
    using requester.id, p_employee_id;
end;
$$;

revoke all on function public.set_employee_permissions_v2(uuid, jsonb) from public, anon;
grant execute on function public.set_employee_permissions_v2(uuid, jsonb) to authenticated;
