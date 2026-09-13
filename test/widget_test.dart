import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/legacy_import_service.dart';

const _targetAdminId = 'd3cc5c6e-1f9e-4552-ad22-b63b6fadf090';

Uint8List _buildPackage({
  String market = LegacyImportService.supportedMarket,
  String projectRef = LegacyImportService.supportedProjectRef,
}) {
  final summary =
      'target_project_ref,target_market,target_admin_id,customers,source_loans,'
      'zhirox_payment_rows_after_allocation,expected_final_balance_iqd\n'
      '$projectRef,$market,$_targetAdminId,1,1,1,600.00\n';

  const customers =
      'legacy_customer_id,name,zhirox_phone,auth_email\n'
      '1,Test Customer,legacy_kani_1,legacy_kani_1@zhirox.local\n';

  const debts =
      'debt_id,legacy_customer_id,customer_lookup_phone,amount,currency,'
      'custom_date,created_at\n'
      '11111111-1111-5111-8111-111111111111,1,legacy_kani_1,1000.00,IQD,'
      '2024-01-01T00:00:00.000Z,2024-01-01T00:00:00.000Z\n';

  const payments =
      'payment_id,debt_id,amount,created_at\n'
      '22222222-2222-5222-8222-222222222222,'
      '11111111-1111-5111-8111-111111111111,400.00,'
      '2024-01-02T00:00:00.000Z\n';

  final archive = Archive()
    ..addFile(ArchiveFile.string(
      'Kanichnar_ZhiroxVIPuser_Import_Ready/meta/migration_summary.csv',
      summary,
    ))
    ..addFile(ArchiveFile.string(
      'Kanichnar_ZhiroxVIPuser_Import_Ready/data/01_customers_zhirox.csv',
      customers,
    ))
    ..addFile(ArchiveFile.string(
      'Kanichnar_ZhiroxVIPuser_Import_Ready/data/02_debts_zhirox.csv',
      debts,
    ))
    ..addFile(ArchiveFile.string(
      'Kanichnar_ZhiroxVIPuser_Import_Ready/data/03_payments_zhirox.csv',
      payments,
    ));

  return ZipEncoder().encodeBytes(archive);
}

void main() {
  group('LegacyImportService.parseZip', () {
    test('accepts a valid Kanichnar Zhirox package', () {
      final package = LegacyImportService.parseZip(
        fileName: 'kanichnar.zip',
        bytes: _buildPackage(),
      );

      expect(package.targetProjectRef, LegacyImportService.supportedProjectRef);
      expect(package.targetMarket, LegacyImportService.supportedMarket);
      expect(package.targetAdminId, _targetAdminId);
      expect(package.customerCount, 1);
      expect(package.debtCount, 1);
      expect(package.paymentCount, 1);
      expect(package.expectedBalanceIqd, 600.0);
      expect(package.expectedBalanceUsd, 0.0);
    });

    test('rejects a package for another market', () {
      expect(
        () => LegacyImportService.parseZip(
          fileName: 'wrong-market.zip',
          bytes: _buildPackage(market: 'مارکێتی تر'),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a package for another Supabase project', () {
      expect(
        () => LegacyImportService.parseZip(
          fileName: 'wrong-project.zip',
          bytes: _buildPackage(projectRef: 'other-project-ref'),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
