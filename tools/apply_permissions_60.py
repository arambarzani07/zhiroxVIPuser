from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, value: str) -> None:
    Path(path).write_text(value, encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'marker not found: {label}')
    return text.replace(old, new, 1)


# 1) AuthProvider: expose all 19 new permissions to the Flutter UI.
path = 'lib/providers/auth_provider.dart'
text = read(path)
marker = "  bool get canManageSettings => _employeePermission('can_manage_settings');\n"
insert = marker + """
  bool get canViewCustomerPhone => _employeePermission('can_view_customer_phone');
  bool get canViewCustomerNotes => _employeePermission('can_view_customer_notes');
  bool get canEditCustomerNotes => _employeePermission('can_edit_customer_notes');
  bool get canViewCustomerBalances => _employeePermission('can_view_customer_balances');
  bool get canViewPaymentHistory => _employeePermission('can_view_payment_history');
  bool get canCreateReceipts => _employeePermission('can_create_receipts');
  bool get canEditReceipts => _employeePermission('can_edit_receipts');
  bool get canDeleteReceipts => _employeePermission('can_delete_receipts');
  bool get canExportReceipts => _employeePermission('can_export_receipts');
  bool get canViewReportSummary => _employeePermission('can_view_report_summary');
  bool get canExportReports => _employeePermission('can_export_reports');
  bool get canViewSyncLogs => _employeePermission('can_view_sync_logs');
  bool get canRetryFailedSync => _employeePermission('can_retry_failed_sync');
  bool get canRunManualBackup => _employeePermission('can_run_manual_backup');
  bool get canRestoreBackup => _employeePermission('can_restore_backup');
  bool get canManageNotificationTemplates =>
      _employeePermission('can_manage_notification_templates');
  bool get canSendBulkNotifications =>
      _employeePermission('can_send_bulk_notifications');
  bool get canManageMarketRateRefresh =>
      _employeePermission('can_manage_market_rate_refresh');
  bool get canManageSecuritySettings =>
      _employeePermission('can_manage_security_settings');
"""
text = replace_once(text, marker, insert, 'AuthProvider permission getters')
write(path, text)


