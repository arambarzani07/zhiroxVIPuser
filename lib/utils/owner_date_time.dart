import 'package:intl/intl.dart';

/// Formats an owner console timestamp, preserving the missing-date placeholder.
String ownerDateTime(dynamic value) {
  final parsed = DateTime.tryParse('${value ?? ''}');
  if (parsed == null) return '—';
  return DateFormat('yyyy/MM/dd HH:mm').format(parsed.toLocal());
}
