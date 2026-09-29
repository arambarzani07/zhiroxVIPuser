alter table public.profiles
  add column if not exists can_view_expiry boolean not null default false;

alter table public.employee_permissions
  add column if not exists can_set_debt_limit boolean not null default false,
  add column if not exists can_set_due_date boolean not null default false,
  add column if not exists can_import_data boolean not null default false,
  add column if not exists can_refund_payments boolean not null default false,
  add column if not exists can_restore_debts boolean not null default false,
  add column if not exists can_manage_receipts boolean not null default false,
  add column if not exists can_manage_notifications boolean not null default false,
  add column if not exists can_approve_customers boolean not null default false,
  add column if not exists can_manage_employees boolean not null default false,
  add column if not exists can_view_audit_log boolean not null default false,
  add column if not exists can_manage_backup boolean not null default false,
  add column if not exists can_manage_daftar_sync boolean not null default false,
  add column if not exists can_manage_subscription boolean not null default false,
  add column if not exists can_view_dashboard boolean not null default true,
  add column if not exists can_view_recent_activity boolean not null default true,
  add column if not exists can_view_transactions boolean not null default false,
  add column if not exists can_edit_payments boolean not null default false,
  add column if not exists can_delete_payments boolean not null default false,
  add column if not exists can_create_statements boolean not null default false,
  add column if not exists can_manage_customer_links boolean not null default false,
  add column if not exists can_pin_customers boolean not null default false,
  add column if not exists can_manage_vip_customers boolean not null default false,
  add column if not exists can_merge_customer_identities boolean not null default false,
  add column if not exists can_view_market_rates boolean not null default true,
  add column if not exists can_view_intelligence boolean not null default false,
  add column if not exists can_manage_collections boolean not null default false,
  add column if not exists can_manage_settings boolean not null default false;

create or replace function private.sync_employee_permissions_to_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;
  update public.profiles
  set can_view_customers = new.can_view_customers,
      can_add_customers = new.can_add_customers,
      can_edit_customers = new.can_edit_customers,
      can_delete_customers = new.can_delete_customers,
      can_view_debts = new.can_view_debts,
      can_add_debts = new.can_add_debts,
      can_edit_debts = new.can_edit_debts,
      can_delete_debts = new.can_delete_debts,
      can_record_payments = new.can_record_payments,
      can_view_financial_reports = new.can_view_financial_reports,
      can_export_data = new.can_export_data,
      can_send_notifications = new.can_send_notifications,
      can_set_debt_limit = new.can_set_debt_limit,
      can_set_due_date = new.can_set_due_date,
      can_import_data = new.can_import_data,
      can_refund_payments = new.can_refund_payments,
      can_restore_debts = new.can_restore_debts,
      can_manage_receipts = new.can_manage_receipts,
      can_manage_notifications = new.can_manage_notifications,
      can_approve_customers = new.can_approve_customers,
      can_manage_employees = new.can_manage_employees,
      can_view_audit_log = new.can_view_audit_log,
      can_manage_backup = new.can_manage_backup,
      can_manage_daftar_sync = new.can_manage_daftar_sync,
      can_manage_subscription = new.can_manage_subscription,
      can_view_dashboard = new.can_view_dashboard,
      can_view_recent_activity = new.can_view_recent_activity,
      can_view_transactions = new.can_view_transactions,
      can_edit_payments = new.can_edit_payments,
      can_delete_payments = new.can_delete_payments,
      can_create_statements = new.can_create_statements,
      can_manage_customer_links = new.can_manage_customer_links,
      can_pin_customers = new.can_pin_customers,
      can_manage_vip_customers = new.can_manage_vip_customers,
      can_merge_customer_identities = new.can_merge_customer_identities,
      can_view_market_rates = new.can_view_market_rates,
      can_view_intelligence = new.can_view_intelligence,
      can_manage_collections = new.can_manage_collections,
      can_view_expiry = new.can_view_expiry,
      can_manage_expiry = new.can_manage_expiry,
      can_manage_settings = new.can_manage_settings,
      updated_at = now()
  where id = new.employee_id
    and role = 'employee'
    and admin_id = new.admin_id;
  return new;
end;
$$;

