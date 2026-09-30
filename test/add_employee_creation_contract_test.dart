import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee creation is strong-password and 180-permission complete', () {
    final ui = File('lib/screens/shared/add_user_screen.dart').readAsStringSync();
    final service = File('lib/services/pb_service.dart').readAsStringSync();
    final registry = File(
      'lib/permissions/additional_employee_permissions.dart',
    ).readAsStringSync();
    final edge =
        File('supabase/functions/employee-create/index.ts').readAsStringSync();

    const legacyKeys = <String>[
      'can_view_customers',
      'can_add_customers',
      'can_edit_customers',
      'can_delete_customers',
      'can_view_debts',
      'can_add_debts',
      'can_edit_debts',
      'can_delete_debts',
      'can_record_payments',
      'can_view_financial_reports',
      'can_export_data',
      'can_send_notifications',
      'can_set_debt_limit',
      'can_set_due_date',
      'can_import_data',
      'can_refund_payments',
      'can_restore_debts',
      'can_manage_receipts',
      'can_manage_notifications',
      'can_approve_customers',
      'can_manage_employees',
      'can_view_audit_log',
      'can_manage_backup',
      'can_manage_daftar_sync',
      'can_manage_subscription',
      'can_view_dashboard',
      'can_view_recent_activity',
      'can_view_transactions',
      'can_edit_payments',
      'can_delete_payments',
      'can_create_statements',
      'can_manage_customer_links',
      'can_pin_customers',
      'can_manage_vip_customers',
      'can_merge_customer_identities',
      'can_view_market_rates',
      'can_view_intelligence',
      'can_manage_collections',
      'can_view_expiry',
      'can_manage_expiry',
      'can_manage_settings',
      'can_view_customer_phone',
      'can_view_customer_notes',
      'can_edit_customer_notes',
      'can_view_customer_balances',
      'can_view_payment_history',
      'can_create_receipts',
      'can_edit_receipts',
      'can_delete_receipts',
      'can_export_receipts',
      'can_view_report_summary',
      'can_export_reports',
      'can_view_sync_logs',
      'can_retry_failed_sync',
      'can_run_manual_backup',
      'can_restore_backup',
      'can_manage_notification_templates',
      'can_send_bulk_notifications',
      'can_manage_market_rate_refresh',
      'can_manage_security_settings',
    ];

    final additionalKeys = RegExp(
      r"AdditionalEmployeePermissionSpec\(key: '([^']+)'",
    ).allMatches(registry).map((match) => match.group(1)!).toSet();

    expect(legacyKeys.toSet().length, 60);
    expect(additionalKeys.length, 120);
    expect(legacyKeys.toSet().intersection(additionalKeys), isEmpty);
    expect({...legacyKeys, ...additionalKeys}.length, 180);

    for (final key in legacyKeys) {
      expect(service, contains("'$key'"), reason: 'service missing legacy $key');
      expect(edge, contains(key), reason: 'employee-create missing legacy $key');
    }
    for (final key in additionalKeys) {
      expect(edge, contains(key), reason: 'employee-create missing additional $key');
    }

    expect(ui, contains('لانیکەم ١٢ پیت + Aa1!'));
    expect(ui, contains("RegExp(r'[A-Z]')"));
    expect(ui, contains('180 دەسەڵات بەردەستن'));
    expect(ui, contains('extraPermissions: widget.role == \'employee\''));
    expect(service, contains('Map<String, bool> extraPermissions'));
    expect(service, contains('...extraPermissions,'));
    expect(
      ui,
      isNot(contains('PBService.updateUser(\n            createdUser.id')),
    );
  });
}
