/// Reads printed date candidates. The user must verify the date before saving.
class ExpiryDateParser {
  ExpiryDateParser._();

  static final _fullNumeric = RegExp(
    r'(?<!\d)(\d{1,4})\s*([/.-]|\s)\s*(\d{1,2})\s*([/.-]|\s)\s*(\d{2,4})(?!\d)',
  );
  static final _compactNumeric = RegExp(r'(?<!\d)(\d{6}|\d{8})(?!\d)');
  static final _gs1Expiry = RegExp(r'\(17\)\s*(\d{6})(?!\d)');
  static final _monthYear = RegExp(
    r'(?<![\d/.-])(\d{1,2})\s*[/.-]\s*(\d{2,4})(?!\d)',
  );
  static final _yearMonth = RegExp(
    r'(?<!\d)(20\d{2})\s*[/.-]\s*(\d{1,2})(?![/.-]\d|\d)',
  );
  static const _monthNames =
      r'jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|'
      r'jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|'
      r'nov(?:ember)?|dec(?:ember)?';
  static final _dayMonthName = RegExp(
    '(?<!\\d)(\\d{1,2})[\\s./-]+($_monthNames)[\\s,./-]+(\\d{2,4})(?!\\d)',
    caseSensitive: false,
  );
  static final _monthNameDay = RegExp(
    '($_monthNames)[\\s./-]+(\\d{1,2}),?[\\s./-]+(\\d{2,4})(?!\\d)',
    caseSensitive: false,
  );
  static final _monthNameYear = RegExp(
    '($_monthNames)[\\s./-]+(\\d{2,4})(?!\\d)',
    caseSensitive: false,
  );
  static final _bestBefore = RegExp(
    r'\b(best\s*before|bbd?|bbs)\b|يفضل\s*قبل|باشترە\s*پێش',
    caseSensitive: false,
  );
  static final _expiry = RegExp(
    r'\b(exp|expiry|expires|expiration|best\s*before|use\s*by|bbd?|bbs)\b|'
    r'(?<![a-z])e\s*[:：.]?\s*(?=\d|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|$)|'
    r'انتهاء|الانتهاء|الصلاحية|بەسەرچوون',
    caseSensitive: false,
  );
  static final _made = RegExp(
    r'\b(mfg|mfd|manufactur\w*|production|prod)\b|'
    r'(?<![a-z])p\s*[:：.]?\s*(?=\d|$)|'
    r'انتاج|الإنتاج|صنع|بەرهەمهێنان',
    caseSensitive: false,
  );

  /// A printed production date must never be presented as an expiry date.
  static String printedDateKind(String text) {
    final normalized = _digits(text);
    if (_expiry.hasMatch(normalized) || _gs1Expiry.hasMatch(normalized)) {
      return _bestBefore.hasMatch(normalized) ? 'best_before' : 'expiry';
    }
    return _made.hasMatch(normalized) ? 'production' : 'unlabelled';
  }

  static String _digits(String raw) {
    const local = '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹';
    return raw.replaceAllMapped(RegExp('[$local]'), (m) {
      final offset = local.indexOf(m[0]!);
      return '${offset % 10}';
    });
  }

