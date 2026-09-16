from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f'marker not found: {label}')
    return text.replace(old, new, 1)


def splice(text: str, start_marker: str, end_marker: str, replacement: str, label: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f'start marker not found: {label}')
    end = text.find(end_marker, start)
    if end < 0:
        raise RuntimeError(f'end marker not found: {label}')
    return text[:start] + replacement + text[end:]


profile_path = Path('lib/screens/shared/user_profile_screen.dart')
profile = profile_path.read_text()

profile = replace_once(
    profile,
    "import 'package:zhirox/services/financial_date_range_summary.dart';\n",
    "import 'package:zhirox/services/financial_date_range_summary.dart';\nimport 'package:zhirox/services/financial_ui_state.dart';\n",
    'profile import',
)
profile = replace_once(
    profile,
    "  String _financialTypeFilter = 'all';\n  _ProfileTimelineItem? _financialReplyTarget;",
    "  String _financialTypeFilter = 'all';\n  bool _financialFiltersExpanded = false;\n  _ProfileTimelineItem? _financialReplyTarget;",
    'filter state',
)
profile = replace_once(
    profile,
    """    setState(() {
      _financialDateRange = null;
      _financialTypeFilter = 'all';
    });
  }

  Widget _buildFinancialChatTools({""",
    """    setState(() {
      _financialDateRange = null;
      _financialTypeFilter = 'all';
      _financialFiltersExpanded = false;
    });
  }

  Widget _buildFinancialChatTools({""",
    'clear filters',
)

financial_tools = r'''  Widget _buildFinancialChatTools({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeFilterCount = countActiveFinancialFilters(
      query: _financialSearchController.text,
      hasDateRange: _financialDateRange != null,
      typeFilter: _financialTypeFilter,
    );
    final expanded = shouldExpandFinancialFilters(
      requestedExpanded: _financialFiltersExpanded,
      activeFilterCount: activeFilterCount,
    );
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
          onSelected: (_) {
            setState(() => _financialTypeFilter = value);
            unawaited(_hydrateFinancialHistoryForFilters());
          },
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

    Widget quickChip(FinancialQuickRange preset, String label) {
      final resolved = resolveFinancialQuickRange(preset, DateTime.now());
      final active = _financialDateRange;
      final selected = active != null &&
          active.start.year == resolved.start.year &&
          active.start.month == resolved.start.month &&
          active.start.day == resolved.start.day &&
          active.end.year == resolved.end.year &&
          active.end.month == resolved.end.month &&
          active.end.day == resolved.end.day;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 7),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => _applyFinancialQuickRange(preset),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 10.25,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          visualDensity: VisualDensity.compact,
          side: BorderSide(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.30)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : const Color(0xFFE4E7EC)),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.025)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE4E7EC),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => setState(
                    () => _financialFiltersExpanded = !expanded,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'گەڕان و فلتەر',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (activeFilterCount > 0) ...[
                          const SizedBox(width: 7),
                          Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$activeFilterCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 19,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF667085),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE4E7EC),
              ),
              TextButton.icon(
                onPressed: _generateFilteredFinancialChatStatement,
                icon: const Icon(Icons.ios_share_rounded, size: 16),
                label: const Text('کەشف'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE4E7EC),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _financialSearchController,
                    onChanged: (_) {
                      setState(() {});
                      _scheduleFinancialSearchHydration();
                    },
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'گەڕان لە مامەڵە، بڕ یان تێبینی...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      suffixIcon: _financialSearchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'سڕینەوەی گەڕان',
                              onPressed: () {
                                _financialSearchDebounce?.cancel();
                                _financialSearchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.07)
                              : const Color(0xFFE4E7EC),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        typeChip('all', 'هەموو', Icons.all_inclusive_rounded),
                        typeChip('debt', 'قەرز', Icons.north_east_rounded),
                        typeChip(
                          'payment',
                          'پارەدانەوە',
                          Icons.south_west_rounded,
                        ),
                        typeChip('system', 'گۆڕانکاری', Icons.history_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        quickChip(FinancialQuickRange.today, 'ئەمڕۆ'),
                        quickChip(FinancialQuickRange.yesterday, 'دوێنێ'),
                        quickChip(FinancialQuickRange.last7Days, '7 ڕۆژ'),
                        quickChip(FinancialQuickRange.last30Days, '30 ڕۆژ'),
                        quickChip(FinancialQuickRange.thisMonth, 'ئەم مانگە'),
                        quickChip(
                          FinancialQuickRange.lastMonth,
                          'مانگی ڕابردوو',
                        ),
                        quickChip(FinancialQuickRange.thisYear, 'ئەم ساڵە'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
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
                            minimumSize: const Size.fromHeight(40),
                            textStyle: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                        ),
                      ),
                      if (activeFilterCount > 0) ...[
                        const SizedBox(width: 7),
                        OutlinedButton.icon(
                          onPressed: _clearFinancialFilters,
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 17,
                          ),
                          label: const Text('پاککردنەوە'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            textStyle: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }

'''
profile = splice(
    profile,
    '  Widget _buildFinancialChatTools({',
    '  Widget _buildFilteredTimelineEmptyState',
    financial_tools,
    'financial tools',
)
profile = replace_once(
    profile,
    "label: const Text('پوختەی قەرز'),",
    "label: const Text('کەشفی گشتی'),",
    'global statement label',
)

