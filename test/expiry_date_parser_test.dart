import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/features/expiry/expiry_date_parser.dart';

void main() {
  test('reads expiry instead of manufacturing date', () {
    final dates = ExpiryDateParser.candidates(
      'MFG: 01/01/2026\nEXP: 27/09/2027',
    );
    expect(dates, [DateTime(2027, 9, 27)]);
  });

  test('a photographed production date alone is not an expiry', () {
    expect(ExpiryDateParser.printedDateKind('P 01 07 2026'), 'production');
    expect(ExpiryDateParser.candidates('P 01 07 2026'), isEmpty);
  });

  test('additional printed expiry labels and date types', () {
    expect(ExpiryDateParser.printedDateKind('BBE 12/2026'), 'best_before');
    expect(ExpiryDateParser.candidates('BBE 12/2026'), [
      DateTime(2026, 12, 31),
    ]);
    expect(ExpiryDateParser.candidates('PKD 01/07/2026'), isEmpty);
    expect(ExpiryDateParser.candidates('EXD 28/12/2026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(
      ExpiryDateParser.printedDateKind('BBE 10/2026\nEXP 28/12/2026'),
      'expiry',
    );
  });

  test('recognizes attached EXP month and narrow OCR O/zero confusion', () {
    for (final printed in [
      'PROD 2023 EXP07 2026',
      'GLYSOLID BRSR344 FR? 2023 EXPO7 2026',
      'EXP 07 2026',
      'EXD07 2026',
    ]) {
      expect(ExpiryDateParser.printedDateKind(printed), 'expiry');
      expect(ExpiryDateParser.candidates(printed), [DateTime(2026, 7, 31)]);
      expect(ExpiryDateParser.isMonthYearOnly(printed), isTrue);
    }
    expect(ExpiryDateParser.candidates('PROD 07 2023'), isEmpty);
    expect(ExpiryDateParser.candidates('LOT 07 2026'), isEmpty);
    expect(ExpiryDateParser.candidates('EXPO8 PRODUCT'), isEmpty);
    expect(ExpiryDateParser.isMonthYearOnly('EXP 28/07/2026'), isFalse);
  });

  test(
    'accepts other labelled month/year layouts without production dates',
    () {
      for (final printed in [
        'EXP07 26',
        'EXP 07 26',
        'EX 07 2026',
        'BEST BEFORE 2026 07',
        'EXP 2026-07',
        'بەسەرچوون ٠٧ ٢٠٢٦',
      ]) {
        expect(ExpiryDateParser.candidates(printed), [DateTime(2026, 7, 31)]);
        expect(ExpiryDateParser.isMonthYearOnly(printed), isTrue);
      }
      expect(ExpiryDateParser.candidates('M 07 2023'), isEmpty);
      expect(ExpiryDateParser.candidates('PROD07 2023'), isEmpty);
      expect(ExpiryDateParser.candidates('LOT 07 26'), isEmpty);
    },
  );

  test('compact month/year is not silently mistaken for a full date', () {
    expect(ExpiryDateParser.candidates('EXP 202607'), [DateTime(2026, 7, 31)]);
    expect(
      ExpiryDateParser.candidates('EXP 072026'),
      containsAll([DateTime(2026, 7, 31), DateTime(2026, 7, 20)]),
    );
    expect(ExpiryDateParser.candidates('LOT 072026'), isEmpty);
  });

  test('recognizes type and prioritizes the labelled expiry on packaging', () {
    expect(
      ExpiryDateParser.printedDateKind('MFG 01/07/2026\nEXP 28/12/2026'),
      'expiry',
    );
    expect(
      ExpiryDateParser.candidates(
        'MFG 01/07/2026\nLOT 09/03/2027\nEXP 28/12/2026',
      ),
      [DateTime(2026, 12, 28)],
    );
    expect(ExpiryDateParser.candidates('EXP 28/12/2026 P 01/07/2026'), [
      DateTime(2026, 12, 28),
    ]);
    expect(
      ExpiryDateParser.printedDateKind('BEST BEFORE 12/2026'),
      'best_before',
    );
    expect(ExpiryDateParser.candidates('BEST BEFORE 12/2026'), [
      DateTime(2026, 12, 31),
    ]);
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
    expect(dates, hasLength(2));
    expect(dates, containsAll([DateTime(2027, 12, 8), DateTime(2027, 8, 12)]));
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
