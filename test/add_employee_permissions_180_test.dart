import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new employee dialog exposes and submits all 180 permissions atomically', () {
    final source =
        File('lib/screens/shared/add_user_screen.dart').readAsStringSync();
    final additionalRegistry = File(
      'lib/permissions/additional_employee_permissions.dart',
    ).readAsStringSync();

    const legacyPermissionFields = <String, String>{
      'canViewCustomers': '_canViewCustomers',
      'canAddCustomers': '_canAddCustomers',
      'canEditCustomers': '_canEditCustomers',
      'canDeleteCustomers': '_canDeleteCustomers',
      'canViewDebts': '_canViewDebts',
      'canAddDebts': '_canAddDebts',
      'canEditDebts': '_canEditDebts',
      'canDeleteDebts': '_canDeleteDebts',
      'canRecordPayments': '_canRecordPayments',
      'canViewFinancialReports': '_canViewFinancialReports',
      'canExportData': '_canExportData',
      'canSendNotifications': '_canSendNotifications',
      'canSetDebtLimit': '_canSetDebtLimit',
      'canSetDueDate': '_canSetDueDate',
      'canImportData': '_canImportData',
      'canRefundPayments': '_canRefundPayments',
      'canRestoreDebts': '_canRestoreDebts',
      'canManageReceipts': '_canManageReceipts',
      'canManageNotifications': '_canManageNotifications',
      'canApproveCustomers': '_canApproveCustomers',
      'canManageEmployees': '_canManageEmployees',
      'canViewAuditLog': '_canViewAuditLog',
      'canManageBackup': '_canManageBackup',
      'canManageDaftarSync': '_canManageDaftarSync',
      'canManageSubscription': '_canManageSubscription',
      'canViewDashboard': '_canViewDashboard',
      'canViewRecentActivity': '_canViewRecentActivity',
      'canViewTransactions': '_canViewTransactions',
      'canEditPayments': '_canEditPayments',
      'canDeletePayments': '_canDeletePayments',
      'canCreateStatements': '_canCreateStatements',
      'canManageCustomerLinks': '_canManageCustomerLinks',
      'canPinCustomers': '_canPinCustomers',
      'canManageVipCustomers': '_canManageVipCustomers',
      'canMergeCustomerIdentities': '_canMergeCustomerIdentities',
      'canViewMarketRates': '_canViewMarketRates',
      'canViewIntelligence': '_canViewIntelligence',
      'canManageCollections': '_canManageCollections',
      'canViewExpiry': '_canViewExpiry',
      'canManageExpiry': '_canManageExpiry',
      'canManageSettings': '_canManageSettings',
      'canViewCustomerPhone': '_canViewCustomerPhone',
      'canViewCustomerNotes': '_canViewCustomerNotes',
      'canEditCustomerNotes': '_canEditCustomerNotes',
      'canViewCustomerBalances': '_canViewCustomerBalances',
      'canViewPaymentHistory': '_canViewPaymentHistory',
      'canCreateReceipts': '_canCreateReceipts',
      'canEditReceipts': '_canEditReceipts',
      'canDeleteReceipts': '_canDeleteReceipts',
      'canExportReceipts': '_canExportReceipts',
      'canViewReportSummary': '_canViewReportSummary',
      'canExportReports': '_canExportReports',
      'canViewSyncLogs': '_canViewSyncLogs',
      'canRetryFailedSync': '_canRetryFailedSync',
      'canRunManualBackup': '_canRunManualBackup',
      'canRestoreBackup': '_canRestoreBackup',
      'canManageNotificationTemplates': '_canManageNotificationTemplates',
      'canSendBulkNotifications': '_canSendBulkNotifications',
      'canManageMarketRateRefresh': '_canManageMarketRateRefresh',
      'canManageSecuritySettings': '_canManageSecuritySettings',
    };

    expect(legacyPermissionFields.length, 60);
    expect(legacyPermissionFields.values.toSet().length, 60);

    for (final entry in legacyPermissionFields.entries) {
      expect(
        source,
        contains('${entry.key}: ${entry.value}'),
        reason: 'createUser is missing legacy ${entry.key}',
      );
      expect(
        source,
        contains('(v) => setState(() => ${entry.value} = v)'),
        reason: 'dialog switch is missing legacy ${entry.value}',
      );
    }

    final additionalKeys = RegExp(
      r"AdditionalEmployeePermissionSpec\(key: '([^']+)'",
    ).allMatches(additionalRegistry).map((match) => match.group(1)!).toList();
    expect(additionalKeys.length, 120);
    expect(additionalKeys.toSet().length, 120);
    expect(additionalRegistry, contains('newAdditionalEmployeePermissionState()'));

    expect(source, contains('180 دەسەڵات بەردەستن'));
    expect(source, contains('_additionalPermissions'));
    expect(source, contains('additionalEmployeePermissionSpecs'));
    expect(source, contains('extraPermissions: widget.role == \'employee\''));
    expect(source, contains('await PBService.createUser('));
    expect(
      source,
      isNot(contains('final createdUser = await PBService.createUser(')),
    );
    expect(
      source,
      isNot(contains('PBService.updateUser(\n            createdUser.id')),
    );
  });
}
