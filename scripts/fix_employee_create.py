from pathlib import Path

extra = [
    ('canViewCustomerPhone','can_view_customer_phone'),
    ('canViewCustomerNotes','can_view_customer_notes'),
    ('canEditCustomerNotes','can_edit_customer_notes'),
    ('canViewCustomerBalances','can_view_customer_balances'),
    ('canViewPaymentHistory','can_view_payment_history'),
    ('canCreateReceipts','can_create_receipts'),
    ('canEditReceipts','can_edit_receipts'),
    ('canDeleteReceipts','can_delete_receipts'),
    ('canExportReceipts','can_export_receipts'),
    ('canViewReportSummary','can_view_report_summary'),
    ('canExportReports','can_export_reports'),
    ('canViewSyncLogs','can_view_sync_logs'),
    ('canRetryFailedSync','can_retry_failed_sync'),
    ('canRunManualBackup','can_run_manual_backup'),
    ('canRestoreBackup','can_restore_backup'),
    ('canManageNotificationTemplates','can_manage_notification_templates'),
    ('canSendBulkNotifications','can_send_bulk_notifications'),
    ('canManageMarketRateRefresh','can_manage_market_rate_refresh'),
    ('canManageSecuritySettings','can_manage_security_settings'),
]

p = Path('lib/screens/shared/add_user_screen.dart')
s = p.read_text()
if 'String? _employeePasswordError' not in s:
    marker = "  @override\n  void dispose() {\n"
    helper = r'''  String? _employeePasswordError(String value) {
    if (value.isEmpty) return 'تکایە وشەی نهێنی بنووسە';
    if (value.length < 12) return 'وشەی نهێنی دەبێت لانیکەم ١٢ پیت بێت';
    if (!RegExp(r'[a-z]').hasMatch(value) ||
        !RegExp(r'[A-Z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(value)) {
      return 'وشەی نهێنی دەبێت پیتی گەورە و بچووک، ژمارە و هێمای تایبەت تێدابێت';
    }
    return null;
  }

'''
    assert marker in s
    s = s.replace(marker, helper + marker, 1)

old = """    final password = _passwordController.text;
    if (name.isEmpty || phone.isEmpty || password.length < 8) {
      if (widget.role == 'employee' && _employeeSection != 0 && mounted) {
        setState(() => _employeeSection = 0);
      }
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          password.isNotEmpty && password.length < 8
              ? 'وشەی نهێنی نابێت لە ٨ پیت کەمتر بێت'
              : 'تکایە زانیاری بنەڕەتی تەواو بکە',
          isError: true,
        );
      }
      return;
    }
"""
new = """    final password = _passwordController.text;
    final passwordError = _employeePasswordError(password);
    if (name.isEmpty || phone.isEmpty || passwordError != null) {
      if (widget.role == 'employee' && _employeeSection != 0 && mounted) {
        setState(() => _employeeSection = 0);
      }
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          passwordError ?? 'تکایە زانیاری بنەڕەتی تەواو بکە',
          isError: true,
        );
      }
      return;
    }
"""
if old in s:
    s = s.replace(old, new, 1)
s = s.replace("hint: 'لانیکەم ٨ پیت',", "hint: 'لانیکەم ١٢ پیت + Aa1!',", 1)
old_validator = """          validator: (v) {
            if (v == null || v.isEmpty) {
              return 'تکایە وشەی نهێنی بنووسە';
            }
            if (v.length < 8) return 'نابێت لە ٨ پیت کەمتر بێت';
            return null;
          },
"""
if old_validator in s:
    s = s.replace(old_validator, "          validator: (v) => _employeePasswordError(v ?? ''),\n", 1)
call_marker = "        canManageSubscription: _canManageSubscription,\n        debtLimit: debtLimit,\n"
if "canViewCustomerPhone: _canViewCustomerPhone" not in s:
    named = ''.join(f"        {camel}: _{camel[0].lower() + camel[1:]},\n" for camel, _ in extra)
    assert call_marker in s
    s = s.replace(call_marker, "        canManageSubscription: _canManageSubscription,\n" + named + "        debtLimit: debtLimit,\n", 1)
start = "      if (widget.role == 'employee') {\n        try {\n          await PBService.updateUser(\n"
if start in s:
    a = s.index(start)
    b = s.index("      if (mounted) {", a)
    s = s[:a] + s[b:]
p.write_text(s)

p = Path('lib/services/pb_service.dart')
s = p.read_text()
sig_marker = "    bool canManageSettings = false,\n    double debtLimit = 0,\n"
if "bool canViewCustomerPhone = false" not in s:
    sig = ''.join(f"    bool {camel} = false,\n" for camel, _ in extra)
    assert sig_marker in s
    s = s.replace(sig_marker, "    bool canManageSettings = false,\n" + sig + "    double debtLimit = 0,\n", 1)