summary_start = """                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildChatSummaryValue(
                        label: 'قەرز',"""
summary_end = """                  const SizedBox(height: 12),
                  _buildFinancialChatTools("""
compact_summary_call = r'''                  const SizedBox(height: 12),
                  _buildCompactFinancialOverview(
                    totalDebt: totalDebt,
                    totalPaid: totalPaid,
                    totalRemaining: totalRemaining,
                    totalsComplete: totalsComplete,
                    healthLabel: health.$1,
                    healthColor: health.$2,
                    isDark: isDark,
                  ),
'''
profile = splice(
    profile,
    summary_start,
    summary_end,
    compact_summary_call,
    'header summary',
)
profile = replace_once(
    profile,
    r'''            const SizedBox(height: 9),
            if (totalsComplete)
              _buildDebtHealthStrip(
                label: health.$1,
                color: health.$2,
                totalRemaining: totalRemaining,
                totalPaid: totalPaid,
              )
            else
              _buildCurrencySummaryWarning(compact: true),
            const SizedBox(height: 12),
''',
    r'''            const SizedBox(height: 9),
            if (!totalsComplete) _buildCurrencySummaryWarning(compact: true),
            const SizedBox(height: 12),
''',
    'health strip use',
)

compact_methods = r'''  Widget _buildCompactFinancialOverview({
    required double totalDebt,
    required double totalPaid,
    required double totalRemaining,
    required bool totalsComplete,
    required String healthLabel,
    required Color healthColor,
    required bool isDark,
  }) {
    final remainingColor = totalsComplete && totalRemaining <= 0
        ? Colors.green.shade700
        : Colors.red.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.035)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE4E7EC),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ماوەی هەژمار',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      totalsComplete
                          ? AppHelpers.formatCurrency(totalRemaining)
                          : '—',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                        color: remainingColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (totalsComplete)
                Container(
                  constraints: const BoxConstraints(maxWidth: 170),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: healthColor.withValues(alpha: isDark ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 13,
                        color: healthColor,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          healthLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: healthColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE4E7EC),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactMetric(
                  label: 'کۆی قەرز',
                  value: totalsComplete
                      ? AppHelpers.formatCurrency(totalDebt)
                      : '—',
                  color: Colors.orange.shade800,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCompactMetric(
                  label: 'پارەدانەوە',
                  value: totalsComplete
                      ? AppHelpers.formatCurrency(totalPaid)
                      : '—',
                  color: Colors.green.shade700,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMetric({
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

'''
insert_marker = '  Widget _buildFinancialRangeSummary('
insert_at = profile.find(insert_marker)
if insert_at < 0:
    raise RuntimeError('range summary marker missing')
profile = profile[:insert_at] + compact_methods + profile[insert_at:]

health_start = profile.find('  Widget _buildDebtHealthStrip({')
if health_start >= 0:
    health_end = profile.find('  Widget _buildEmptyTimelineState(', health_start)
    if health_end < 0:
        raise RuntimeError('health strip end marker missing')
    profile = profile[:health_start] + profile[health_end:]

profile = profile.replace(
    r'''              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('پوختەی قەرز'),
                onTap: () => Navigator.pop(sheetContext, 'statement'),
              ),
''',
    '',
    1,
)
profile = profile.replace(
    r'''      case 'statement':
        await _generateCurrentFinancialStatement();
        break;
''',
    '',
    1,
)
profile_path.write_text(profile)