create or replace function private.sync_profile_permissions_to_employee_permissions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if pg_trigger_depth() > 1 then return new; end if;

  if new.role = 'employee' and new.admin_id is not null then
    insert into public.employee_permissions (
      employee_id, admin_id,
      can_view_customers, can_add_customers, can_edit_customers, can_delete_customers,
      can_view_debts, can_add_debts, can_edit_debts, can_delete_debts,
      can_record_payments, can_view_financial_reports, can_export_data,
      can_send_notifications, can_set_debt_limit, can_set_due_date, can_import_data,
      can_refund_payments, can_restore_debts, can_manage_receipts,
      can_manage_notifications, can_approve_customers, can_manage_employees,
      can_view_audit_log, can_manage_backup, can_manage_daftar_sync,
      can_manage_subscription, can_view_dashboard, can_view_recent_activity,
      can_view_transactions, can_edit_payments, can_delete_payments,
      can_create_statements, can_manage_customer_links, can_pin_customers,
      can_manage_vip_customers, can_merge_customer_identities,
      can_view_market_rates, can_view_intelligence, can_manage_collections,
      can_view_expiry, can_manage_expiry, can_manage_settings,
      updated_at, updated_by
    ) values (
      new.id, new.admin_id,
      new.can_view_customers, new.can_add_customers, new.can_edit_customers, new.can_delete_customers,
      new.can_view_debts, new.can_add_debts, new.can_edit_debts, new.can_delete_debts,
      new.can_record_payments, new.can_view_financial_reports, new.can_export_data,
      new.can_send_notifications, new.can_set_debt_limit, new.can_set_due_date, new.can_import_data,
      new.can_refund_payments, new.can_restore_debts, new.can_manage_receipts,
      new.can_manage_notifications, new.can_approve_customers, new.can_manage_employees,
      new.can_view_audit_log, new.can_manage_backup, new.can_manage_daftar_sync,
      new.can_manage_subscription, new.can_view_dashboard, new.can_view_recent_activity,
      new.can_view_transactions, new.can_edit_payments, new.can_delete_payments,
      new.can_create_statements, new.can_manage_customer_links, new.can_pin_customers,
      new.can_manage_vip_customers, new.can_merge_customer_identities,
      new.can_view_market_rates, new.can_view_intelligence, new.can_manage_collections,
      new.can_view_expiry, new.can_manage_expiry, new.can_manage_settings,
      now(), auth.uid()
    )
    on conflict (employee_id) do update set
      admin_id = excluded.admin_id,
      can_view_customers = excluded.can_view_customers,
      can_add_customers = excluded.can_add_customers,
      can_edit_customers = excluded.can_edit_customers,
      can_delete_customers = excluded.can_delete_customers,
      can_view_debts = excluded.can_view_debts,
      can_add_debts = excluded.can_add_debts,
      can_edit_debts = excluded.can_edit_debts,
      can_delete_debts = excluded.can_delete_debts,
      can_record_payments = excluded.can_record_payments,
      can_view_financial_reports = excluded.can_view_financial_reports,
      can_export_data = excluded.can_export_data,
      can_send_notifications = excluded.can_send_notifications,
      can_set_debt_limit = excluded.can_set_debt_limit,
      can_set_due_date = excluded.can_set_due_date,
      can_import_data = excluded.can_import_data,
      can_refund_payments = excluded.can_refund_payments,
      can_restore_debts = excluded.can_restore_debts,
      can_manage_receipts = excluded.can_manage_receipts,
      can_manage_notifications = excluded.can_manage_notifications,
      can_approve_customers = excluded.can_approve_customers,
      can_manage_employees = excluded.can_manage_employees,
      can_view_audit_log = excluded.can_view_audit_log,
      can_manage_backup = excluded.can_manage_backup,
      can_manage_daftar_sync = excluded.can_manage_daftar_sync,
      can_manage_subscription = excluded.can_manage_subscription,
      can_view_dashboard = excluded.can_view_dashboard,
      can_view_recent_activity = excluded.can_view_recent_activity,
      can_view_transactions = excluded.can_view_transactions,
      can_edit_payments = excluded.can_edit_payments,
      can_delete_payments = excluded.can_delete_payments,
      can_create_statements = excluded.can_create_statements,
      can_manage_customer_links = excluded.can_manage_customer_links,
      can_pin_customers = excluded.can_pin_customers,
      can_manage_vip_customers = excluded.can_manage_vip_customers,
      can_merge_customer_identities = excluded.can_merge_customer_identities,
      can_view_market_rates = excluded.can_view_market_rates,
      can_view_intelligence = excluded.can_view_intelligence,
      can_manage_collections = excluded.can_manage_collections,
      can_view_expiry = excluded.can_view_expiry,
      can_manage_expiry = excluded.can_manage_expiry,
      can_manage_settings = excluded.can_manage_settings,
      updated_at = now(),
      updated_by = coalesce(auth.uid(), public.employee_permissions.updated_by);
  elsif tg_op = 'UPDATE' and old.role = 'employee' then
    delete from public.employee_permissions where employee_id = old.id;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_sync_employee_permissions on public.profiles;
create trigger profiles_sync_employee_permissions
after insert or update on public.profiles
for each row execute function private.sync_profile_permissions_to_employee_permissions();

