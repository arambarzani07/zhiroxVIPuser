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

  test('reads spaced E date and ignores spaced P production date', () {
    expect(ExpiryDateParser.candidates('P 01 07 2026\nE 28 12 2026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('P 01 07 2026 E 28 12 2026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('P 01 07 2026'), isEmpty);
    expect(ExpiryDateParser.candidates('28 12 2026'), isEmpty);
  });

  test('rejects invalid calendar dates rather than normalizing them', () {
    expect(ExpiryDateParser.candidates('EXP 31/02/2027'), isEmpty);
    expect(ExpiryDateParser.candidates('MFG 01/01/2026'), isEmpty);
  });

  test('keeps ambiguous dates for human verification', () {
    final dates = ExpiryDateParser.candidates('EXP 08/12/2027\n09/12/2027');
    expect(dates, hasLength(4));
    expect(
      dates,
      containsAll([
        DateTime(2027, 12, 8),
        DateTime(2027, 8, 12),
        DateTime(2027, 12, 9),
        DateTime(2027, 9, 12),
      ]),
    );
  });

  test('accepts an explicitly corrected expiry date with a full year', () {
    expect(ExpiryDateParser.enteredDate('28/12/2026'), DateTime(2026, 12, 28));
    expect(ExpiryDateParser.enteredDate('٢٨/١٢/٢٠٢٦'), DateTime(2026, 12, 28));
    expect(ExpiryDateParser.enteredDate('28/12/26'), isNull);
    expect(ExpiryDateParser.enteredDate('31/02/2026'), isNull);
    expect(ExpiryDateParser.enteredDate('28/12/2028 extra'), isNull);
  });

  test('reads all common numeric orders and separators', () {
    expect(ExpiryDateParser.candidates('EXP 2026-12-28'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('EXP 28.12.26'), [
      DateTime(2026, 12, 28),
      DateTime(2028, 12, 26),
    ]);
    expect(ExpiryDateParser.candidates('EXP 12/28/2026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('P 01 07 2026 E 28 12 2026'), [
      DateTime(2026, 12, 28),
    ]);
  });

  test('never guesses whether an ambiguous date is US or day first', () {
    expect(ExpiryDateParser.candidates('EXP 01/02/2026'), [
      DateTime(2026, 1, 2),
      DateTime(2026, 2, 1),
    ]);
  });

  test('reads named months and full or shortened years', () {
    expect(ExpiryDateParser.candidates('EXP 28 DEC 2026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('EXP Dec 28, 2026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('E DEC 2026'), [DateTime(2026, 12, 31)]);
    expect(ExpiryDateParser.candidates('EXP 2026/02'), [DateTime(2026, 2, 28)]);
  });

  test('reads compact dates only when labelled and GS1 expiry YYMMDD', () {
    expect(ExpiryDateParser.candidates('EXP 20261228'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('EXP 28122026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('EXP 261228'), [
      DateTime(2026, 12, 28),
      DateTime(2028, 12, 26),
    ]);
    expect(ExpiryDateParser.candidates('(11)260701(17)261228'), [
      DateTime(2026, 12, 28),
    ]);
    expect(ExpiryDateParser.candidates('20261228'), isEmpty);
  });
}
