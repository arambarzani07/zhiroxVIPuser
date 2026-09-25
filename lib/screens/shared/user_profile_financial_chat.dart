part of 'user_profile_screen.dart';

extension _UserProfileFinancialChat on _UserProfileScreenState {
  Widget _buildCustomerChatTimelineCard({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allTimelineItems = _buildTimelineItems();
    final timelineItems = _filterFinancialTimeline(allTimelineItems);
    final selectedRange = _financialDateRange;
    final rangeSummary = selectedRange == null
        ? null
        : summarizeFinancialDateRange(
            entries: allTimelineItems.map(
              (item) => FinancialRangeEntry(
                kind: item.kind,
                amount: item.isSystem
                    ? 0
                    : (_timelineAmountInIqd(item) ?? double.nan),
                date: item.date,
              ),
            ),
            start: selectedRange.start,
            end: selectedRange.end,
          );
    // A partial newest-page window has no trustworthy opening ledger balance.
    // Hide per-row running balances until the complete history is hydrated.
    final runningBalances = _financialTimelineHasMore
        ? const <String, double?>{}
        : _financialRunningBalances(allTimelineItems);
    final hasFilters = _hasFinancialFilters;
    final waitingForFullFilterHistory = hasFilters &&
        (_financialTimelineHasMore || _financialFilterHydrating);
    final renderEntries = _buildFinancialChatRenderEntries(
      waitingForFullFilterHistory
          ? const <_ProfileTimelineItem>[]
          : timelineItems,
    );
    final totalsComplete = _financeSummaryComplete;
    final health = _debtHealth(totalRemaining, totalDebt);

    Widget buildHeader() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE7ECF3),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.forum_outlined,
                          color: AppColors.primary,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'چاتی دارایی',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              _financialTimelineHasMore && !hasFilters
                                  ? '${allTimelineItems.length}+ مامەڵەی نوێ بارکراوە • مێژووی کۆنتر هەیە'
                                  : '${timelineItems.length}/${allTimelineItems.length} مامەڵە • قەرز و پارە وەرگرتنەوە لە یەک مێژوودا',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9.75,
                                color: isDark
                                    ? AppDarkColors.textSecondary
                                    : const Color(0xFF98A2B3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'نوێکردنەوە',
                        onPressed: _financialRefreshInFlight
                            ? null
                            : () => _refreshFinancialData(showError: true),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildCompactFinancialOverview(
                    totalDebt: totalDebt,
                    totalPaid: totalPaid,
                    totalRemaining: totalRemaining,
                    totalsComplete: totalsComplete,
                    healthLabel: health.$1,
                    healthColor: health.$2,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildFinancialChatTools(
                    totalDebt: totalDebt,
                    totalRemaining: totalRemaining,
                    totalPaid: totalPaid,
                  ),
                  if (rangeSummary != null &&
                      !waitingForFullFilterHistory) ...[
                    const SizedBox(height: 7),
                    _buildFinancialRangeSummary(rangeSummary, isDark),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (!totalsComplete) _buildCurrencySummaryWarning(compact: true),
            const SizedBox(height: 8),
            if (!hasFilters && _financialTimelineHasMore) ...[
              OutlinedButton.icon(
                onPressed: _financialHistoryLoading
                    ? null
                    : () => _loadOlderFinancialHistory(),
                icon: _financialHistoryLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history_rounded, size: 18),
                label: Text(
                  _financialHistoryLoading
                      ? 'بارکردنی مامەڵە کۆنەکان...'
                      : 'مامەڵە کۆنەکان باربکە',
                ),
              ),
              const SizedBox(height: 7),
            ],
            if (waitingForFullFilterHistory)
              _buildFinancialHistoryLoadingState(isDark)
            else if (timelineItems.isEmpty)
              allTimelineItems.isEmpty
                  ? _buildEmptyTimelineState(isDark)
                  : _buildFilteredTimelineEmptyState(isDark),
          ],
        ),
      );
    }

    // One virtualized sliver owns both the Financial Chat header and the
    // timeline rows. Unlike spreading a List<Widget> into a Column, this only
    // builds message bubbles close to the viewport and keeps long histories
    // responsive without changing search/filter/realtime semantics.
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) return buildHeader();
          if (index == renderEntries.length + 1) {
            return const SizedBox(height: 5);
          }

          final entry = renderEntries[index - 1];
          final child = entry.isSeparator
              ? _buildChatDaySeparator(entry.separatorDate!)
              : entry.item!.isSystem
                  ? _buildFinancialSystemMessage(entry.item!)
                  : _buildTimelineBubble(
                      entry.item!,
                      entry.timelineIndex,
                      balanceAfter:
                          runningBalances[_timelineLedgerKey(entry.item!)],
                    );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: child,
          );
        },
        childCount: renderEntries.length + 2,
        addAutomaticKeepAlives: false,
      ),
    );
  }

  Widget _buildCompactFinancialOverview({
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
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.035)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
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
                        fontSize: 9.75,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      totalsComplete
                          ? AppHelpers.formatCurrency(totalRemaining)
                          : '—',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 16,
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
                  constraints: const BoxConstraints(maxWidth: 155),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
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
                        size: 12,
                        color: healthColor,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          healthLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
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
          const SizedBox(height: 6),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFE4E7EC),
          ),
          const SizedBox(height: 5),
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
                  label: 'پارە وەرگرتنەوە',
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
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 9.75,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialRangeSummary(
    FinancialRangeSummary summary,
    bool isDark,
  ) {
    final netColor = summary.net > 0 ? Colors.red : Colors.green;
    final closingColor =
        summary.closingBalance > 0 ? Colors.red : Colors.green;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.08 : 0.045),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.date_range_rounded,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 5),
              const Expanded(
                child: Text(
                  'پوختەی مەودای هەڵبژێردراو',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Text(
                '${summary.transactionCount} مامەڵە',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              _buildChatSummaryValue(
                label: 'باڵانسی سەرەتا',
                value: summary.openingBalance,
                color: AppColors.primary,
                isDark: isDark,
              ),
              const SizedBox(width: 5),
              _buildChatSummaryValue(
                label: 'باڵانسی کۆتایی',
                value: summary.closingBalance,
                color: closingColor,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildChatSummaryValue(
                label: 'قەرز پێدان',
                value: summary.debtTotal,
                color: Colors.orange,
                isDark: isDark,
              ),
              const SizedBox(width: 5),
              _buildChatSummaryValue(
                label: 'پارە وەرگرتنەوە',
                value: summary.paymentTotal,
                color: Colors.green,
                isDark: isDark,
              ),
              const SizedBox(width: 5),
              _buildChatSummaryValue(
                label: 'گۆڕانی خالص',
                value: summary.net,
                color: netColor,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${summary.debtCount} قەرز • ${summary.paymentCount} پارە وەرگرتنەوە',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF98A2B3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatSummaryValue({
    required String label,
    required double value,
    required Color color,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.isNaN ? '—' : AppHelpers.formatCurrency(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_FinancialChatRenderEntry> _buildFinancialChatRenderEntries(
    List<_ProfileTimelineItem> timelineItems,
  ) {
    final entries = <_FinancialChatRenderEntry>[];
    DateTime? previousDay;

    for (var index = 0; index < timelineItems.length; index++) {
      final item = timelineItems[index];
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      if (previousDay == null || day != previousDay) {
        entries.add(_FinancialChatRenderEntry.separator(item.date, index));
        previousDay = day;
      }
      entries.add(_FinancialChatRenderEntry.item(item, index));
    }
    return entries;
  }

  Widget _buildChatDaySeparator(DateTime date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE4E7EC),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              AppHelpers.formatDate(date.toIso8601String()),
              style: TextStyle(
                fontSize: 9.75,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF98A2B3),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE4E7EC),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSystemMessage(_ProfileTimelineItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final record = item.record;
    final type = record.getStringValue('event_type');
    final actor = record.getStringValue('actor_name').trim();
    final amount = record.getDoubleValue('amount');
    // Audit events store the canonical amount but do not snapshot dollar_rate.
    // Never relabel that known IQD value as USD without a safe conversion rate.
    final amountText = amount > 0 ? AppHelpers.formatCurrency(amount) : '';

    final (icon, message) = switch (type) {
      'debt_deleted' => (
          Icons.delete_outline_rounded,
          amountText.isEmpty ? 'قەرزێک سڕایەوە' : 'قەرزی $amountText سڕایەوە',
        ),
      'payment_updated' => (
          Icons.edit_note_rounded,
          'پارە وەرگرتنەوە دەستکاری کرا',
        ),
      'payment_deleted' => (
          Icons.remove_circle_outline_rounded,
          amountText.isEmpty
              ? 'پارە وەرگرتنەوەیەک سڕایەوە'
              : 'پارە وەرگرتنەوەی $amountText سڕایەوە',
        ),
      _ => (Icons.edit_outlined, 'قەرز دەستکاری کرا'),
    };

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.055)
              : const Color(0xFFF2F4F7),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                actor.isEmpty ? message : '$message • $actor',
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.75,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              DateFormat('HH:mm').format(item.date),
              style: TextStyle(
                fontSize: 9,
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF98A2B3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialChatComposer(AuthProvider auth, bool isDark) {
    final hasOutstandingDebt = _openDebts.isNotEmpty;
    final replyTarget = _financialReplyTarget;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFE4E7EC),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTarget != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 5, 5, 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.07),
                  borderRadius: BorderRadius.circular(9),
                  border: Border(
                    right: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.65),
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, size: 15, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'پەیوەست بە مامەڵەی پێشوو',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            _financialReplyLabel(replyTarget),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF475467),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'لابردنی پەیوەندی',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setProfileState(() => _financialReplyTarget = null),
                      icon: const Icon(Icons.close_rounded, size: 16),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openAddDebtFromChat,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('قەرز زیاد بکە'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasOutstandingDebt
                        ? () => _showFinancialPaymentSheet(auth)
                        : null,
                    icon: const Icon(Icons.payments_outlined, size: 16),
                    label: const Text('پارە وەرگرتنەوە'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(
                        color: hasOutstandingDebt
                            ? Colors.green.withValues(alpha: 0.32)
                            : const Color(0xFFD0D5DD),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddDebtFromChat() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddDebtScreen(
          customerId: widget.userId,
          referenceKind: _financialReplyTarget == null
              ? null
              : (_financialReplyTarget!.isPayment ? 'payment' : 'debt'),
          referenceId: _financialReplyTarget?.record.id,
        ),
      ),
    );
    if (result == true && mounted) {
      if (mounted && _financialReplyTarget != null) {
        _setProfileState(() => _financialReplyTarget = null);
      }
      await _refreshFinancialData(autoJump: true);
    }
  }

  Future<void> _openTimelineItem(_ProfileTimelineItem item) async {
    final debtId = item.isPayment
        ? item.record.getStringValue('debt')
        : item.record.id;
    if (debtId.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debtId)),
    );
    if (mounted) await _refreshFinancialData();
  }

  Future<void> _deleteFinancialPayment(
    _ProfileTimelineItem item,
  ) async {
    if (!item.isPayment || !mounted) return;
    final isGeneral = item.isGeneralPayment;
    final amount = item.record.getDoubleValue('amount');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isGeneral
              ? 'پارەدانەوەی گشتی بسڕدرێتەوە؟'
              : 'پارە وەرگرتنەوە بسڕدرێتەوە؟',
        ),
        content: Text(
          '${AppHelpers.formatCurrency(amount)} دەسڕدرێتەوە و باڵانسی کڕیار لە سێرڤەرەوە دووبارە هەژمار دەکرێتەوە. ئەم کردارە لە Audit Log تۆمار دەبێت.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('سڕینەوە'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      if (isGeneral) {
        await PBService.deleteGeneralPayment(item.record.id);
      } else {
        await PBService.deletePayment(item.record.id);
      }
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        isGeneral
            ? 'پارەدانەوەی گشتی سڕایەوە و باڵانس نوێ کرایەوە'
            : 'پارە وەرگرتنەوە سڕایەوە و باڵانس نوێ کرایەوە',
      );
      await _refreshFinancialData(showError: true);
    } catch (error) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          error,
          fallback: 'سڕینەوەی پارەدانەوە سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _showFinancialPaymentSheet(
    AuthProvider auth, {
    String? initialDebtId,
    double? initialAmount,
  }) async {
    final replyTarget = _financialReplyTarget;
    final saved = await FinancialPaymentFlow.show(
      context: context,
      debts: _openDebts,
      createdBy: auth.userId,
      createdByName: auth.userName,
      initialDebtId: initialDebtId,
      initialStorageAmount: initialAmount,
      customerWideOnly: initialDebtId == null,
      referenceKind: initialDebtId == null || replyTarget == null
          ? null
          : (replyTarget.isPayment ? 'payment' : 'debt'),
      referenceId: initialDebtId == null ? null : replyTarget?.record.id,
    );
    if (!mounted || !saved) return;
    if (_financialReplyTarget != null) {
      _setProfileState(() => _financialReplyTarget = null);
    }
    await _refreshFinancialData(autoJump: true);
  }

  (String, Color) _debtHealth(double totalRemaining, double totalDebt) {
    final debtLimit = _user?.getDoubleValue('debt_limit') ?? 0;
    if (totalRemaining <= 0) return ('باش — هیچ قەرزێکی ماوە نییە', Colors.green);
    if (debtLimit > 0 && totalRemaining > debtLimit) {
      return ('مەترسیدار — سنووری قەرز تێپەڕیوە', Colors.red);
    }
    final ratio = totalDebt <= 0 ? 0.0 : totalRemaining / totalDebt;
    if (ratio >= 0.75) return ('ئاگاداری — پارە وەرگرتنەوە کەمە', Colors.orange);
    if (ratio >= 0.35) return ('مامناوەند — پێویستی بە چاودێرییە', Colors.blue);
    return ('باش — پارە وەرگرتنەوە ڕێکوپێکە', Colors.green);
  }

  Widget _buildEmptyTimelineState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
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
            Icons.receipt_long_outlined,
            color: isDark ? AppDarkColors.textSecondary : Colors.grey[400],
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            'هێشتا هیچ مامەڵەیەک نییە',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDark ? AppDarkColors.textPrimary : const Color(0xFF344054),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineBubble(
    _ProfileTimelineItem item,
    int index, {
    double? balanceAfter,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPayment = item.isPayment;
    final record = item.record;
    final relatedDebt = item.relatedDebt;
    final amount = record.getDoubleValue('amount');
    final currency = isPayment
        ? (relatedDebt?.getStringValue('currency').isNotEmpty == true
            ? relatedDebt!.getStringValue('currency')
            : 'IQD')
        : record.getStringValue('currency').isNotEmpty
            ? record.getStringValue('currency')
            : 'IQD';
    final dollarRate = isPayment
        ? (relatedDebt?.getDoubleValue('dollar_rate') ?? 0)
        : record.getDoubleValue('dollar_rate');
    final description = isPayment
        ? record.getStringValue('note').trim()
        : record.getStringValue('description').trim();
    final status = isPayment ? '' : record.getStringValue('status');
    final color = isPayment ? Colors.green.shade700 : Colors.orange.shade800;
    final background = color.withValues(alpha: isDark ? 0.16 : 0.09);
    final formattedAmount = AppHelpers.formatStoredFinancialAmount(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: currency == 'USD',
    );
    final receiptPath = isPayment ? '' : record.getStringValue('receipt_image');
    final overdueLabel = isPayment ? null : _overdueDebtLabel(record);
    final auth = context.read<AuthProvider>();
    final canQuickPay = !isPayment &&
        auth.userRole != 'customer' &&
        record.getDoubleValue('remaining') > 0;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 160 + (index * 18).clamp(0, 220)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset((isPayment ? -8 : 8) * (1 - value), 0),
          child: child,
        ),
      ),
      child: Align(
        alignment: isPayment ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            minWidth: 180,
          ),
          child: Material(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(15),
              topRight: const Radius.circular(15),
              bottomLeft: Radius.circular(isPayment ? 4 : 15),
              bottomRight: Radius.circular(isPayment ? 15 : 4),
            ),
            child: InkWell(
              onTap: () => _showFinancialTransactionActions(item),
              onLongPress: () => _showFinancialTransactionActions(item),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(15),
                topRight: const Radius.circular(15),
                bottomLeft: Radius.circular(isPayment ? 4 : 15),
                bottomRight: Radius.circular(isPayment ? 15 : 4),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
                decoration: BoxDecoration(
                  border: Border.all(color: color.withValues(alpha: 0.16)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(15),
                    topRight: const Radius.circular(15),
                    bottomLeft: Radius.circular(isPayment ? 4 : 15),
                    bottomRight: Radius.circular(isPayment ? 15 : 4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPayment
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            size: 13,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.isGeneralPayment
                                ? 'پارەدانەوەی گشتی'
                                : isPayment
                                    ? 'پارە وەرگرتنەوەی مامەڵە'
                                    : 'قەرز',
                            style: TextStyle(
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF1D2939),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!isPayment && status.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppHelpers.statusName(status),
                              style: TextStyle(
                                color: color,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isPayment ? '−' : '+'} $formattedAmount',
                      textDirection: TextDirection.ltr,
                      textAlign: isPayment ? TextAlign.left : TextAlign.right,
                      style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF475467),
                          fontSize: 10.5,
                          height: 1.30,
                        ),
                      ),
                    ],
                    if (!item.isGeneralPayment &&
                        _financialReferenceSnapshot(record) != null) ...[
                      const SizedBox(height: 7),
                      _buildPersistentFinancialReference(record, color, isDark),
                    ],
                    if (isPayment &&
                        !item.isGeneralPayment &&
                        relatedDebt != null) ...[
                      const SizedBox(height: 7),
                      _buildPaymentDebtReference(relatedDebt, color, isDark),
                    ],
                    if (!isPayment && receiptPath.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      _buildReceiptPreview(record, receiptPath, color, isDark),
                    ],
                    if (overdueLabel != null) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: isDark ? 0.14 : 0.08),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              overdueLabel,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (balanceAfter != null) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.10)
                              : Colors.white.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'ماوەی هەژمار',
                              style: TextStyle(
                                color: isDark
                                    ? AppDarkColors.textSecondary
                                    : const Color(0xFF667085),
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              AppHelpers.formatCurrency(balanceAfter),
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                color: balanceAfter > 0
                                    ? Colors.red.shade700
                                    : Colors.green.shade700,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (canQuickPay) ...[
                      const SizedBox(height: 2),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => unawaited(
                            _showFinancialPaymentSheet(
                              auth,
                              initialDebtId: record.id,
                              initialAmount: record.getDoubleValue('remaining'),
                            ),
                          ),
                          icon: const Icon(Icons.payments_outlined, size: 14),
                          label: const Text('پارە وەرگرتنەوەی تەواو'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green.shade700,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (receiptPath.isNotEmpty) ...[
                          Icon(
                            Icons.receipt_outlined,
                            size: 13,
                            color: color.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'وەسڵ',
                            style: TextStyle(
                              color: color,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          DateFormat('HH:mm').format(item.date),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF98A2B3),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentDebtReference(
    RecordModel debt,
    Color accent,
    bool isDark,
  ) {
    final description = debt.getStringValue('description').trim();
    final currency = debt.getStringValue('currency').isEmpty
        ? 'IQD'
        : debt.getStringValue('currency');
    final amount = debt.getDoubleValue('amount');
    final amountText = AppHelpers.formatStoredFinancialAmount(
      amount,
      currency,
      dollarRate: debt.getDoubleValue('dollar_rate'),
      showConversion: currency == 'USD',
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(7),
        border: BorderDirectional(
          start: BorderSide(color: accent, width: 2.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.reply_rounded, size: 12, color: accent),
          const SizedBox(width: 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'پەیوەست بە قەرز',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description.isEmpty ? amountText : '$description • $amountText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 9.5,
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

  Map<String, dynamic>? _financialReferenceSnapshot(RecordModel record) {
    final raw = record.toJson()['reference_snapshot'];
    if (raw is Map && raw.isNotEmpty) {
      return Map<String, dynamic>.from(raw);
    }
    return null;
  }

  String _financialReplyLabel(_ProfileTimelineItem item) {
    final isPayment = item.isPayment;
    final record = item.record;
    final amount = record.getDoubleValue('amount');
    final relatedCurrency = item.relatedDebt?.getStringValue('currency') ?? '';
    final ownCurrency = record.getStringValue('currency');
    final currency = (isPayment ? relatedCurrency : ownCurrency).trim().isEmpty
        ? 'IQD'
        : (isPayment ? relatedCurrency : ownCurrency);
    final text = (isPayment
            ? record.getStringValue('note')
            : record.getStringValue('description'))
        .trim();
    final dollarRate = isPayment
        ? (item.relatedDebt?.getDoubleValue('dollar_rate') ?? 0)
        : record.getDoubleValue('dollar_rate');
    final amountText = AppHelpers.formatStoredFinancialAmount(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: currency == 'USD',
    );
    final prefix = item.isGeneralPayment
        ? 'پارەدانەوەی گشتی'
        : isPayment
            ? 'پارە وەرگرتنەوەی مامەڵە'
            : 'قەرز';
    return text.isEmpty ? '$prefix • $amountText' : '$prefix • $amountText • $text';
  }

  Widget _buildPersistentFinancialReference(
    RecordModel record,
    Color accent,
    bool isDark,
  ) {
    final snapshot = _financialReferenceSnapshot(record);
    if (snapshot == null) return const SizedBox.shrink();

    final kind = snapshot['kind']?.toString() ?? '';
    final amount = double.tryParse('${snapshot['amount'] ?? 0}') ?? 0;
    final currency = (snapshot['currency']?.toString() ?? '').trim().isEmpty
        ? 'IQD'
        : snapshot['currency'].toString();
    final text = snapshot['text']?.toString().trim() ?? '';
    final dollarRate =
        double.tryParse('${snapshot['dollar_rate'] ?? 0}') ?? 0;
    final label = kind == 'payment' ? 'وەڵام بۆ پارە وەرگرتنەوە' : 'وەڵام بۆ قەرز';
    final amountText = AppHelpers.formatStoredFinancialAmount(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: currency == 'USD',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(7),
        border: Border(
          right: BorderSide(color: accent.withValues(alpha: 0.72), width: 2.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, size: 12, color: accent),
          const SizedBox(width: 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  text.isEmpty ? amountText : '$amountText • $text',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF475467),
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
    final imageUrl = FinancialDocumentActions.receiptUrl(
        debt,
        receiptPath: receiptPath,
      );
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 64,
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
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.8),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) => Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, size: 15, color: accent),
                    const SizedBox(width: 3),
                    Text(
                      'وێنەی وەسڵ بەردەست نییە',
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            PositionedDirectional(
              end: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 11, color: Colors.white),
                    SizedBox(width: 3),
                    Text(
                      'وەسڵ',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
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

  Future<void> _showFinancialTransactionActions(
    _ProfileTimelineItem item,
  ) async {
    if (item.isSystem || !mounted) return;

    // A general repayment is a customer-ledger entry, not a debt
    // transaction. Even legacy rows must not expose debt actions/references.
    final debt = item.isGeneralPayment
        ? null
        : (item.isPayment ? item.relatedDebt : item.record);
    final receiptPath = debt?.getStringValue('receipt_image').trim() ?? '';
    final auth = context.read<AuthProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final amount = item.record.getDoubleValue('amount');
        final currency = debt?.getStringValue('currency').isNotEmpty == true
            ? debt!.getStringValue('currency')
            : 'IQD';
        final dollarRate = debt?.getDoubleValue('dollar_rate') ?? 0;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 7),
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                leading: CircleAvatar(
                  backgroundColor: (item.isPayment ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.10),
                  child: Icon(
                    item.isPayment
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: item.isPayment ? Colors.green.shade700 : Colors.orange.shade800,
                    size: 17,
                  ),
                ),
                title: Text(
                  item.isGeneralPayment
                      ? 'پارەدانەوەی گشتی'
                      : item.isPayment
                          ? 'پارە وەرگرتنەوەی مامەڵە'
                          : 'قەرز',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  AppHelpers.formatStoredFinancialAmount(
                    amount,
                    currency,
                    dollarRate: dollarRate,
                    showConversion: currency == 'USD',
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const Divider(height: 8),
              if (debt != null)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.open_in_new_rounded, size: 19),
                  title: const Text(
                    'وردەکاری مامەڵە',
                    style: TextStyle(fontSize: 13),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'details'),
                ),
              if (auth.userRole != 'customer' && debt != null)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.reply_rounded, size: 19),
                  title: const Text('وەک وەڵام / پەیوەستکردن', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('مامەڵەی نوێ بە ئەم مامەڵەیەوە ببەستە', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheetContext, 'reference'),
                ),
              if (auth.userRole != 'customer' &&
                  debt != null &&
                  debt.getDoubleValue('remaining') > 0)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(
                    Icons.done_all_rounded,
                    size: 19,
                    color: Colors.green.shade700,
                  ),
                  title: const Text('پارە وەرگرتنەوەی تەواوی ماوە', style: TextStyle(fontSize: 13)),
                  subtitle: Text(
                    AppHelpers.formatStoredFinancialAmount(
                      debt.getDoubleValue('remaining'),
                      currency,
                      dollarRate: dollarRate,
                      showConversion: currency == 'USD',
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'pay_full'),
                ),
              if (auth.userRole == 'admin' && item.isPayment)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    size: 19,
                    color: Colors.red,
                  ),
                  title: Text(
                    item.isGeneralPayment
                        ? 'سڕینەوەی پارەدانەوەی گشتی'
                        : 'سڕینەوەی پارە وەرگرتنەوە',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'باڵانسی کڕیار دووبارە هەژمار دەکرێتەوە',
                    style: TextStyle(fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'delete_payment'),
                ),
              if (receiptPath.isNotEmpty)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.image_outlined, size: 19),
                  title: const Text('بینینی وەسڵ', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('گەورەکردن و جوڵاندنی وێنە', style: TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(sheetContext, 'receipt'),
                ),
              if (debt != null)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: const Icon(Icons.print_outlined, size: 19),
                  title: const Text('چاپکردنی وەسڵ', style: TextStyle(fontSize: 13)),
                  onTap: () => Navigator.pop(sheetContext, 'invoice'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'reference':
        if (mounted) {
          _setProfileState(() => _financialReplyTarget = item);
          _jumpToLatest();
        }
        break;
      case 'details':
        await _openTimelineItem(item);
        break;
      case 'pay_full':
        if (debt != null && debt.getDoubleValue('remaining') > 0) {
          await _showFinancialPaymentSheet(
            auth,
            initialDebtId: debt.id,
            initialAmount: debt.getDoubleValue('remaining'),
          );
        }
        break;
      case 'delete_payment':
        await _deleteFinancialPayment(item);
        break;
      case 'receipt':
        if (debt != null && receiptPath.isNotEmpty) {
          await FinancialDocumentActions.openReceiptViewer(
            context,
            debt,
            receiptPath: receiptPath,
          );
        }
        break;
      case 'invoice':
        if (debt != null) {
          await FinancialDocumentActions.generateDebtInvoice(context, debt);
        }
        break;
    }
  }

  Future<void> _generateFilteredFinancialChatStatement() async {
    final hydrated = await _ensureAllFinancialHistoryLoaded(showError: true);
    if (!hydrated || !mounted) return;
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
        'payment_updated' => 'پارە وەرگرتنەوە دەستکاری کرا',
        'payment_deleted' => 'پارە وەرگرتنەوە سڕایەوە',
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
      'payment' => 'پارە وەرگرتنەوە',
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

  Future<void> _openPeriodStatement() async {
    final auth = context.read<AuthProvider>();
    if (!auth.canViewDebts) {
      AppHelpers.showSnackBar(
        context,
        'دەسەڵاتی بینینی قەرزەکانت نییە.',
        isError: true,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerPeriodStatementScreen(
          customerId: widget.userId,
          customerName: _user?.getStringValue('name') ?? '',
          canExport: auth.canExportData,
        ),
      ),
    );
  }

  Future<void> _generateCurrentFinancialStatement() async {
    if (!_financeSummaryComplete) {
      _showIncompleteCurrencySummaryMessage();
      return;
    }
    try {
      final fullDebts = await PBService.getAllCustomerDebtsLive(widget.userId);
      if (!mounted) return;
      await _generateAccountStatement(
        debts: fullDebts,
        totalDebt: _financeTotalDebtIqd,
        totalRemaining: _financeTotalRemainingIqd,
        totalPaid: _financeTotalPaidIqd,
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'کەشف حیساب دروست نەکرا. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }

  Future<void> _generateAccountStatement({
    required List<RecordModel> debts,
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) async {
    final auth = context.read<AuthProvider>();
    final customerName = _user?.getStringValue('name') ?? '';

    try {
      await PdfService.generateCustomerStatement(
        activeDebts: debts,
        customerName: customerName,
        marketName: auth.marketName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        totalDebt: totalDebt,
        totalRemaining: totalRemaining,
        totalPaid: totalPaid,
      );
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);
      }
    }
  }

  // ═══════════════════════════════════════════
  // ── Employee Body ──
  // ═══════════════════════════════════════════
}