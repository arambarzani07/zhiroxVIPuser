from pathlib import Path

path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text(encoding='utf-8')

if 'Future<void> _generateFilteredFinancialChatStatement() async {' in text:
    print('Filtered Financial Chat statement already present.')
    raise SystemExit(0)

anchor = '  Future<void> _generateCurrentFinancialStatement() async {'
if anchor not in text:
    raise SystemExit('Current financial statement anchor missing')

method = r'''  Future<void> _generateFilteredFinancialChatStatement() async {
    final allItems = _buildTimelineItems();
    final visibleItems = _filterFinancialTimeline(allItems);
    if (visibleItems.isEmpty) {
      AppHelpers.showSnackBar(
        context,
        'هیچ مامەڵەیەک نییە بۆ کەشف/هاوبەشکردن',
        isError: true,
      );
      return;
    }

    final balances = _financialRunningBalances(allItems);
    String systemDescription(RecordModel record) {
      final type = record.getStringValue('event_type');
      final actor = record.getStringValue('actor_name').trim();
      final base = switch (type) {
        'debt_deleted' => 'قەرز سڕایەوە',
        'payment_updated' => 'پارەدانەوە دەستکاری کرا',
        'payment_deleted' => 'پارەدانەوە سڕایەوە',
        _ => 'قەرز دەستکاری کرا',
      };
      return actor.isEmpty ? base : '$base • $actor';
    }

    final entries = <Map<String, dynamic>>[];
    for (final item in visibleItems) {
      final record = item.record;
      final debt = item.isPayment ? item.relatedDebt : record;
      final currency = debt?.getStringValue('currency').isNotEmpty == true
          ? debt!.getStringValue('currency')
          : 'IQD';
      final description = item.isSystem
          ? systemDescription(record)
          : item.isPayment
              ? record.getStringValue('note').trim()
              : record.getStringValue('description').trim();
      entries.add({
        'type': item.kind,
        'date': item.date.toIso8601String(),
        'description': description,
        'amount': record.getDoubleValue('amount'),
        'currency': currency,
        'dollar_rate': debt?.getDoubleValue('dollar_rate') ?? 0,
        'balance_after_iqd': balances[_timelineLedgerKey(item)],
      });
    }

    final filterParts = <String>[];
    final query = _financialSearchController.text.trim();
    if (query.isNotEmpty) filterParts.add('گەڕان: $query');
    if (_financialDateRange != null) {
      filterParts.add(
        '${DateFormat('yyyy/MM/dd').format(_financialDateRange!.start)} — '
        '${DateFormat('yyyy/MM/dd').format(_financialDateRange!.end)}',
      );
    }
    final typeLabel = switch (_financialTypeFilter) {
      'debt' => 'قەرز',
      'payment' => 'پارەدانەوە',
      'system' => 'مێژووی گۆڕانکاری',
      _ => '',
    };
    if (typeLabel.isNotEmpty) filterParts.add(typeLabel);

    try {
      final auth = context.read<AuthProvider>();
      await PdfService.generateFinancialChatStatement(
        entries: entries,
        customerName: _user?.getStringValue('name') ?? '',
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        filterSummary:
            filterParts.isEmpty ? 'هەموو مامەڵەکان' : filterParts.join(' • '),
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'کەشفی چاتی دارایی دروست نەکرا. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

'''

text = text.replace(anchor, method + anchor, 1)
path.write_text(text, encoding='utf-8')
print('Restored filtered Financial Chat statement export.')
