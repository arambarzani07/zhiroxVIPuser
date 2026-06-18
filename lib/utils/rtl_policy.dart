import 'package:flutter/widgets.dart';

class ZhiroxRtlPolicy {
  static const Locale locale = Locale('ckb');
  static const TextDirection appDirection = TextDirection.rtl;
  static const TextDirection numberDirection = TextDirection.ltr;
  static const String fontFamily = 'NotoKufiArabic';

  static TextDirection directionForValue(String value) {
    final hasLatinOrNumber = RegExp(r'[A-Za-z0-9]').hasMatch(value);
    return hasLatinOrNumber ? numberDirection : appDirection;
  }

  static Widget wrap(Widget child) {
    return Directionality(textDirection: appDirection, child: child);
  }
}