# 2) PBService: accept all 60 permissions and atomically apply the full map
# through set_employee_permissions_v2 after account creation.
path = 'lib/services/pb_service.dart'
text = read(path)
start = text.index('  static Future<RecordModel> createUser({')
end = text.index('  static Future<void> updateUser', start)
chunk = text[start:end]
chunk = replace_once(
    chunk,
    "    bool canManageSettings = false,\n    double debtLimit = 0,\n  }) {\n",
    """    bool canManageSettings = false,
    bool canViewCustomerPhone = false,
    bool canViewCustomerNotes = false,
    bool canEditCustomerNotes = false,
    bool canViewCustomerBalances = false,
    bool canViewPaymentHistory = false,
    bool canCreateReceipts = false,
    bool canEditReceipts = false,
    bool canDeleteReceipts = false,
    bool canExportReceipts = false,
    bool canViewReportSummary = false,
    bool canExportReports = false,
    bool canViewSyncLogs = false,
    bool canRetryFailedSync = false,
    bool canRunManualBackup = false,
    bool canRestoreBackup = false,
    bool canManageNotificationTemplates = false,
    bool canSendBulkNotifications = false,
    bool canManageMarketRateRefresh = false,
    bool canManageSecuritySettings = false,
    bool assignEmployeePermissions = false,
    double debtLimit = 0,
  }) async {
""",
    'PBService createUser params',
)
chunk = replace_once(
    chunk,
    '    return _invokeCreateAccount({\n',
    '    final created = await _invokeCreateAccount({\n',
    'PBService createUser await',
)
old_tail = "      'debt_limit': debtLimit,\n    });\n  }\n\n"
new_tail = """      'debt_limit': debtLimit,
    });

    if (role == 'employee' && assignEmployeePermissions) {
      final permissions = <String, bool>{
        'can_view_customers': canViewCustomers,
        'can_add_customers': canAddCustomers,
        'can_edit_customers': canEditCustomers,
        'can_delete_customers': canDeleteCustomers,
        'can_view_debts': canViewDebts,
        'can_add_debts': canAddDebts,
        'can_edit_debts': canEditDebts,
        'can_delete_debts': canDeleteDebts,
        'can_record_payments': canRecordPayments,
        'can_view_financial_reports': canViewFinancialReports,
        'can_export_data': canExportData,
        'can_send_notifications': canSendNotifications,
        'can_set_debt_limit': canSetDebtLimit,
        'can_set_due_date': canSetDueDate,
        'can_import_data': canImportData,
        'can_refund_payments': canRefundPayments,
        'can_restore_debts': canRestoreDebts,
        'can_manage_receipts': canManageReceipts,
        'can_manage_notifications': canManageNotifications,
        'can_approve_customers': canApproveCustomers,
        'can_manage_employees': canManageEmployees,
        'can_view_audit_log': canViewAuditLog,
        'can_manage_backup': canManageBackup,
        'can_manage_daftar_sync': canManageDaftarSync,
        'can_manage_subscription': canManageSubscription,
        'can_view_dashboard': canViewDashboard,
        'can_view_recent_activity': canViewRecentActivity,
        'can_view_transactions': canViewTransactions,
        'can_edit_payments': canEditPayments,
        'can_delete_payments': canDeletePayments,
        'can_create_statements': canCreateStatements,
        'can_manage_customer_links': canManageCustomerLinks,
        'can_pin_customers': canPinCustomers,
        'can_manage_vip_customers': canManageVipCustomers,
        'can_merge_customer_identities': canMergeCustomerIdentities,
        'can_view_market_rates': canViewMarketRates,
        'can_view_intelligence': canViewIntelligence,
        'can_manage_collections': canManageCollections,
        'can_view_expiry': canViewExpiry,
        'can_manage_expiry': canManageExpiry,
        'can_manage_settings': canManageSettings,
        'can_view_customer_phone': canViewCustomerPhone,
        'can_view_customer_notes': canViewCustomerNotes,
        'can_edit_customer_notes': canEditCustomerNotes,
        'can_view_customer_balances': canViewCustomerBalances,
        'can_view_payment_history': canViewPaymentHistory,
        'can_create_receipts': canCreateReceipts,
        'can_edit_receipts': canEditReceipts,
        'can_delete_receipts': canDeleteReceipts,
        'can_export_receipts': canExportReceipts,
        'can_view_report_summary': canViewReportSummary,
        'can_export_reports': canExportReports,
        'can_view_sync_logs': canViewSyncLogs,
        'can_retry_failed_sync': canRetryFailedSync,
        'can_run_manual_backup': canRunManualBackup,
        'can_restore_backup': canRestoreBackup,
        'can_manage_notification_templates': canManageNotificationTemplates,
        'can_send_bulk_notifications': canSendBulkNotifications,
        'can_manage_market_rate_refresh': canManageMarketRateRefresh,
        'can_manage_security_settings': canManageSecuritySettings,
      };
      try {
        await setEmployeePermissions(
          employeeId: created.id,
          permissions: permissions,
        );
      } catch (_) {
        try {
          await deleteUser(created.id);
        } catch (_) {}
        rethrow;
      }
    }

    return created;
  }

  static Future<void> setEmployeePermissions({
    required String employeeId,
    required Map<String, bool> permissions,
  }) async {
    await ensureInitialized();
    await client.rpc(
      'set_employee_permissions_v2',
      params: {
        'p_employee_id': employeeId,
        'p_permissions': permissions,
      },
    );
  }

"""
chunk = replace_once(chunk, old_tail, new_tail, 'PBService permission assignment tail')
text = text[:start] + chunk + text[end:]
write(path, text)


# 3) AddUserDialog: surface every existing and new permission.
path = 'lib/screens/shared/add_user_screen.dart'
text = read(path)
marker = '  bool _canManageSubscription = false;\n'
insert = marker + """
  final Map<String, bool> _advancedPermissions = <String, bool>{
    'can_view_dashboard': true,
    'can_view_recent_activity': true,
    'can_view_transactions': false,
    'can_edit_payments': false,
    'can_delete_payments': false,
    'can_create_statements': false,
    'can_manage_customer_links': false,
    'can_pin_customers': false,
    'can_manage_vip_customers': false,
    'can_merge_customer_identities': false,
    'can_view_market_rates': true,
    'can_view_intelligence': false,
    'can_manage_collections': false,
    'can_view_expiry': false,
    'can_manage_expiry': false,
    'can_manage_settings': false,
    'can_view_customer_phone': false,
    'can_view_customer_notes': false,
    'can_edit_customer_notes': false,
    'can_view_customer_balances': false,
    'can_view_payment_history': false,
    'can_create_receipts': false,
    'can_edit_receipts': false,
    'can_delete_receipts': false,
    'can_export_receipts': false,
    'can_view_report_summary': false,
    'can_export_reports': false,
    'can_view_sync_logs': false,
    'can_retry_failed_sync': false,
    'can_run_manual_backup': false,
    'can_restore_backup': false,
    'can_manage_notification_templates': false,
    'can_send_bulk_notifications': false,
    'can_manage_market_rate_refresh': false,
    'can_manage_security_settings': false,
  };
"""
text = replace_once(text, marker, insert, 'AddUser advanced permission state')