create or replace function private.employee_has_permission(permission_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare allowed boolean := false;
begin
  if private.current_role() = 'admin' then return true; end if;
  if private.current_role() <> 'employee' then return false; end if;
  select case permission_name
    when 'view_customers' then ep.can_view_customers
    when 'add_customers' then ep.can_add_customers
    when 'edit_customers' then ep.can_edit_customers
    when 'delete_customers' then ep.can_delete_customers
    when 'view_debts' then ep.can_view_debts
    when 'add_debts' then ep.can_add_debts
    when 'edit_debts' then ep.can_edit_debts
    when 'delete_debts' then ep.can_delete_debts
    when 'record_payments' then ep.can_record_payments
    when 'view_financial_reports' then ep.can_view_financial_reports
    when 'export_data' then ep.can_export_data
    when 'send_notifications' then ep.can_send_notifications
    when 'set_debt_limit' then ep.can_set_debt_limit
    when 'set_due_date' then ep.can_set_due_date
    when 'import_data' then ep.can_import_data
    when 'refund_payments' then ep.can_refund_payments
    when 'restore_debts' then ep.can_restore_debts
    when 'manage_receipts' then ep.can_manage_receipts
    when 'manage_notifications' then ep.can_manage_notifications
    when 'approve_customers' then ep.can_approve_customers
    when 'manage_employees' then ep.can_manage_employees
    when 'view_audit_log' then ep.can_view_audit_log
    when 'manage_backup' then ep.can_manage_backup
    when 'manage_daftar_sync' then ep.can_manage_daftar_sync
    when 'manage_subscription' then ep.can_manage_subscription
    when 'view_dashboard' then ep.can_view_dashboard
    when 'view_recent_activity' then ep.can_view_recent_activity
    when 'view_transactions' then ep.can_view_transactions
    when 'edit_payments' then ep.can_edit_payments
    when 'delete_payments' then ep.can_delete_payments
    when 'create_statements' then ep.can_create_statements
    when 'manage_customer_links' then ep.can_manage_customer_links
    when 'pin_customers' then ep.can_pin_customers
    when 'manage_vip_customers' then ep.can_manage_vip_customers
    when 'merge_customer_identities' then ep.can_merge_customer_identities
    when 'view_market_rates' then ep.can_view_market_rates
    when 'view_intelligence' then ep.can_view_intelligence
    when 'manage_collections' then ep.can_manage_collections
    when 'view_expiry' then ep.can_view_expiry
    when 'manage_expiry' then ep.can_manage_expiry
    when 'manage_settings' then ep.can_manage_settings
    else false
  end into allowed
  from public.employee_permissions ep
  where ep.employee_id = auth.uid()
    and ep.admin_id = private.current_admin_id();
  return coalesce(allowed, false);
end;
$$;

insert into public.employee_permissions (
  employee_id, admin_id,
  can_view_customers, can_add_customers, can_edit_customers, can_delete_customers,
  can_view_debts, can_add_debts, can_edit_debts, can_delete_debts,
  can_record_payments, can_view_financial_reports, can_export_data,
  can_send_notifications, can_set_debt_limit, can_set_due_date, can_import_data,
  can_refund_payments, can_restore_debts, can_manage_receipts,
  can_manage_notifications, can_approve_customers, can_manage_employees,
  can_view_audit_log, can_manage_backup, can_manage_daftar_sync,
  can_manage_subscription, can_view_dashboard, can_view_recent_activity,
  can_view_transactions, can_edit_payments, can_delete_payments,
  can_create_statements, can_manage_customer_links, can_pin_customers,
  can_manage_vip_customers, can_merge_customer_identities,
  can_view_market_rates, can_view_intelligence, can_manage_collections,
  can_view_expiry, can_manage_expiry, can_manage_settings,
  updated_at, updated_by
)
select
  p.id, p.admin_id,
  p.can_view_customers, p.can_add_customers, p.can_edit_customers, p.can_delete_customers,
  p.can_view_debts, p.can_add_debts, p.can_edit_debts, p.can_delete_debts,
  p.can_record_payments, p.can_view_financial_reports, p.can_export_data,
  p.can_send_notifications, p.can_set_debt_limit, p.can_set_due_date, p.can_import_data,
  p.can_refund_payments, p.can_restore_debts, p.can_manage_receipts,
  p.can_manage_notifications, p.can_approve_customers, p.can_manage_employees,
  p.can_view_audit_log, p.can_manage_backup, p.can_manage_daftar_sync,
  p.can_manage_subscription, p.can_view_dashboard, p.can_view_recent_activity,
  p.can_view_transactions, p.can_edit_payments, p.can_delete_payments,
  p.can_create_statements, p.can_manage_customer_links, p.can_pin_customers,
  p.can_manage_vip_customers, p.can_merge_customer_identities,
  p.can_view_market_rates, p.can_view_intelligence, p.can_manage_collections,
  p.can_view_expiry, p.can_manage_expiry, p.can_manage_settings,
  now(), null
from public.profiles p
where p.role='employee' and p.admin_id is not null
on conflict (employee_id) do nothing;
