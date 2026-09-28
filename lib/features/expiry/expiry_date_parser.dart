/// Reads printed date candidates. The user must verify the date before saving.
class ExpiryDateParser {
  ExpiryDateParser._();

  static final _yearFirst = RegExp(
    r'(?<!\d)(20\d{2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{1,2})(?!\d)',
  );
  static final _dayFirst = RegExp(
    r'(?<!\d)(\d{1,2})\s*[/.-]\s*(\d{1,2})\s*[/.-]\s*(\d{2,4})(?!\d)',
  );
  static final _spacedDayFirst = RegExp(
    r'(?<!\d)(\d{1,2})\s+(\d{1,2})\s+(\d{2,4})(?!\d)',
  );
  static final _monthYear = RegExp(
    r'(?<![\d/.-])(\d{1,2})\s*[/.-]\s*(\d{2,4})(?!\d)',
  );
  static final _expiry = RegExp(
    r'\b(exp|expiry|expires|expiration|best\s*before|use\s*by|bb)\b|'
    r'(?<![a-z])e\s*[:：.]?\s*(?=\d|$)|'
    r'انتهاء|الانتهاء|الصلاحية|بەسەرچوون',
    caseSensitive: false,
  );
  static final _made = RegExp(
    r'\b(mfg|mfd|manufactur\w*|production|prod)\b|'
    r'(?<![a-z])p\s*[:：.]?\s*(?=\d|$)|'
    r'انتاج|الإنتاج|صنع|بەرهەمهێنان',
    caseSensitive: false,
  );

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

  static List<DateTime> candidates(String text) {
    final lines = _digits(text).split(RegExp(r'[\r\n]+'));
    final found = <DateTime, int>{};
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final expiryMark = _expiry.allMatches(line).lastOrNull;
      if (_made.hasMatch(line) && expiryMark == null) continue;
      // When production and expiry share a line, do not propose the
      // production date as an expiry candidate.
      final dateText = expiryMark == null
          ? line
          : line.substring(expiryMark.start);
      final preferred =
          expiryMark != null || (i > 0 && _expiry.hasMatch(lines[i - 1]));
      final score = preferred ? 10 : 1;

      void add(DateTime? date) {
        if (date != null && score > (found[date] ?? 0)) found[date] = score;
      }

      final fullDates = <String>{};
      for (final match in _yearFirst.allMatches(dateText)) {
        fullDates.add(match.group(0)!);
        add(
          _valid(
            int.parse(match[1]!),
            int.parse(match[2]!),
            int.parse(match[3]!),
          ),
        );
      }
      for (final match in _dayFirst.allMatches(dateText)) {
        if (fullDates.any((full) => full.contains(match.group(0)!))) continue;
        add(
          _valid(_year(match[3]!), int.parse(match[2]!), int.parse(match[1]!)),
        );
      }
      // Manufacturers also print "E 28 12 2026" without punctuation.
      // Bare spaced numbers are parsed only beside an expiry label.
      if (preferred) {
        for (final match in _spacedDayFirst.allMatches(dateText)) {
          add(
            _valid(
              _year(match[3]!),
              int.parse(match[2]!),
              int.parse(match[1]!),
            ),
          );
        }
      }
      // A package may print only a month and year. Its expiry is the last
      // calendar day of that month. Require an expiry label to avoid prices.
      if (preferred &&
          fullDates.isEmpty &&
          !_dayFirst.hasMatch(dateText) &&
          !_spacedDayFirst.hasMatch(dateText)) {
        for (final match in _monthYear.allMatches(dateText)) {
          final year = _year(match[2]!);
          final month = int.parse(match[1]!);
          if (year >= 2000 && year <= 2100 && month >= 1 && month <= 12) {
            add(DateTime(year, month + 1, 0));
          }
        }
      }
    }
    return found.keys.toList()..sort((a, b) {
      final ranking = found[b]!.compareTo(found[a]!);
      return ranking == 0 ? a.compareTo(b) : ranking;
    });
  }
}