save_marker = "        canManageSubscription: _canManageSubscription,\n        debtLimit: debtLimit,\n"
save_insert = """        canManageSubscription: _canManageSubscription,
        canViewDashboard: _advancedPermissions['can_view_dashboard'] ?? true,
        canViewRecentActivity:
            _advancedPermissions['can_view_recent_activity'] ?? true,
        canViewTransactions:
            _advancedPermissions['can_view_transactions'] ?? false,
        canEditPayments: _advancedPermissions['can_edit_payments'] ?? false,
        canDeletePayments: _advancedPermissions['can_delete_payments'] ?? false,
        canCreateStatements:
            _advancedPermissions['can_create_statements'] ?? false,
        canManageCustomerLinks:
            _advancedPermissions['can_manage_customer_links'] ?? false,
        canPinCustomers: _advancedPermissions['can_pin_customers'] ?? false,
        canManageVipCustomers:
            _advancedPermissions['can_manage_vip_customers'] ?? false,
        canMergeCustomerIdentities:
            _advancedPermissions['can_merge_customer_identities'] ?? false,
        canViewMarketRates:
            _advancedPermissions['can_view_market_rates'] ?? true,
        canViewIntelligence:
            _advancedPermissions['can_view_intelligence'] ?? false,
        canManageCollections:
            _advancedPermissions['can_manage_collections'] ?? false,
        canViewExpiry: _advancedPermissions['can_view_expiry'] ?? false,
        canManageExpiry: _advancedPermissions['can_manage_expiry'] ?? false,
        canManageSettings:
            _advancedPermissions['can_manage_settings'] ?? false,
        canViewCustomerPhone:
            _advancedPermissions['can_view_customer_phone'] ?? false,
        canViewCustomerNotes:
            _advancedPermissions['can_view_customer_notes'] ?? false,
        canEditCustomerNotes:
            _advancedPermissions['can_edit_customer_notes'] ?? false,
        canViewCustomerBalances:
            _advancedPermissions['can_view_customer_balances'] ?? false,
        canViewPaymentHistory:
            _advancedPermissions['can_view_payment_history'] ?? false,
        canCreateReceipts:
            _advancedPermissions['can_create_receipts'] ?? false,
        canEditReceipts: _advancedPermissions['can_edit_receipts'] ?? false,
        canDeleteReceipts:
            _advancedPermissions['can_delete_receipts'] ?? false,
        canExportReceipts:
            _advancedPermissions['can_export_receipts'] ?? false,
        canViewReportSummary:
            _advancedPermissions['can_view_report_summary'] ?? false,
        canExportReports: _advancedPermissions['can_export_reports'] ?? false,
        canViewSyncLogs: _advancedPermissions['can_view_sync_logs'] ?? false,
        canRetryFailedSync:
            _advancedPermissions['can_retry_failed_sync'] ?? false,
        canRunManualBackup:
            _advancedPermissions['can_run_manual_backup'] ?? false,
        canRestoreBackup:
            _advancedPermissions['can_restore_backup'] ?? false,
        canManageNotificationTemplates:
            _advancedPermissions['can_manage_notification_templates'] ?? false,
        canSendBulkNotifications:
            _advancedPermissions['can_send_bulk_notifications'] ?? false,
        canManageMarketRateRefresh:
            _advancedPermissions['can_manage_market_rate_refresh'] ?? false,
        canManageSecuritySettings:
            _advancedPermissions['can_manage_security_settings'] ?? false,
        assignEmployeePermissions:
            widget.role == 'employee' && auth.userRole == 'admin',
        debtLimit: debtLimit,
"""
text = replace_once(text, save_marker, save_insert, 'AddUser save permission args')

