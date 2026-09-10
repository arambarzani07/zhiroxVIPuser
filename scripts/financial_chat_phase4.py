from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label}: marker not found')


path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text(encoding='utf-8')

# State for live, in-memory chat filtering. No business data is persisted.
text = replace_once(
    text,
    "  bool _hasNewFinancialActivity = false;\n\n  final _nameController = TextEditingController();",
    "  bool _hasNewFinancialActivity = false;\n  final _financialSearchController = TextEditingController();\n  DateTimeRange? _financialDateRange;\n  String _financialTypeFilter = 'all';\n\n  final _nameController = TextEditingController();",
    'financial filter state',
)

text = replace_once(
    text,
    "    _profileScrollController.dispose();\n    _connectivitySub?.cancel();",
    "    _profileScrollController.dispose();\n    _financialSearchController.dispose();\n    _connectivitySub?.cancel();",
    'financial search dispose',
)

# Insert filter/search/date helpers immediately before the timeline card builder.
if 'List<_ProfileTimelineItem> _filterFinancialTimeline(' not in text:
    marker = "  Widget _buildCustomerChatTimelineCard({\n"
    addition = r'''  List<_ProfileTimelineItem> _filterFinancialTimeline(
    List<_ProfileTimelineItem> items,
  ) {
    final query = _financialSearchController.text.trim().toLowerCase();
    final range = _financialDateRange;

    return items.where((item) {
      if (_financialTypeFilter != 'all' && item.kind != _financialTypeFilter) {
        return false;
      }

      if (range != null) {
        final day = DateTime(item.date.year, item.date.month, item.date.day);
        final start = DateTime(
          range.start.year,
          range.start.month,
          range.start.day,
        );
        final end = DateTime(range.end.year, range.end.month, range.end.day);
        if (day.isBefore(start) || day.isAfter(end)) return false;
      }

      if (query.isEmpty) return true;
      final record = item.record;
      final searchable = <String>[
        item.kind,
        record.getStringValue('description'),
        record.getStringValue('note'),
        record.getStringValue('status'),
        record.getStringValue('event_type'),
        record.getStringValue('actor_name'),
        record.getStringValue('currency'),
        record.getDoubleValue('amount').toString(),
        DateFormat('yyyy/MM/dd HH:mm').format(item.date),
        if (item.relatedDebt != null)
          item.relatedDebt!.getStringValue('description'),
        if (item.relatedDebt != null)
          item.relatedDebt!.getDoubleValue('amount').toString(),
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  Future<void> _pickFinancialDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _financialDateRange,
      helpText: 'فلتەری بەروار',
      cancelText: 'پاشگەزبوونەوە',
      confirmText: 'هەڵبژاردن',
      saveText: 'هەڵبژاردن',
    );
    if (!mounted || picked == null) return;
    setState(() => _financialDateRange = picked);
  }

  void _clearFinancialFilters() {
    if (_financialSearchController.text.isEmpty &&
        _financialDateRange == null &&
        _financialTypeFilter == 'all') {
      return;
    }
    _financialSearchController.clear();
    setState(() {
      _financialDateRange = null;
      _financialTypeFilter = 'all';
    });
  }

  Widget _buildFinancialChatTools({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasFilters = _financialSearchController.text.trim().isNotEmpty ||
        _financialDateRange != null ||
        _financialTypeFilter != 'all';
    final dateLabel = _financialDateRange == null
        ? 'بەروار'
        : '${DateFormat('yyyy/MM/dd').format(_financialDateRange!.start)} — '
            '${DateFormat('yyyy/MM/dd').format(_financialDateRange!.end)}';

    Widget typeChip(String value, String label, IconData icon) {
      final selected = _financialTypeFilter == value;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 7),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => setState(() => _financialTypeFilter = value),
          avatar: Icon(
            icon,
            size: 15,
            color: selected
                ? AppColors.primary
                : (isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085)),
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          visualDensity: VisualDensity.compact,
          side: BorderSide(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.28)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE4E7EC)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _financialSearchController,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'گەڕان لە قەرز، پارەدانەوە، بڕ یان تێبینی...',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            suffixIcon: _financialSearchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'سڕینەوەی گەڕان',
                    onPressed: () {
                      _financialSearchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
            isDense: true,
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE4E7EC),
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              typeChip('all', 'هەموو', Icons.all_inclusive_rounded),
              typeChip('debt', 'قەرز', Icons.north_east_rounded),
              typeChip('payment', 'پارەدانەوە', Icons.south_west_rounded),
              typeChip('system', 'مێژووی گۆڕانکاری', Icons.history_rounded),
            ],
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickFinancialDateRange,
                icon: const Icon(Icons.date_range_outlined, size: 17),
                label: Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _generateAccountStatement(
                  totalDebt: totalDebt,
                  totalRemaining: totalRemaining,
                  totalPaid: totalPaid,
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 17),
                label: const Text('کەشف / هاوبەشکردن'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(width: 5),
              IconButton(
                tooltip: 'پاککردنەوەی فلتەرەکان',
                onPressed: _clearFinancialFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 19),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFilteredTimelineEmptyState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 30,
            color: isDark ? AppDarkColors.textSecondary : Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'هیچ مامەڵەیەک لەم گەڕان/فلتەرەدا نەدۆزرایەوە',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppDarkColors.textPrimary
                  : const Color(0xFF344054),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _clearFinancialFilters,
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: const Text('هەموو مامەڵەکان پیشان بدە'),
          ),
        ],
      ),
    );
  }

'''
    if marker not in text:
        raise SystemExit('timeline card marker not found')
    text = text.replace(marker, addition + marker, 1)

