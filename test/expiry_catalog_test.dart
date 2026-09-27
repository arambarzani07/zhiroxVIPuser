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

  test(
    'large cashier export maps unit barcode without using carton barcode',
    () {
      final preview = ExpiryCatalogService.parseFile(
        csv('barcode,product_name,carton_barcode,quantity\n0123,Milk,999,12\n'),
        'cashier.csv',
      );
      final mapping = preview.suggestedColumns();
      expect(mapping.code, 0);
      expect(mapping.name, 1);
      expect(mapping.barcode, 0);
      expect(mapping.category, isNull);
      expect(
        preview
            .products(
              codeColumn: mapping.code,
              nameColumn: mapping.name,
              barcodeColumn: mapping.barcode,
            )
            .single['barcode'],
        '0123',
      );
    },
  );

  test('41443 products stay ordered in request batches below RPC limit', () {
    final preview = ExpiryImportPreview(
      const ['barcode', 'product_name'],
      List.generate(41443, (index) => ['$index', 'کاڵا $index']),
      'cashier.csv',
    );
    final products = preview.products(codeColumn: 0, nameColumn: 1);
    expect(products.length, 41443);
    final rows = List.generate(41443, (index) => index);
    final batches = ExpiryCatalogService.importBatches(rows).toList();
    expect(batches.length, 42);
    expect(batches.every((batch) => batch.length <= 1000), isTrue);
    expect(batches.last.length, 443);
    expect(batches.expand((batch) => batch).toList(), rows);
  });
}