start = text.index('  Widget _buildPermissionSection(bool isDark) {')
end = text.index('  Widget _sectionLabel(', start)
chunk = text[start:end]
closing = "        ),\n      ],\n    );\n  }\n\n"
extra_groups = """        ),
        const SizedBox(height: 12),
        _buildAdvancedPermissionGroup(
          title: 'نمایش و زانیاری کڕیار',
          icon: Icons.visibility_outlined,
          isDark: isDark,
          permissions: const {
            'can_view_dashboard': 'بینینی داشبۆرد',
            'can_view_recent_activity': 'بینینی چالاکییە نوێکان',
            'can_view_transactions': 'بینینی هەموو مامەڵەکان',
            'can_view_market_rates': 'بینینی نرخی بازاڕ',
            'can_view_customer_phone': 'بینینی ژمارەی مۆبایلی کڕیار',
            'can_view_customer_notes': 'بینینی تێبینی کڕیار',
            'can_edit_customer_notes': 'دەستکاریکردنی تێبینی کڕیار',
            'can_view_customer_balances': 'بینینی باڵانسی کڕیار',
            'can_view_payment_history': 'بینینی مێژووی پارەدانەوە',
            'can_view_report_summary': 'بینینی پوختەی ڕاپۆرت',
            'can_view_sync_logs': 'بینینی لۆگی Sync',
          },
        ),
        const SizedBox(height: 12),
        _buildAdvancedPermissionGroup(
          title: 'کڕیار و ناسنامە',
          icon: Icons.people_alt_outlined,
          isDark: isDark,
          permissions: const {
            'can_manage_customer_links': 'بەڕێوەبردنی لینکی کڕیار',
            'can_pin_customers': 'Pin کردنی کڕیار',
            'can_manage_vip_customers': 'بەڕێوەبردنی کڕیاری VIP',
            'can_merge_customer_identities': 'یەکخستنی ناسنامەی کڕیار',
          },
        ),
        const SizedBox(height: 12),
        _buildAdvancedPermissionGroup(
          title: 'پارەدانەوە، پسووڵە و ڕاپۆرت',
          icon: Icons.receipt_long_outlined,
          isDark: isDark,
          permissions: const {
            'can_edit_payments': 'دەستکاریکردنی پارەدانەوە',
            'can_delete_payments': 'سڕینەوەی پارەدانەوە',
            'can_create_statements': 'دروستکردنی کەشفی حیساب',
            'can_create_receipts': 'دروستکردنی پسووڵە',
            'can_edit_receipts': 'دەستکاریکردنی پسووڵە',
            'can_delete_receipts': 'سڕینەوەی پسووڵە',
            'can_export_receipts': 'هەناردەکردنی پسووڵە',
            'can_export_reports': 'هەناردەکردنی ڕاپۆرت',
          },
        ),
        const SizedBox(height: 12),
        _buildAdvancedPermissionGroup(
          title: 'زیرەکی، Sync و Backup',
          icon: Icons.hub_outlined,
          isDark: isDark,
          permissions: const {
            'can_view_intelligence': 'بینینی ناوەندی زیرەکی',
            'can_manage_collections': 'بەڕێوەبردنی بەدواداچوونی قەرز',
            'can_view_expiry': 'بینینی کاڵای بەسەرچوو',
            'can_manage_expiry': 'بەڕێوەبردنی کاڵای بەسەرچوو',
            'can_retry_failed_sync': 'دووبارەکردنەوەی Sync ـی شکستخواردوو',
            'can_run_manual_backup': 'Backup ـی دەستی',
            'can_restore_backup': 'گەڕاندنەوە لە Backup',
            'can_manage_market_rate_refresh': 'نوێکردنەوەی نرخی بازاڕ',
          },
        ),
        const SizedBox(height: 12),
        _buildAdvancedPermissionGroup(
          title: 'ڕێکخستن و ئاگادارکردنەوە',
          icon: Icons.security_outlined,
          isDark: isDark,
          permissions: const {
            'can_manage_settings': 'بەڕێوەبردنی ڕێکخستنەکان',
            'can_manage_notification_templates': 'قالبی ئاگادارکردنەوەکان',
            'can_send_bulk_notifications': 'ناردنی ئاگادارکردنەوەی کۆمەڵەیی',
            'can_manage_security_settings': 'ڕێکخستنی پاراستن و ئاسایش',
          },
        ),
      ],
    );
  }

  Widget _buildAdvancedPermissionGroup({
    required String title,
    required IconData icon,
    required bool isDark,
    required Map<String, String> permissions,
  }) {
    final entries = permissions.entries.toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.surface : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: AppColors.primary),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : const Color(0xFF344054),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC),
          ),
          for (var index = 0; index < entries.length; index++)
            _buildSwitch(
              entries[index].value,
              _advancedPermissions[entries[index].key] ?? false,
              (value) => setState(
                () => _advancedPermissions[entries[index].key] = value,
              ),
              isLast: index == entries.length - 1,
            ),
        ],
      ),
    );
  }

"""
if not chunk.endswith(closing):
    raise RuntimeError('AddUser permission section closing marker not found')
chunk = chunk[:-len(closing)] + extra_groups
text = text[:start] + chunk + text[end:]
write(path, text)

print('Applied 60-permission app wiring successfully.')