payment_path = Path('lib/screens/shared/financial_payment_flow.dart')
payment = payment_path.read_text()
payment = replace_once(
    payment,
    "import 'package:zhirox/services/customer_payment_allocator.dart';\n",
    "import 'package:zhirox/services/customer_payment_allocator.dart';\nimport 'package:zhirox/services/financial_ui_state.dart';\n",
    'payment import',
)

progress_methods = r'''  static Widget _buildPaymentProgress(
    FinancialPaymentStep step,
    bool isDark,
  ) {
    const steps = [
      (FinancialPaymentStep.target, 'قەرز'),
      (FinancialPaymentStep.amount, 'بڕ'),
      (FinancialPaymentStep.review, 'پشتڕاستکردنەوە'),
    ];
    final currentIndex = steps.indexWhere((entry) => entry.$1 == step);
    return Row(
      children: List.generate(steps.length * 2 - 1, (index) {
        if (index.isOdd) {
          final connectorIndex = index ~/ 2;
          final completed = connectorIndex < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              color: completed
                  ? AppColors.primary
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : const Color(0xFFE4E7EC)),
            ),
          );
        }
        final stepIndex = index ~/ 2;
        final active = stepIndex == currentIndex;
        final completed = stepIndex < currentIndex;
        final color = active || completed
            ? AppColors.primary
            : (isDark
                ? AppDarkColors.textSecondary
                : const Color(0xFF98A2B3));
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 25,
              height: 25,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active || completed
                    ? AppColors.primary.withValues(alpha: active ? 0.16 : 0.10)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : const Color(0xFFF2F4F7)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active || completed
                      ? AppColors.primary.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: completed
                  ? Icon(Icons.check_rounded, size: 14, color: color)
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
            ),
            const SizedBox(height: 3),
            Text(
              steps[stepIndex].$2,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        );
      }),
    );
  }

  static Widget _buildInlineReview({
    required bool isAll,
    required RecordModel? debt,
    required double before,
    required double amount,
    required double after,
    required int allocationCount,
    required bool isDark,
  }) {
    final amountText = isAll
        ? AppHelpers.formatCurrency(amount)
        : _formatDisplay(debt!, amount);
    final beforeText = isAll
        ? AppHelpers.formatCurrency(before)
        : _formatDisplay(debt!, before);
    final afterText = isAll
        ? AppHelpers.formatCurrency(after)
        : _formatDisplay(debt!, after);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.09 : 0.055),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 7),
              Text(
                'پێداچوونەوەی کۆتایی',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _confirmationRow('ماوەی پێش پارەدان', beforeText, isDark),
          const SizedBox(height: 7),
          _confirmationRow(
            'بڕی پارەدان',
            amountText,
            isDark,
            valueColor: Colors.green.shade700,
          ),
          if (isAll) ...[
            const SizedBox(height: 7),
            _confirmationRow(
              'ژمارەی قەرزی کاریگەر',
              '$allocationCount',
              isDark,
            ),
          ],
          const Divider(height: 18),
          _confirmationRow(
            'ماوەی دوای پارەدان',
            afterText,
            isDark,
            valueColor: after <= 0 ? Colors.green : Colors.orange,
            emphasized: true,
          ),
          if (isAll) ...[
            const SizedBox(height: 8),
            Text(
              'بڕەکە لە قەرزە کۆنترەکانەوە بەرەو نوێترەکان دابەش دەکرێت.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
              ),
            ),
          ],
        ],
      ),
    );
  }

'''
payment = splice(
    payment,
    '  static Future<bool> _confirmSingle({',
    '  static Widget _confirmationRow(',
    progress_methods,
    'payment confirmation helpers',
)
payment = replace_once(
    payment,
    "    var saving = false;\n    var showNote = false;\n    String? localError;",
    "    var saving = false;\n    var showNote = false;\n    var reviewMode = false;\n    String? localError;",
    'review state',
)
payment = replace_once(
    payment,
    """            final remainingAfter = (remainingStorage - typedStorageAmount)
                .clamp(0.0, remainingStorage)
                .toDouble();

            void applyQuickAmount""",
    """            final remainingAfter = (remainingStorage - typedStorageAmount)
                .clamp(0.0, remainingStorage)
                .toDouble();
            final paymentStep = resolveFinancialPaymentStep(
              targetSelected: selectedDebtId.isNotEmpty,
              amount: typedStorageAmount,
              maximum: remainingStorage,
              reviewRequested: reviewMode,
            );
            var previewAllocationCount = 1;
            if (isAll &&
                typedStorageAmount > 0 &&
                typedStorageAmount <= remainingStorage + 0.0001) {
              try {
                previewAllocationCount =
                    _customerAllocations(openDebts, typedStorageAmount).length;
              } catch (_) {}
            }

            void applyQuickAmount""",
    'payment step computation',
)
payment = replace_once(
    payment,
    """              setSheetState(() => localError = null);
            }

            return Container(""",
    """              setSheetState(() {
                localError = null;
                reviewMode = false;
              });
            }

            return Container(""",
    'quick amount reset',
)
payment = replace_once(
    payment,
    """                    const SizedBox(height: 16),
                    if (openDebts.length > 1) ...[""",
    """                    const SizedBox(height: 14),
                    _buildPaymentProgress(paymentStep, isDark),
                    const SizedBox(height: 16),
                    if (openDebts.length > 1) ...[""",
    'progress insertion',
)
payment = replace_once(
    payment,
    """                                setSheetState(() {
                                  selectedDebtId = value;
                                  localError = null;
                                });""",
    """                                setSheetState(() {
                                  selectedDebtId = value;
                                  localError = null;
                                  reviewMode = false;
                                });""",
    'target reset',
)
payment = replace_once(
    payment,
    "onChanged: (_) => setSheetState(() => localError = null),",
    """onChanged: (_) => setSheetState(() {
                        localError = null;
                        reviewMode = false;
                      }),""",
    'amount reset',
)
payment = replace_once(
    payment,
    """                    const SizedBox(height: 10),
                    if (showNote)
                      TextField(""",
    """                    if (reviewMode &&
                        typedStorageAmount > 0 &&
                        typedStorageAmount <= remainingStorage + 0.0001) ...[
                      const SizedBox(height: 10),
                      _buildInlineReview(
                        isAll: isAll,
                        debt: debt,
                        before: remainingStorage,
                        amount: typedStorageAmount,
                        after: remainingAfter,
                        allocationCount: previewAllocationCount,
                        isDark: isDark,
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (showNote)
                      TextField(""",
    'inline review',
)
payment = replace_once(
    payment,
    r'''                              var allocationCount = 1;
                              bool confirmed;
                              if (isAll) {
                                try {
                                  allocationCount = _customerAllocations(
                                    openDebts,
                                    storageAmount,
                                  ).length;
                                } catch (_) {
                                  setSheetState(() => localError =
                                      'بڕی پارەدانەوە لە کۆی ماوەی کڕیار زیاترە.');
                                  return;
                                }
                                confirmed = await _confirmCustomer(
                                  context: sheetContext,
                                  currentBalance: customerBalance,
                                  amount: storageAmount,
                                  allocationCount: allocationCount,
                                );
                              } else {
                                confirmed = await _confirmSingle(
                                  context: sheetContext,
                                  debt: debt!,
                                  storageAmount: storageAmount,
                                );
                              }
                              if (!confirmed || !sheetContext.mounted) return;

                              setSheetState(() {
                                saving = true;
                                localError = null;
                              });
''',
    r'''                              var allocationCount = 1;
                              if (isAll) {
                                try {
                                  allocationCount = _customerAllocations(
                                    openDebts,
                                    storageAmount,
                                  ).length;
                                } catch (_) {
                                  setSheetState(() => localError =
                                      'بڕی پارەدانەوە لە کۆی ماوەی کڕیار زیاترە.');
                                  return;
                                }
                              }

                              if (!reviewMode) {
                                FocusScope.of(sheetContext).unfocus();
                                setSheetState(() {
                                  reviewMode = true;
                                  localError = null;
                                });
                                return;
                              }

                              setSheetState(() {
                                saving = true;
                                localError = null;
                              });
''',
    'inline review submit',
)
payment = replace_once(
    payment,
    """                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        saving ? 'تۆمار دەکرێت...' : 'پێداچوونەوە و تۆمارکردن',
                      ),""",
    """                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              reviewMode
                                  ? Icons.check_rounded
                                  : Icons.navigate_next_rounded,
                            ),
                      label: Text(
                        saving
                            ? 'تۆمار دەکرێت...'
                            : reviewMode
                                ? 'تۆمارکردنی پارەدانەوە'
                                : 'پێداچوونەوە',
                      ),""",
    'submit button',
)
payment_path.write_text(payment)

workflow = Path('.github/workflows/finance-ux-cleanup-once.yml')
if workflow.exists():
    workflow.unlink()
Path(__file__).unlink()
