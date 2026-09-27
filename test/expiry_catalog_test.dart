import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/features/expiry/expiry_catalog_service.dart';

void main() {
  Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));

  test(
    'catalog import maps cashier columns without importing counts or debt',
    () {
      final preview = ExpiryCatalogService.parseFile(
        csv(
          'Name,Count,Barcode,Code,Expires\nMilk,12,0123456789,M-1,2026-11-01\n',
        ),
        'products.csv',
      );
      expect(preview.products(codeColumn: 3, nameColumn: 0, barcodeColumn: 2), [
        {
          'external_code': 'M-1',
          'name': 'Milk',
          'barcode': '0123456789',
          'category': '',
        },
      ]);
    },
  );

  test('two different products cannot share a scanned barcode', () {
    final preview = ExpiryCatalogService.parseFile(
      csv('code,name,barcode\nA,Milk,555\nB,Juice,555\n'),
      'products.csv',
    );
    expect(
      () => preview.products(codeColumn: 0, nameColumn: 1, barcodeColumn: 2),
      throwsFormatException,
    );
  });
}
