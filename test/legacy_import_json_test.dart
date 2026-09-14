import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/legacy_import_service.dart';

Uint8List _bytes(Map<String, dynamic> value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

Map<String, dynamic> _export({
  required List<Map<String, dynamic>> contacts,
  required List<Map<String, dynamic>> transactions,
  bool contactsIncomplete = false,
  bool transactionsIncomplete = false,
}) =>
    {
      'format': 'daftar-qarz-authorized-api-export-v1',
      'account_user_id': '28',
      'contacts': {
        'page_count': 1,
        'pagination_incomplete_or_unknown': contactsIncomplete,
        'pages': [
          {'success': true, 'data': contacts},
        ],
      },
      'transactions': {
        'page_count': 1,
        'pagination_incomplete_or_unknown': transactionsIncomplete,
        'pages': [
          {'success': true, 'data': transactions},
        ],
      },
    };

void main() {
  test('parses authorized JSON and deterministically splits a payment', () {
    final bundle = LegacyImportService.parseAuthorizedApiJsonBundle(
      _bytes(
        _export(
          contacts: [
            {
              'id': 1,
              'user_id': 28,
              'name': 'Ali',
              'phone': '07500000000',
            },
          ],
          transactions: [
            {
              'id': 10,
              'user_id': 28,
              'contact_id': 1,
              'transaction_type': 'LOAN',
              'amount': '1000',
              'currency': 'IQD',
              'transaction_date': '2026-09-01T10:00:00Z',
              'note': 'first',
            },
            {
              'id': 11,
              'user_id': 28,
              'contact_id': 1,
              'transaction_type': 'LOAN',
              'amount': '500',
              'currency': 'IQD',
              'transaction_date': '2026-09-02T10:00:00Z',
              'note': 'second',
            },
            {
              'id': 20,
              'user_id': 28,
              'contact_id': 1,
              'transaction_type': 'PAYMENT',
              'amount': '1200',
              'currency': 'IQD',
              'transaction_date': '2026-09-03T10:00:00Z',
              'note': 'paid',
            },
          ],
        ),
      ),
      'kani-chnar-raw.json',
    );

    expect(bundle.customers, hasLength(1));
    expect(bundle.debts, hasLength(2));
    expect(bundle.payments, hasLength(2));
    expect(bundle.expectedBalanceIqd, 300);

    expect(bundle.payments[0]['source_id'], '20:1');
    expect(bundle.payments[0]['debt_source_id'], '10');
    expect(bundle.payments[0]['amount'], 1000);
    expect(bundle.payments[1]['source_id'], '20:2');
    expect(bundle.payments[1]['debt_source_id'], '11');
    expect(bundle.payments[1]['amount'], 200);
  });

  test('rejects an export whose pagination is incomplete', () {
    final data = _export(
      contacts: [
        {'id': 1, 'user_id': 28, 'name': 'Ali'},
      ],
      transactions: [
        {
          'id': 10,
          'user_id': 28,
          'contact_id': 1,
          'transaction_type': 'LOAN',
          'amount': 100,
          'currency': 'IQD',
          'transaction_date': '2026-09-01T10:00:00Z',
        },
      ],
      transactionsIncomplete: true,
    );

    expect(
      () => LegacyImportService.parseAuthorizedApiJsonBundle(
        _bytes(data),
        'incomplete.json',
      ),
      throwsException,
    );
  });

  test('rejects a payment that cannot be fully allocated', () {
    final data = _export(
      contacts: [
        {'id': 1, 'user_id': 28, 'name': 'Ali'},
      ],
      transactions: [
        {
          'id': 10,
          'user_id': 28,
          'contact_id': 1,
          'transaction_type': 'LOAN',
          'amount': 50,
          'currency': 'IQD',
          'transaction_date': '2026-09-01T10:00:00Z',
        },
        {
          'id': 20,
          'user_id': 28,
          'contact_id': 1,
          'transaction_type': 'PAYMENT',
          'amount': 100,
          'currency': 'IQD',
          'transaction_date': '2026-09-02T10:00:00Z',
        },
      ],
    );

    expect(
      () => LegacyImportService.parseAuthorizedApiJsonBundle(
        _bytes(data),
        'unallocatable.json',
      ),
      throwsException,
    );
  });

  test('rejects zero-amount history instead of silently dropping it', () {
    final data = _export(
      contacts: [
        {'id': 1, 'user_id': 28, 'name': 'Ali'},
      ],
      transactions: [
        {
          'id': 10,
          'user_id': 28,
          'contact_id': 1,
          'transaction_type': 'LOAN',
          'amount': 0,
          'currency': 'IQD',
          'transaction_date': '2026-09-01T10:00:00Z',
        },
      ],
    );

    expect(
      () => LegacyImportService.parseAuthorizedApiJsonBundle(
        _bytes(data),
        'zero.json',
      ),
      throwsException,
    );
  });

  test('rejects rows from a different legacy account', () {
    final data = _export(
      contacts: [
        {'id': 1, 'user_id': 99, 'name': 'Wrong account'},
      ],
      transactions: [
        {
          'id': 10,
          'user_id': 99,
          'contact_id': 1,
          'transaction_type': 'LOAN',
          'amount': 100,
          'currency': 'IQD',
          'transaction_date': '2026-09-01T10:00:00Z',
        },
      ],
    );

    expect(
      () => LegacyImportService.parseAuthorizedApiJsonBundle(
        _bytes(data),
        'wrong-account.json',
      ),
      throwsException,
    );
  });
}