body_marker = "      'can_manage_settings': canManageSettings,\n      'debt_limit': debtLimit,\n"
if "'can_view_customer_phone': canViewCustomerPhone" not in s:
    body = ''.join(f"      '{snake}': {camel},\n" for camel, snake in extra)
    assert body_marker in s
    s = s.replace(body_marker, "      'can_manage_settings': canManageSettings,\n" + body + "      'debt_limit': debtLimit,\n", 1)
p.write_text(s)

p = Path('supabase/functions/account-admin/index.ts')
s = p.read_text()
decl_marker = "      let canManageSettings = false;\n"
if "let canViewCustomerPhone = false;" not in s:
    s = s.replace(decl_marker, decl_marker + ''.join(f"      let {camel} = false;\n" for camel, _ in extra), 1)
assign_marker = "          canManageSettings = Boolean(body.can_manage_settings ?? false);\n"
if "canViewCustomerPhone = Boolean(body.can_view_customer_phone" not in s:
    s = s.replace(assign_marker, assign_marker + ''.join(f"          {camel} = Boolean(body.{snake} ?? false);\n" for camel, snake in extra), 1)
profile_marker = "        can_manage_settings: canManageSettings,\n"
if "can_view_customer_phone: canViewCustomerPhone" not in s:
    s = s.replace(profile_marker, profile_marker + ''.join(f"        {snake}: {camel},\n" for camel, snake in extra), 1)
p.write_text(s)

p = Path('lib/utils/helpers.dart')
s = p.read_text()
marker = "    final text = error.toString().toLowerCase();\n\n"
if "text.contains('weak_password')" not in s:
    extra_errors = """    if (text.contains('weak_password') || text.contains('وشەی نهێنی لانیکەم ١٢')) {
      return 'وشەی نهێنی دەبێت لانیکەم ١٢ پیت بێت و پیتی گەورە/بچووک، ژمارە و هێمای تایبەت تێدابێت.';
    }
    if (text.contains('phone_exists') || text.contains('ژمارەیە پێشتر تۆمارکراوە')) {
      return 'ئەم ژمارەی مۆبایلە پێشتر تۆمارکراوە.';
    }
    if (text.contains('employee_creation_requires_admin') || text.contains('تەنها بەڕێوەبەر دەتوانێت کارمەند')) {
      return 'تەنها بەڕێوەبەر دەتوانێت کارمەند دروست بکات.';
    }

"""
    s = s.replace(marker, marker + extra_errors, 1)
p.write_text(s)

keys = [
    'can_view_customers','can_add_customers','can_edit_customers','can_delete_customers','can_view_debts','can_add_debts','can_edit_debts','can_delete_debts','can_record_payments','can_view_financial_reports','can_export_data','can_send_notifications','can_set_debt_limit','can_set_due_date','can_import_data','can_refund_payments','can_restore_debts','can_manage_receipts','can_manage_notifications','can_approve_customers','can_manage_employees','can_view_audit_log','can_manage_backup','can_manage_daftar_sync','can_manage_subscription','can_view_dashboard','can_view_recent_activity','can_view_transactions','can_edit_payments','can_delete_payments','can_create_statements','can_manage_customer_links','can_pin_customers','can_manage_vip_customers','can_merge_customer_identities','can_view_market_rates','can_view_intelligence','can_manage_collections','can_view_expiry','can_manage_expiry','can_manage_settings','can_view_customer_phone','can_view_customer_notes','can_edit_customer_notes','can_view_customer_balances','can_view_payment_history','can_create_receipts','can_edit_receipts','can_delete_receipts','can_export_receipts','can_view_report_summary','can_export_reports','can_view_sync_logs','can_retry_failed_sync','can_run_manual_backup','can_restore_backup','can_manage_notification_templates','can_send_bulk_notifications','can_manage_market_rate_refresh','can_manage_security_settings',
]
assert len(keys) == 60 and len(set(keys)) == 60
Path('test/add_employee_creation_contract_test.dart').write_text("""import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee creation is strong-password and 60-permission complete', () {
    final ui = File('lib/screens/shared/add_user_screen.dart').readAsStringSync();
    final service = File('lib/services/pb_service.dart').readAsStringSync();
    final edge = File('supabase/functions/account-admin/index.ts').readAsStringSync();
    const keys = <String>[
""" + ''.join(f"      '{k}',\n" for k in keys) + """    ];
    expect(keys.toSet().length, 60);
    for (final key in keys) {
      expect(service, contains("'$key'"), reason: 'service missing $key');
      expect(edge, contains(key), reason: 'edge function missing $key');
    }
    expect(ui, contains('لانیکەم ١٢ پیت + Aa1!'));
    expect(ui, contains("RegExp(r'[A-Z]')"));
    expect(ui, isNot(contains("PBService.updateUser(\\n            createdUser.id")));
  });
}
""")
