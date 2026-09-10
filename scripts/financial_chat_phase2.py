from pathlib import Path

path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text()

# Debt detail is the canonical drill-down for both debt and payment bubbles.
anchor = "import 'package:zhirox/screens/shared/add_debt_screen.dart';\n"
imp = "import 'package:zhirox/screens/shared/debt_detail_screen.dart';\n"
if imp not in text:
    if anchor not in text:
        raise SystemExit('add debt import anchor not found')
    text = text.replace(anchor, anchor + imp, 1)

# Make the financial chat tab explicit without changing the three-section IA.
text = text.replace(
    "const labels = ['پوختە', 'مامەڵەکان', 'دەستکاری'];",
    "const labels = ['پوختە', 'چاتی دارایی', 'دەستکاری'];",
    1,
)

# Add a true fixed financial-action composer to the customer transaction tab.
scaffold_anchor = """      body: CustomScrollView(
        slivers: [
"""
scaffold_replacement = """      body: CustomScrollView(
        slivers: [
"""
# We inject bottomNavigationBar immediately before the closing Scaffold body block marker.
body_tail = """          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // ── Customer Body ──
"""
body_tail_new = """          const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
        ],
      ),
      bottomNavigationBar: _isCustomer &&
              _customerSection == 1 &&
              auth.userRole != 'customer'
          ? _buildFinancialChatComposer(auth, isDark)
          : null,
    );
  }

  // ═══════════════════════════════════════════
  // ── Customer Body ──
"""
if body_tail in text:
    text = text.replace(body_tail, body_tail_new, 1)
elif "_buildFinancialChatComposer(auth, isDark)" not in text:
    raise SystemExit('profile Scaffold tail not found')

start = text.find("  Widget _buildCustomerChatTimelineCard({")
end = text.find("  (String, Color) _debtHealth(", start)
if start < 0 or end < 0:
    raise SystemExit('chat card method boundaries not found')

chat_card = r'''  Widget _buildCustomerChatTimelineCard({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timelineItems = _buildTimelineItems();
    final health = _debtHealth(totalRemaining, totalDebt);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(18),
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
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.forum_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'چاتی دارایی',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${timelineItems.length} مامەڵە • قەرز و پارەدانەوە لە یەک مێژوودا',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
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
                        onPressed: _loadInFlight ? null : _loadData,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildChatSummaryValue(
                        label: 'قەرز',
                        value: totalDebt,
                        color: Colors.orange,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 7),
                      _buildChatSummaryValue(
                        label: 'دراوە',
                        value: totalPaid,
                        color: Colors.green,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 7),
                      _buildChatSummaryValue(
                        label: 'ماوە',
                        value: totalRemaining,
                        color: totalRemaining > 0 ? Colors.red : Colors.green,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            _buildDebtHealthStrip(
              label: health.$1,
              color: health.$2,
              totalRemaining: totalRemaining,
              totalPaid: totalPaid,
            ),
            const SizedBox(height: 12),
            if (timelineItems.isEmpty)
              _buildEmptyTimelineState(isDark)
            else
              ..._buildFinancialChatMessages(timelineItems),
            const SizedBox(height: 8),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.10 : 0.07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark
                    ? AppDarkColors.textSecondary
                    : const Color(0xFF667085),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              AppHelpers.formatCurrency(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFinancialChatMessages(
    List<_ProfileTimelineItem> timelineItems,
  ) {
    final widgets = <Widget>[];
    DateTime? previousDay;

    for (var index = 0; index < timelineItems.length; index++) {
      final item = timelineItems[index];
      final day = DateTime(item.date.year, item.date.month, item.date.day);
      if (previousDay == null || day != previousDay) {
        widgets.add(_buildChatDaySeparator(item.date));
        previousDay = day;
      }
      widgets.add(_buildTimelineBubble(item, index));
    }
    return widgets;
  }

  Widget _buildChatDaySeparator(DateTime date) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
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
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              AppHelpers.formatDate(date.toIso8601String()),
              style: TextStyle(
                fontSize: 10.5,
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

  Widget _buildFinancialChatComposer(AuthProvider auth, bool isDark) {
    final totalRemaining = _debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
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
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openAddDebtFromChat(),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('قەرز زیاد بکە'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: totalRemaining > 0
                    ? () => _showFinancialPaymentSheet(auth)
                    : null,
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('پارەدانەوە'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: Colors.green.shade700,
                  side: BorderSide(
                    color: totalRemaining > 0
                        ? Colors.green.withValues(alpha: 0.32)
                        : const Color(0xFFD0D5DD),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
              ),
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
        builder: (_) => AddDebtScreen(customerId: widget.userId),
      ),
    );
    if (result == true && mounted) {
      await _loadData();
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
    if (mounted) await _loadData();
  }

  Future<void> _showFinancialPaymentSheet(AuthProvider auth) async {
    final openDebts = _debts
        .where((debt) => debt.getDoubleValue('remaining') > 0)
        .toList()
      ..sort((a, b) => _timelineDate(a).compareTo(_timelineDate(b)));
    if (openDebts.isEmpty) {
      AppHelpers.showSnackBar(context, 'هیچ قەرزێکی ماوە نییە');
      return;
    }

    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var selectedDebtId = openDebts.first.id;
    var saving = false;
    String? localError;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final sheetDark =
                  Theme.of(sheetContext).brightness == Brightness.dark;
              final selectedDebt = openDebts.firstWhere(
                (debt) => debt.id == selectedDebtId,
                orElse: () => openDebts.first,
              );
              final remaining = selectedDebt.getDoubleValue('remaining');
              return Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                decoration: BoxDecoration(
                  color: sheetDark ? AppDarkColors.card : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD0D5DD),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'تۆمارکردنی پارەدانەوە',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'قەرز هەڵبژێرە و بڕی پارەدانەوە بنووسە.',
                        style: TextStyle(
                          fontSize: 12,
                          color: sheetDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF667085),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedDebtId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'قەرز',
                          border: OutlineInputBorder(),
                        ),
                        items: openDebts.map((debt) {
                          final description =
                              debt.getStringValue('description').trim();
                          final balance = debt.getDoubleValue('remaining');
                          return DropdownMenuItem<String>(
                            value: debt.id,
                            child: Text(
                              description.isEmpty
                                  ? 'ماوە: ${AppHelpers.formatCurrency(balance)}'
                                  : '$description • ${AppHelpers.formatCurrency(balance)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value == null) return;
                                setSheetState(() {
                                  selectedDebtId = value;
                                  localError = null;
                                });
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        enabled: !saving,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'بڕی پارەدانەوە',
                          helperText:
                              'ماوە: ${AppHelpers.formatCurrency(remaining)}',
                          prefixIcon: const Icon(Icons.payments_outlined),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        enabled: !saving,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'تێبینی (ئارەزوومەندانە)',
                          prefixIcon: Icon(Icons.notes_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          localError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                final normalized = amountController.text
                                    .trim()
                                    .replaceAll(',', '');
                                final amount = double.tryParse(normalized) ?? 0;
                                if (amount <= 0) {
                                  setSheetState(() => localError =
                                      'بڕێکی دروستی پارەدانەوە بنووسە.');
                                  return;
                                }
                                if (amount > remaining) {
                                  setSheetState(() => localError =
                                      'بڕی پارەدانەوە نابێت لە ماوەی قەرز زیاتر بێت.');
                                  return;
                                }

                                setSheetState(() {
                                  saving = true;
                                  localError = null;
                                });
                                try {
                                  await PBService.createPayment(
                                    debtId: selectedDebtId,
                                    amount: amount,
                                    note: noteController.text.trim(),
                                    createdBy: auth.userId,
                                    createdByName: auth.userName,
                                  );
                                  if (!sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                  if (!mounted) return;
                                  AppHelpers.showSnackBar(
                                    context,
                                    'پارەدانەوە بە سەرکەوتوویی تۆمارکرا',
                                  );
                                  await _loadData();
                                } catch (e) {
                                  if (!sheetContext.mounted) return;
                                  setSheetState(() {
                                    saving = false;
                                    localError = AppHelpers.backendErrorMessage(
                                      e,
                                      fallback:
                                          'پارەدانەوە تۆمار نەکرا. دووبارە هەوڵ بدە.',
                                    );
                                  });
                                }
                              },
                        icon: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(saving ? 'تۆمار دەکرێت...' : 'تۆمارکردن'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.green.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      amountController.dispose();
      noteController.dispose();
    }
  }

'''
text = text[:start] + chat_card + text[end:]

