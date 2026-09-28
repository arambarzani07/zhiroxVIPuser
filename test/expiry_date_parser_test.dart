import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/features/expiry/expiry_date_parser.dart';

void main() {
  test('reads expiry instead of manufacturing date', () {
    final dates = ExpiryDateParser.candidates(
      'MFG: 01/01/2026\nEXP: 27/09/2027',
    );
    expect(dates, [DateTime(2027, 9, 27)]);
  });

  test('normalizes Arabic and Persian digits', () {
    expect(ExpiryDateParser.candidates('تاريخ الانتهاء ۲۰۲۷/۰۹/۲۷'), [
      DateTime(2027, 9, 27),
    ]);
    expect(ExpiryDateParser.candidates('EXP: ٢٧/٠٩/٢٧'), [
      DateTime(2027, 9, 27),
    ]);
  });

  test('month and year expire at end of printed month', () {
    expect(ExpiryDateParser.candidates('EXP 02/28'), [DateTime(2028, 2, 29)]);
  });

  test('rejects invalid calendar dates rather than normalizing them', () {
    expect(ExpiryDateParser.candidates('EXP 31/02/2027'), isEmpty);
    expect(ExpiryDateParser.candidates('MFG 01/01/2026'), isEmpty);
  });

  test('keeps ambiguous dates for human verification', () {
    expect(ExpiryDateParser.candidates('EXP 08/12/2027\n09/12/2027'), [
      DateTime(2027, 12, 8),
      DateTime(2027, 12, 9),
    ]);
  });
}
