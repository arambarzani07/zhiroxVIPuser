const Duration dashboardRecentActivityWindow = Duration(hours: 24);

List<Map<String, dynamic>> filterAndSortRecentDashboardActivity(
  Iterable<Map<String, dynamic>> rows, {
  DateTime? now,
}) {
  final referenceNow = (now ?? DateTime.now()).toUtc();
  final cutoff = referenceNow.subtract(dashboardRecentActivityWindow);
  final filtered = <Map<String, dynamic>>[];

  for (final source in rows) {
    final row = Map<String, dynamic>.from(source);
    final rawType = row['event_type']?.toString().trim().toLowerCase() ?? '';
    // Older dashboard snapshots contained only debts and did not include an
    // explicit type. Treat those rows as debt activity during migration.
    final type = rawType.isEmpty ? 'debt' : rawType;
    if (type != 'debt' && type != 'payment') continue;

    final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (created == null) continue;
    final createdUtc = created.toUtc();
    if (createdUtc.isBefore(cutoff) || createdUtc.isAfter(referenceNow)) {
      continue;
    }

    row['event_type'] = type;
    filtered.add(row);
  }

  filtered.sort((a, b) {
    final aCreated = DateTime.parse(a['created_at'].toString()).toUtc();
    final bCreated = DateTime.parse(b['created_at'].toString()).toUtc();
    final byCreated = bCreated.compareTo(aCreated);
    if (byCreated != 0) return byCreated;
    return (b['id']?.toString() ?? '').compareTo(a['id']?.toString() ?? '');
  });

  return filtered;
}