bubble_start = text.find("  Widget _buildTimelineBubble(")
bubble_end = text.find("  Future<void> _generateAccountStatement(", bubble_start)
if bubble_start < 0 or bubble_end < 0:
    raise SystemExit('timeline bubble method boundaries not found')

bubble = r'''  Widget _buildTimelineBubble(_ProfileTimelineItem item, int index) {
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
    final formattedAmount = AppHelpers.formatCurrencyWithType(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: currency == 'USD',
    );
    final receiptPath = isPayment ? '' : record.getStringValue('receipt_image');

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
            maxWidth: MediaQuery.sizeOf(context).width * 0.80,
            minWidth: 180,
          ),
          child: Material(
            color: background,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(17),
              topRight: const Radius.circular(17),
              bottomLeft: Radius.circular(isPayment ? 5 : 17),
              bottomRight: Radius.circular(isPayment ? 17 : 5),
            ),
            child: InkWell(
              onTap: () => _openTimelineItem(item),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(17),
                topRight: const Radius.circular(17),
                bottomLeft: Radius.circular(isPayment ? 5 : 17),
                bottomRight: Radius.circular(isPayment ? 17 : 5),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
                decoration: BoxDecoration(
                  border: Border.all(color: color.withValues(alpha: 0.16)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(17),
                    topRight: const Radius.circular(17),
                    bottomLeft: Radius.circular(isPayment ? 5 : 17),
                    bottomRight: Radius.circular(isPayment ? 17 : 5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isPayment
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            size: 15,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isPayment ? 'پارەدانەوە' : 'قەرز',
                            style: TextStyle(
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF1D2939),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!isPayment && status.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              AppHelpers.statusName(status),
                              style: TextStyle(
                                color: color,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${isPayment ? '−' : '+'} $formattedAmount',
                      textDirection: TextDirection.ltr,
                      textAlign: isPayment ? TextAlign.left : TextAlign.right,
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF475467),
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
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
                            'وەصڵ',
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

'''
text = text[:bubble_start] + bubble + text[bubble_end:]

# Durable source-level markers so accidental regression is obvious in review.
required = [
    "'چاتی دارایی'",
    '_buildFinancialChatComposer',
    '_showFinancialPaymentSheet',
    'Alignment.centerLeft',
    'Alignment.centerRight',
    'DebtDetailScreen(debtId: debtId)',
]
for marker in required:
    if marker not in text:
        raise SystemExit(f'missing Financial Chat marker: {marker}')

path.write_text(text)
