import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/legacy_import_service.dart';

void main() {
  test('parses Zhirox single CSV import package', () {
    const csv = '''record_type,source_id,customer_source_id,debt_source_id,allocation_part,name,phone,description,amount,currency,occurred_at,note,debt_limit,debt_duration,market_name,expected_balance_iqd
META,,,,,,,,,,,,,,سوپەرمارکێتی کانی چنار,900
CUSTOMER,1,,,,Ali,07500000000,,,,,0,30,,
DEBT,10,1,,,,,Debt,1000,IQD,2026-09-01T10:00:00Z,,,,,
PAYMENT,p20:1,,10,1,,,,100,,2026-09-02T10:00:00Z,paid,,,,
''';

    final bundle = LegacyImportService.parseCsvBundle(
      Uint8List.fromList(utf8.encode(csv)),
      'import.csv',
    );

    expect(bundle.marketName, 'سوپەرمارکێتی کانی چنار');
    expect(bundle.expectedBalanceIqd, 900);
    expect(bundle.customers, hasLength(1));
    expect(bundle.debts, hasLength(1));
    expect(bundle.payments, hasLength(1));
    expect(bundle.customers.single['source_id'], '1');
    expect(bundle.debts.single['customer_source_id'], '1');
    expect(bundle.payments.single['debt_source_id'], '10');
  });

  test('rejects CSV without record_type', () {
    final bytes = Uint8List.fromList(utf8.encode('name,amount\nA,10\n'));
    expect(
      () => LegacyImportService.parseCsvBundle(bytes, 'bad.csv'),
      throwsException,
    );
  });
}
