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
      can_view_customer_phone = new.can_view_customer_phone,
      can_view_customer_notes = new.can_view_customer_notes,
      can_edit_customer_notes = new.can_edit_customer_notes,
      can_view_customer_balances = new.can_view_customer_balances,
      can_view_payment_history = new.can_view_payment_history,
      can_create_receipts = new.can_create_receipts,
      can_edit_receipts = new.can_edit_receipts,
      can_delete_receipts = new.can_delete_receipts,
      can_export_receipts = new.can_export_receipts,
      can_view_report_summary = new.can_view_report_summary,
      can_export_reports = new.can_export_reports,
      can_view_sync_logs = new.can_view_sync_logs,
      can_retry_failed_sync = new.can_retry_failed_sync,
      can_run_manual_backup = new.can_run_manual_backup,
      can_restore_backup = new.can_restore_backup,
      can_manage_notification_templates = new.can_manage_notification_templates,
      can_send_bulk_notifications = new.can_send_bulk_notifications,
      can_manage_market_rate_refresh = new.can_manage_market_rate_refresh,
      can_manage_security_settings = new.can_manage_security_settings,
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
      can_record_payments, can_view_financial_reports, can_export_data, can_send_notifications,
      can_set_debt_limit, can_set_due_date, can_import_data, can_refund_payments,
      can_restore_debts, can_manage_receipts, can_manage_notifications, can_approve_customers,
      can_manage_employees, can_view_audit_log, can_manage_backup, can_manage_daftar_sync,
      can_manage_subscription, can_view_dashboard, can_view_recent_activity, can_view_transactions,
      can_edit_payments, can_delete_payments, can_create_statements, can_manage_customer_links,
      can_pin_customers, can_manage_vip_customers, can_merge_customer_identities,
      can_view_market_rates, can_view_intelligence, can_manage_collections, can_view_expiry,
      can_manage_expiry, can_manage_settings, can_view_customer_phone, can_view_customer_notes,
      can_edit_customer_notes, can_view_customer_balances, can_view_payment_history,
      can_create_receipts, can_edit_receipts, can_delete_receipts, can_export_receipts,
      can_view_report_summary, can_export_reports, can_view_sync_logs, can_retry_failed_sync,
      can_run_manual_backup, can_restore_backup, can_manage_notification_templates,
      can_send_bulk_notifications, can_manage_market_rate_refresh, can_manage_security_settings,
      updated_at, updated_by
    ) values (
      new.id, new.admin_id,
      new.can_view_customers, new.can_add_customers, new.can_edit_customers, new.can_delete_customers,
      new.can_view_debts, new.can_add_debts, new.can_edit_debts, new.can_delete_debts,
      new.can_record_payments, new.can_view_financial_reports, new.can_export_data, new.can_send_notifications,
      new.can_set_debt_limit, new.can_set_due_date, new.can_import_data, new.can_refund_payments,
      new.can_restore_debts, new.can_manage_receipts, new.can_manage_notifications, new.can_approve_customers,
      new.can_manage_employees, new.can_view_audit_log, new.can_manage_backup, new.can_manage_daftar_sync,
      new.can_manage_subscription, new.can_view_dashboard, new.can_view_recent_activity, new.can_view_transactions,
      new.can_edit_payments, new.can_delete_payments, new.can_create_statements, new.can_manage_customer_links,
      new.can_pin_customers, new.can_manage_vip_customers, new.can_merge_customer_identities,
      new.can_view_market_rates, new.can_view_intelligence, new.can_manage_collections, new.can_view_expiry,
      new.can_manage_expiry, new.can_manage_settings, new.can_view_customer_phone, new.can_view_customer_notes,
      new.can_edit_customer_notes, new.can_view_customer_balances, new.can_view_payment_history,
      new.can_create_receipts, new.can_edit_receipts, new.can_delete_receipts, new.can_export_receipts,
      new.can_view_report_summary, new.can_export_reports, new.can_view_sync_logs, new.can_retry_failed_sync,
      new.can_run_manual_backup, new.can_restore_backup, new.can_manage_notification_templates,
      new.can_send_bulk_notifications, new.can_manage_market_rate_refresh, new.can_manage_security_settings,
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
      can_view_customer_phone = excluded.can_view_customer_phone,
      can_view_customer_notes = excluded.can_view_customer_notes,
      can_edit_customer_notes = excluded.can_edit_customer_notes,
      can_view_customer_balances = excluded.can_view_customer_balances,
      can_view_payment_history = excluded.can_view_payment_history,
      can_create_receipts = excluded.can_create_receipts,
      can_edit_receipts = excluded.can_edit_receipts,
      can_delete_receipts = excluded.can_delete_receipts,
      can_export_receipts = excluded.can_export_receipts,
      can_view_report_summary = excluded.can_view_report_summary,
      can_export_reports = excluded.can_export_reports,
      can_view_sync_logs = excluded.can_view_sync_logs,
      can_retry_failed_sync = excluded.can_retry_failed_sync,
      can_run_manual_backup = excluded.can_run_manual_backup,
      can_restore_backup = excluded.can_restore_backup,
      can_manage_notification_templates = excluded.can_manage_notification_templates,
      can_send_bulk_notifications = excluded.can_send_bulk_notifications,
      can_manage_market_rate_refresh = excluded.can_manage_market_rate_refresh,
      can_manage_security_settings = excluded.can_manage_security_settings,
      updated_at = now(),
      updated_by = coalesce(auth.uid(), public.employee_permissions.updated_by);
  elsif tg_op = 'UPDATE' and old.role = 'employee' then
    delete from public.employee_permissions where employee_id = old.id;
  end if;

  return new;
end;
$$;