# Make the timeline filter-aware and show filtered/total counts.
text = replace_once(
    text,
    "    final timelineItems = _buildTimelineItems();\n    final health = _debtHealth(totalRemaining, totalDebt);",
    "    final allTimelineItems = _buildTimelineItems();\n    final timelineItems = _filterFinancialTimeline(allTimelineItems);\n    final health = _debtHealth(totalRemaining, totalDebt);",
    'filtered timeline source',
)
text = replace_once(
    text,
    "                              '${timelineItems.length} مامەڵە • قەرز و پارەدانەوە لە یەک مێژوودا',",
    "                              '${timelineItems.length}/${allTimelineItems.length} مامەڵە • قەرز و پارەدانەوە لە یەک مێژوودا',",
    'timeline count',
)

# Put search/filter/date/share tools inside the existing Financial Chat header card.
text = replace_once(
    text,
    "                  Row(\n                    children: [\n                      _buildChatSummaryValue(\n                        label: 'قەرز',\n                        value: totalDebt,\n                        color: Colors.orange,\n                        isDark: isDark,\n                      ),\n                      const SizedBox(width: 7),\n                      _buildChatSummaryValue(\n                        label: 'دراوە',\n                        value: totalPaid,\n                        color: Colors.green,\n                        isDark: isDark,\n                      ),\n                      const SizedBox(width: 7),\n                      _buildChatSummaryValue(\n                        label: 'ماوە',\n                        value: totalRemaining,\n                        color: totalRemaining > 0 ? Colors.red : Colors.green,\n                        isDark: isDark,\n                      ),\n                    ],\n                  ),\n                ],",
    "                  Row(\n                    children: [\n                      _buildChatSummaryValue(\n                        label: 'قەرز',\n                        value: totalDebt,\n                        color: Colors.orange,\n                        isDark: isDark,\n                      ),\n                      const SizedBox(width: 7),\n                      _buildChatSummaryValue(\n                        label: 'دراوە',\n                        value: totalPaid,\n                        color: Colors.green,\n                        isDark: isDark,\n                      ),\n                      const SizedBox(width: 7),\n                      _buildChatSummaryValue(\n                        label: 'ماوە',\n                        value: totalRemaining,\n                        color: totalRemaining > 0 ? Colors.red : Colors.green,\n                        isDark: isDark,\n                      ),\n                    ],\n                  ),\n                  const SizedBox(height: 12),\n                  _buildFinancialChatTools(\n                    totalDebt: totalDebt,\n                    totalRemaining: totalRemaining,\n                    totalPaid: totalPaid,\n                  ),\n                ],",
    'chat tools insertion',
)

text = replace_once(
    text,
    "            if (timelineItems.isEmpty)\n              _buildEmptyTimelineState(isDark)\n            else\n              ..._buildFinancialChatMessages(timelineItems),",
    "            if (timelineItems.isEmpty)\n              allTimelineItems.isEmpty\n                  ? _buildEmptyTimelineState(isDark)\n                  : _buildFilteredTimelineEmptyState(isDark)\n            else\n              ..._buildFinancialChatMessages(timelineItems),",
    'filtered empty state',
)

