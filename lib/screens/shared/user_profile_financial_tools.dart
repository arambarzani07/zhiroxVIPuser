part of 'user_profile_screen.dart';

extension _UserProfileFinancialTools on _UserProfileScreenState {
  DateTime _timelineDate(RecordModel record) {
    final customDate = record.getStringValue('custom_date');
    final created = record.getStringValue('created');
    for (final candidate in [customDate, created]) {
      if (candidate.isEmpty) continue;
      try {
        return DateTime.parse(candidate).toLocal();
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<_ProfileTimelineItem> _buildTimelineItems() {
    final debtsById = {for (final debt in _debts) debt.id: debt};
    final items = <_ProfileTimelineItem>[
      for (final debt in _debts)
        _ProfileTimelineItem(
          kind: 'debt',
          record: debt,
          date: _timelineDate(debt),
        ),
      for (final payment in _payments)
        _ProfileTimelineItem(
          kind: 'payment',
          record: payment,
          relatedDebt: debtsById[payment.getStringValue('debt')] ??
              AppHelpers.expandedRecord(payment, 'debt'),
          date: _timelineDate(payment),
        ),
      for (final event in _financialEvents)
        if (const <String>{
          'debt_updated',
          'debt_deleted',
          'payment_updated',
          'payment_deleted',
        }.contains(event.getStringValue('event_type')))
          _ProfileTimelineItem(
            kind: 'system',
            record: event,
            date: _timelineDate(event),
          ),
    ];

    // Oldest first gives a natural chat/timeline flow.
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  List<_ProfileTimelineItem> _filterFinancialTimeline(
    List<_ProfileTimelineItem> items,
  ) {
    final query = _financialSearchController.text.trim().toLowerCase();
    final range = _financialDateRange;

    return items.where((item) {
      if (_financialTypeFilter != 'all' && item.kind != _financialTypeFilter) {
        return false;
      }

      if (range != null &&
          !isWithinFinancialDateRange(
            item.date,
            start: range.start,
            end: range.end,
          )) {
        return false;
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

  String _timelineLedgerKey(_ProfileTimelineItem item) =>
      '${item.kind}:${item.record.id}';

  double? _timelineAmountInIqd(_ProfileTimelineItem item) {
    if (item.isSystem) return 0;
    if (item.isGeneralPayment) {
      return item.record.getDoubleValue('amount');
    }

    final debt = item.isPayment ? item.relatedDebt : item.record;
    final currency = debt?.getStringValue('currency').trim().toUpperCase() ?? 'IQD';
    final dollarRate = debt?.getDoubleValue('dollar_rate') ?? 0;

    // Current writes use IQD as the canonical storage unit. Some legacy USD
    // rows predate that rule and have no conversion rate; mixing those raw USD
    // values into an IQD running balance would be financially incorrect.
    if (currency == 'USD' && dollarRate <= 0) return null;
    return item.record.getDoubleValue('amount');
  }

  Map<String, double?> _financialRunningBalances(
    List<_ProfileTimelineItem> items,
  ) {
    var running = 0.0;
    var complete = true;
    final balances = <String, double?>{};
    for (final item in items) {
      if (item.isSystem) continue;
      final normalized = _timelineAmountInIqd(item);
      if (normalized == null) {
        complete = false;
      } else if (item.isPayment) {
        running -= normalized;
      } else {
        running += normalized;
      }
      if (running.abs() < 0.000001) running = 0;
      balances[_timelineLedgerKey(item)] = complete ? running : null;
    }
    return balances;
  }

  String? _overdueDebtLabel(RecordModel debt) {
    if (debt.getStringValue('status') == 'paid') return null;
    final raw = debt.getStringValue('due_date').trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(parsed.year, parsed.month, parsed.day);
    if (!due.isBefore(today)) return null;
    final days = today.difference(due).inDays;
    return '$days ڕۆژ دواکەوتوو';
  }

  void _showIncompleteCurrencySummaryMessage() {
    AppHelpers.showSnackBar(
      context,
      'هەندێک قەرزی USD نرخی گۆڕینەوەی دروستی نییە؛ بۆ پاراستنی دروستی ژمارەکان کۆی گشتی پیشان نادرێت.',
      isError: true,
    );
  }

  Widget _buildCurrencySummaryWarning({bool compact = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warning = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 11 : 13,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_exchange_rounded, size: 17, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'کۆی دارایی نیشان نادرێت چونکە هەندێک USD نرخی گۆڕینەوەی نییە.',
              style: TextStyle(
                fontSize: compact ? 9.5 : 10.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF7A5B00),
              ),
            ),
          ),
        ],
      ),
    );
    if (compact) return warning;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: warning,
      ),
    );
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
    _setProfileState(() {
      _financialDateRange = picked;
      // A date range means "show the customer's financial activity in this
      // period". Reset a previous single-kind chip so debt and payment rows
      // are both visible immediately.
      _financialTypeFilter = 'all';
    });
    unawaited(_hydrateFinancialHistoryForFilters());
  }

  void _applyFinancialQuickRange(FinancialQuickRange preset) {
    final resolved = resolveFinancialQuickRange(preset, DateTime.now());
    _setProfileState(() {
      _financialDateRange = DateTimeRange(
        start: resolved.start,
        end: resolved.end,
      );
      _financialTypeFilter = 'all';
    });
    unawaited(_hydrateFinancialHistoryForFilters());
  }

  void _clearFinancialFilters() {
    if (_financialSearchController.text.isEmpty &&
        _financialDateRange == null &&
        _financialTypeFilter == 'all') {
      return;
    }
    _financialSearchDebounce?.cancel();
    _financialSearchController.clear();
    _setProfileState(() {
      _financialDateRange = null;
      _financialTypeFilter = 'all';
      _financialFiltersExpanded = false;
    });
  }

  Widget _buildFinancialChatTools({
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
        padding: const EdgeInsetsDirectional.only(end: 5),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) {
            _setProfileState(() => _financialTypeFilter = value);
            unawaited(_hydrateFinancialHistoryForFilters());
          },
          avatar: Icon(
            icon,
            size: 14,
            color: selected
                ? AppColors.primary
                : (isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085)),
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 10,
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
        padding: const EdgeInsetsDirectional.only(end: 5),
        child: ChoiceChip(
          selected: selected,
          onSelected: (_) => _applyFinancialQuickRange(preset),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 9.75,
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
        borderRadius: BorderRadius.circular(10),
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
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _setProfileState(
                    () => _financialFiltersExpanded = !expanded,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'گەڕان و فلتەر',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (activeFilterCount > 0) ...[
                          const SizedBox(width: 5),
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
                height: 24,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFE4E7EC),
              ),
              TextButton.icon(
                onPressed: _generateFilteredFinancialChatStatement,
                icon: const Icon(Icons.ios_share_rounded, size: 15),
                label: const Text('کەشف'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(
                    fontSize: 10,
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
              padding: const EdgeInsets.fromLTRB(9, 1, 9, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE4E7EC),
                  ),
                  const SizedBox(height: 5),
                  TextField(
                    controller: _financialSearchController,
                    onChanged: (_) {
                      _setProfileState(() {});
                      _scheduleFinancialSearchHydration();
                    },
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'گەڕان لە مامەڵە، بڕ یان تێبینی...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 17),
                      suffixIcon: _financialSearchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'سڕینەوەی گەڕان',
                              onPressed: () {
                                _financialSearchDebounce?.cancel();
                                _financialSearchController.clear();
                                _setProfileState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 16),
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.07)
                              : const Color(0xFFE4E7EC),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        typeChip('all', 'هەموو', Icons.all_inclusive_rounded),
                        typeChip('debt', 'قەرز', Icons.north_east_rounded),
                        typeChip(
                          'payment',
                          'پارە وەرگرتنەوە',
                          Icons.south_west_rounded,
                        ),
                        typeChip('system', 'گۆڕانکاری', Icons.history_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 5),
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFinancialDateRange,
                          icon: const Icon(Icons.date_range_outlined, size: 15),
                          label: Text(
                            dateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(36),
                            textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      if (activeFilterCount > 0) ...[
                        const SizedBox(width: 5),
                        OutlinedButton.icon(
                          onPressed: _clearFinancialFilters,
                          icon: const Icon(
                            Icons.filter_alt_off_outlined,
                            size: 15,
                          ),
                          label: const Text('پاککردنەوە'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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

  Widget _buildFinancialHistoryLoadingState(bool isDark) {
    final error = _financialHistoryError;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
          if (error == null)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.3),
            )
          else
            const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 28),
          const SizedBox(height: 9),
          Text(
            error ?? 'بۆ گەڕان و فلتەری تەواو، مێژووی کۆنتر لە سێرڤەر بار دەکرێت...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 7),
            TextButton.icon(
              onPressed: _financialFilterHydrating
                  ? null
                  : () => unawaited(_hydrateFinancialHistoryForFilters()),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ],
        ],
      ),
    );
  }
}
