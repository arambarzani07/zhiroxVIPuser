update public.profiles
set
  can_view_customer_phone = can_view_customers,
  can_view_customer_notes = can_view_customers,
  can_edit_customer_notes = can_edit_customers,
  can_view_customer_balances = can_view_financial_reports,
  can_view_payment_history = can_view_transactions or can_record_payments,
  can_create_receipts = can_manage_receipts,
  can_edit_receipts = can_manage_receipts,
  can_delete_receipts = can_manage_receipts,
  can_export_receipts = can_manage_receipts or can_export_data,
  can_view_report_summary = can_view_financial_reports,
  can_export_reports = can_export_data,
  can_view_sync_logs = can_manage_daftar_sync,
  can_retry_failed_sync = can_manage_daftar_sync,
  can_run_manual_backup = can_manage_backup,
  can_restore_backup = can_manage_backup,
  can_manage_notification_templates = can_manage_notifications,
  can_send_bulk_notifications = can_manage_notifications or can_send_notifications,
  can_manage_market_rate_refresh = can_view_market_rates and can_manage_settings,
  can_manage_security_settings = can_manage_settings
where role = 'employee';

update public.employee_permissions ep
set
  can_view_customer_phone = p.can_view_customer_phone,
  can_view_customer_notes = p.can_view_customer_notes,
  can_edit_customer_notes = p.can_edit_customer_notes,
  can_view_customer_balances = p.can_view_customer_balances,
  can_view_payment_history = p.can_view_payment_history,
  can_create_receipts = p.can_create_receipts,
  can_edit_receipts = p.can_edit_receipts,
  can_delete_receipts = p.can_delete_receipts,
  can_export_receipts = p.can_export_receipts,
  can_view_report_summary = p.can_view_report_summary,
  can_export_reports = p.can_export_reports,
  can_view_sync_logs = p.can_view_sync_logs,
  can_retry_failed_sync = p.can_retry_failed_sync,
  can_run_manual_backup = p.can_run_manual_backup,
  can_restore_backup = p.can_restore_backup,
  can_manage_notification_templates = p.can_manage_notification_templates,
  can_send_bulk_notifications = p.can_send_bulk_notifications,
  can_manage_market_rate_refresh = p.can_manage_market_rate_refresh,
  can_manage_security_settings = p.can_manage_security_settings,
  updated_at = now()
from public.profiles p
where p.id = ep.employee_id
  and p.role = 'employee'
  and p.admin_id = ep.admin_id;
