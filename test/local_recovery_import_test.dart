import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/legacy_import_service.dart';

Uint8List _bytes(Map<String, dynamic> value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

Map<String, dynamic> _recovery({
  required List<Map<String, dynamic>> debts,
  required List<Map<String, dynamic>> payments,
}) =>
    {
      'format': 'zhirox_local_recovery_v1',
      'identity': {
        'user_data': {
          'id': 'admin-old',
          'role': 'admin',
          'market_name': 'Kani Chnar',
        },
      },
      'cache': {
        'cached_users_customer_admin-old': [
          {
            'id': 'c1',
            'role': 'customer',
            'name': 'Ali',
            'phone': '07500000000',
            'debt_limit': 2000,
            'debt_duration': 30,
          },
        ],
        'cached_profile_debts_c1': debts,
        'cached_profile_payments_c1': payments,
      },
    };

void main() {
  test('recovery JSON keeps debt and general payments separate', () {
    final data = _recovery(
      debts: [
        {
          'id': 'd1',
          'customer': 'c1',
          'amount': 1000,
          'remaining': 700,
          'currency': 'IQD',
          'description': 'first debt',
          'created': '2026-09-01T10:00:00Z',
        },
        {
          'id': 'd2',
          'customer': 'c1',
          'amount': 500,
          'remaining': 500,
          'currency': 'IQD',
          'description': 'second debt',
          'created': '2026-09-02T10:00:00Z',
        },
      ],
      payments: [
        {
          'id': 'p1',
          'debt': 'd1',
          'payment_scope': 'debt',
          'amount': 300,
          'note': 'specific repayment',
          'created': '2026-09-03T10:00:00Z',
        },
        {
          'id': 'g1',
          'payment_scope': 'general',
          'amount': 100,
          'note': 'overall repayment',
          'created': '2026-09-04T10:00:00Z',
        },
      ],
    );

    final bundle = LegacyImportService.parseLocalRecoveryJsonBundle(
      _bytes(data),
      'recovery.json',
    );

    expect(bundle.marketName, 'Kani Chnar');
    expect(bundle.customers, hasLength(1));
    expect(bundle.debts, hasLength(2));
    expect(bundle.payments, hasLength(2));
    expect(bundle.expectedBalanceIqd, 1100);

    final debtPayment = bundle.payments.singleWhere(
      (row) => row['source_id'] == 'p1',
    );
    expect(debtPayment['payment_scope'], 'debt');
    expect(debtPayment['debt_source_id'], 'd1');

    final generalPayment = bundle.payments.singleWhere(
      (row) => row['source_id'] == 'g1',
    );
    expect(generalPayment['payment_scope'], 'general');
    expect(generalPayment['customer_source_id'], 'c1');
    expect(generalPayment.containsKey('debt_source_id'), isFalse);
  });

  test('recovery JSON rejects incomplete debt payment history', () {
    final data = _recovery(
      debts: [
        {
          'id': 'd1',
          'customer': 'c1',
          'amount': 1000,
          'remaining': 700,
          'currency': 'IQD',
          'created': '2026-09-01T10:00:00Z',
        },
      ],
      payments: [
        {
          'id': 'p1',
          'debt': 'd1',
          'payment_scope': 'debt',
          'amount': 200,
          'created': '2026-09-03T10:00:00Z',
        },
      ],
    );

    expect(
      () => LegacyImportService.parseLocalRecoveryJsonBundle(
        _bytes(data),
        'incomplete-recovery.json',
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            'recovery_payment_history_incomplete:d1',
          ),
        ),
      ),
    );
  });

  test('recovery JSON rejects the old 100-row admin debt cache ceiling', () {
    final debts = List<Map<String, dynamic>>.generate(
      100,
      (index) => {
        'id': 'd$index',
        'customer': 'c1',
        'amount': 100,
        'remaining': 100,
        'currency': 'IQD',
        'created': '2026-09-01T10:00:00Z',
      },
    );
    final data = {
      'format': 'zhirox_local_recovery_v1',
      'cache': {
        'cached_users_customer_admin-old': [
          {'id': 'c1', 'role': 'customer', 'name': 'Ali'},
        ],
        'cached_debts_admin_admin-old': debts,
      },
    };

    expect(
      () => LegacyImportService.parseLocalRecoveryJsonBundle(
        _bytes(data),
        'truncated-recovery.json',
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            'recovery_debt_cache_may_be_truncated',
          ),
        ),
      ),
    );
  });
}
