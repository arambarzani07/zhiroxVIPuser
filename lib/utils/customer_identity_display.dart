class CustomerIdentityDisplay {
  CustomerIdentityDisplay._();

  static final RegExp _legacyPhonePattern = RegExp(
    r'^legacy_[0-9a-f]{8}_([0-9]+)$',
    caseSensitive: false,
  );

  static bool isLegacyPlaceholderPhone(String value) =>
      _legacyPhonePattern.hasMatch(value.trim());

  static String visiblePhone(String value) {
    final normalized = value.trim();
    return isLegacyPlaceholderPhone(normalized) ? '' : normalized;
  }

  static String? legacySourceId(String value) =>
      _legacyPhonePattern.firstMatch(value.trim())?.group(1);

  static String identityTail(String value) {
    final normalized = value.trim();
    final sourceId = legacySourceId(normalized);
    if (sourceId != null) return '#$sourceId';

    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    final buffer = StringBuffer();
    for (final codePoint in normalized.runes) {
      final char = String.fromCharCode(codePoint);
      final latin = '0123456789'.indexOf(char);
      if (latin >= 0) {
        buffer.write(char);
        continue;
      }
      final arabic = arabicDigits.indexOf(char);
      if (arabic >= 0) {
        buffer.write(arabic);
        continue;
      }
      final persian = persianDigits.indexOf(char);
      if (persian >= 0) buffer.write(persian);
    }

    final digits = buffer.toString();
    if (digits.length <= 4) return digits;
    return digits.substring(digits.length - 4);
  }
}