# Payment bubbles now carry a visible reference to the debt they settle.
text = replace_once(
    text,
    "                    if (description.isNotEmpty) ...[\n                      const SizedBox(height: 6),\n                      Text(\n                        description,\n                        maxLines: 3,\n                        overflow: TextOverflow.ellipsis,\n                        style: TextStyle(\n                          color: isDark\n                              ? AppDarkColors.textSecondary\n                              : const Color(0xFF475467),\n                          fontSize: 11.5,\n                          height: 1.45,\n                        ),\n                      ),\n                    ],\n                    const SizedBox(height: 7),",
    "                    if (description.isNotEmpty) ...[\n                      const SizedBox(height: 6),\n                      Text(\n                        description,\n                        maxLines: 3,\n                        overflow: TextOverflow.ellipsis,\n                        style: TextStyle(\n                          color: isDark\n                              ? AppDarkColors.textSecondary\n                              : const Color(0xFF475467),\n                          fontSize: 11.5,\n                          height: 1.45,\n                        ),\n                      ),\n                    ],\n                    if (isPayment && relatedDebt != null) ...[\n                      const SizedBox(height: 7),\n                      _buildPaymentDebtReference(relatedDebt, color, isDark),\n                    ],\n                    if (!isPayment && receiptPath.isNotEmpty) ...[\n                      const SizedBox(height: 8),\n                      _buildReceiptPreview(record, receiptPath, color, isDark),\n                    ],\n                    const SizedBox(height: 7),",
    'bubble reference and receipt',
)

# Add compact reference + inline receipt preview helpers before statement generation.
if 'Widget _buildPaymentDebtReference(' not in text:
    marker = "  Future<void> _generateAccountStatement({\n"
    addition = r'''  Widget _buildPaymentDebtReference(
    RecordModel debt,
    Color accent,
    bool isDark,
  ) {
    final description = debt.getStringValue('description').trim();
    final currency = debt.getStringValue('currency').isEmpty
        ? 'IQD'
        : debt.getStringValue('currency');
    final amount = debt.getDoubleValue('amount');
    final amountText = AppHelpers.formatCurrencyWithType(
      amount,
      currency,
      dollarRate: debt.getDoubleValue('dollar_rate'),
      showConversion: currency == 'USD',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(
          start: BorderSide(color: accent, width: 2.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.reply_rounded, size: 14, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'پەیوەست بە قەرز',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description.isEmpty ? amountText : '$description • $amountText',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptPreview(
    RecordModel debt,
    String receiptPath,
    Color accent,
    bool isDark,
  ) {
    final imageUrl = PBService.pb.getFileUrl(debt, receiptPath).toString();
    return ClipRRect(
      borderRadius: BorderRadius.circular(11),
      child: Container(
        height: 88,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : const Color(0xFFF2F4F7),
          border: Border.all(color: accent.withValues(alpha: 0.14)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, size: 17, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      'وێنەی وەصڵ بەردەست نییە',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              end: 7,
              bottom: 7,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'وەصڵ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
    if marker not in text:
        raise SystemExit('statement marker not found')
    text = text.replace(marker, addition + marker, 1)

path.write_text(text, encoding='utf-8')

# Extend permanent policy verification with durable Phase 4 UX markers.
verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text(encoding='utf-8')
if 'Financial Chat Phase 4' not in verify:
    marker = "\n\nif violations:\n"
    addition = r'''

# Financial Chat Phase 4 must remain live-only and keep its integrated search,
# date/type filters, debt references, receipt preview and statement/share action.
profile = (LIB / 'screens/shared/user_profile_screen.dart').read_text(encoding='utf-8')
for marker_name in (
    '_financialSearchController',
    '_financialDateRange',
    "_financialTypeFilter = 'all'",
    '_filterFinancialTimeline',
    'showDateRangePicker',
    '_buildPaymentDebtReference',
    '_buildReceiptPreview',
    'Image.network(',
    'کەشف / هاوبەشکردن',
):
    if marker_name not in profile:
        fail(f'lib/screens/shared/user_profile_screen.dart: Financial Chat Phase 4 marker missing: {marker_name}')
'''
    if marker not in verify:
        raise SystemExit('verify insertion marker not found')
    verify = verify.replace(marker, addition + marker, 1)
verify_path.write_text(verify, encoding='utf-8')