  static DateTime? _valid(int year, int month, int day) {
    if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final date = DateTime(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static int _year(String text) {
    final value = int.parse(text);
    return value < 100 ? 2000 + value : value;
  }

  static int _monthName(String text) {
    const names = [
      'jan',
      'feb',
      'mar',
      'apr',
      'may',
      'jun',
      'jul',
      'aug',
      'sep',
      'oct',
      'nov',
      'dec',
    ];
    return names.indexOf(text.toLowerCase().substring(0, 3)) + 1;
  }

  /// A user-corrected date must have an explicit four-digit year. OCR may
  /// confuse 6 with 8, so never infer the year from a two-digit entry here.
  static DateTime? enteredDate(String text) {
    final match = RegExp(
      r'^\s*(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{4})\s*$',
    ).firstMatch(_digits(text));
    if (match == null) return null;
    return _valid(
      int.parse(match[3]!),
      int.parse(match[2]!),
      int.parse(match[1]!),
    );
  }

  static List<DateTime> candidates(String text) {
    final lines = _digits(text).split(RegExp(r'[\r\n]+'));
    final found = <DateTime, int>{};
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final expiryMark = _expiry.allMatches(line).lastOrNull;
      if (_made.hasMatch(line) &&
          expiryMark == null &&
          !_gs1Expiry.hasMatch(line)) {
        continue;
      }
      // When production and expiry share a line, do not propose the
      // production date as an expiry candidate.
      final afterMark = expiryMark == null
          ? line
          : line.substring(expiryMark.start);
      final nextProduction = expiryMark == null
          ? null
          : _made.firstMatch(
              afterMark.substring(expiryMark.end - expiryMark.start),
            );
      final dateText = nextProduction == null
          ? afterMark
          : afterMark.substring(
              0,
              expiryMark!.end - expiryMark.start + nextProduction.start,
            );
      final preferred =
          expiryMark != null || (i > 0 && _expiry.hasMatch(lines[i - 1]));
      final score = preferred ? 10 : 1;

      void add(DateTime? date) {
        if (date != null && score > (found[date] ?? 0)) found[date] = score;
      }

      // GS1 application identifier (17) explicitly means YYMMDD. Do not
      // reinterpret its six digits as a day-first or US month-first date.
      final gs1 = _gs1Expiry.allMatches(line).toList();
      if (gs1.isNotEmpty) {
        for (final match in gs1) {
          final raw = match[1]!;
          add(
            _valid(
              _year(raw.substring(0, 2)),
              int.parse(raw.substring(2, 4)),
              int.parse(raw.substring(4, 6)),
            ),
          );
        }
        continue;
      }

      var hasFullDate = false;
      for (final match in _fullNumeric.allMatches(dateText)) {
        if (match[2] == ' ' || match[4] == ' ') {
          if (!preferred) continue; // An unlabeled number could be a price.
        }
        final first = int.parse(match[1]!);
        final middle = int.parse(match[3]!);
        final last = int.parse(match[5]!);
        if (match[1]!.length == 4) {
          final date = _valid(first, middle, last);
          if (date != null) {
            add(date);
            hasFullDate = true;
          }
        } else {
          final dmy = _valid(_year(match[5]!), middle, first);
          final mdy = _valid(_year(match[5]!), first, middle);
          if (dmy != null) {
            add(dmy);
            hasFullDate = true;
          }
          // For 01/02/2026 neither order can be inferred from the print.
          if (mdy != null) {
            add(mdy);
            hasFullDate = true;
          }
          if (match[1]!.length == 2 && match[5]!.length == 2) {
            final ymd = _valid(_year(match[1]!), middle, last);
            if (ymd != null) {
              add(ymd);
              hasFullDate = true;
            }
          }
        }
      }
      for (final match in _dayMonthName.allMatches(dateText)) {
        final date = _valid(
          _year(match[3]!),
          _monthName(match[2]!),
          int.parse(match[1]!),
        );
        if (date != null) {
          add(date);
          hasFullDate = true;
        }
      }
      for (final match in _monthNameDay.allMatches(dateText)) {
        final date = _valid(
          _year(match[3]!),
          _monthName(match[1]!),
          int.parse(match[2]!),
        );
        if (date != null) {
          add(date);
          hasFullDate = true;
        }
      }
      if (preferred) {
        for (final match in _compactNumeric.allMatches(dateText)) {
          final raw = match[1]!;
          if (raw.length == 8 && raw.startsWith('20')) {
            final date = _valid(
              int.parse(raw.substring(0, 4)),
              int.parse(raw.substring(4, 6)),
              int.parse(raw.substring(6, 8)),
            );
            if (date != null) {
              add(date);
              hasFullDate = true;
            }
          } else {
            final parts = raw.length == 8 ? [2, 2, 4] : [2, 2, 2];
            final first = int.parse(raw.substring(0, parts[0]));
            final second = int.parse(
              raw.substring(parts[0], parts[0] + parts[1]),
            );
            final suffix = raw.substring(parts[0] + parts[1]);
            final dmy = _valid(_year(suffix), second, first);
            final mdy = _valid(_year(suffix), first, second);
            if (dmy != null) {
              add(dmy);
              hasFullDate = true;
            }
            if (mdy != null) {
              add(mdy);
              hasFullDate = true;
            }
            // Without a GS1 (17) prefix, YYMMDD is another valid reading of
            // six consecutive digits. Surface the ambiguity for confirmation.
            if (raw.length == 6) {
              final ymd = _valid(
                _year(raw.substring(0, 2)),
                int.parse(raw.substring(2, 4)),
                int.parse(raw.substring(4, 6)),
              );
              if (ymd != null) {
                add(ymd);
                hasFullDate = true;
              }
            }
          }
        }
      }
      // A package may print only a month and year. Its expiry is the last
      // calendar day of that month. Require an expiry label to avoid prices.
      if (preferred && !hasFullDate) {
        for (final match in _monthYear.allMatches(dateText)) {
          final year = _year(match[2]!);
          final month = int.parse(match[1]!);
          if (year >= 2000 && year <= 2100 && month >= 1 && month <= 12) {
            add(DateTime(year, month + 1, 0));
          }
        }
        for (final match in _yearMonth.allMatches(dateText)) {
          final year = int.parse(match[1]!);
          final month = int.parse(match[2]!);
          if (month >= 1 && month <= 12) add(DateTime(year, month + 1, 0));
        }
        for (final match in _monthNameYear.allMatches(dateText)) {
          final year = _year(match[2]!);
          if (year >= 2000 && year <= 2100) {
            add(DateTime(year, _monthName(match[1]!) + 1, 0));
          }
        }
      }
    }
    // A labelled expiry on the photo is stronger evidence than any other
    // printed numbers (batch, price, production or other dates).
    final labelled = found.values.any((score) => score == 10);
    return found.keys.where((date) => !labelled || found[date] == 10).toList()
      ..sort((a, b) {
        final ranking = found[b]!.compareTo(found[a]!);
        return ranking == 0 ? a.compareTo(b) : ranking;
      });
  }
}
