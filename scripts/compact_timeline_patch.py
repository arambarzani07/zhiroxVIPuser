from pathlib import Path

path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text()

start = text.index('  Widget _buildCustomerChatTimelineCard({')
end = text.index('  (String, Color) _debtHealth(', start)
text = text[:start] + r'''  Widget _buildCustomerChatTimelineCard({
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timelineItems = _buildTimelineItems();
    final health = _debtHealth(totalRemaining, totalDebt);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
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
                        'مامەڵەکان',
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
                        '${timelineItems.length} تۆمار',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF98A2B3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDebtHealthStrip(
              label: health.$1,
              color: health.$2,
              totalRemaining: totalRemaining,
              totalPaid: totalPaid,
            ),
            const SizedBox(height: 10),
            if (timelineItems.isEmpty)
              _buildEmptyTimelineState(isDark)
            else
              ...timelineItems.asMap().entries.map(
                    (entry) => _buildTimelineBubble(entry.value, entry.key),
                  ),
          ],
        ),
      ),
    );
  }

''' + text[end:]

start = text.index('  Widget _buildDebtHealthStrip({')
end = text.index('  Widget _buildEmptyTimelineState(', start)
text = text[:start] + r'''  Widget _buildDebtHealthStrip({
    required String label,
    required Color color,
    required double totalRemaining,
    required double totalPaid,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'ماوە ${AppHelpers.formatCurrency(totalRemaining)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : const Color(0xFF667085),
            ),
          ),
        ],
      ),
    );
  }

''' + text[end:]

start = text.index('  Widget _buildEmptyTimelineState(bool isDark) {')
end = text.index('  Widget _buildTimelineBubble(', start)
text = text[:start] + r'''  Widget _buildEmptyTimelineState(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
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

''' + text[end:]

start = text.index('  Widget _buildTimelineBubble(_ProfileTimelineItem item, int index) {')
end = text.index('  Future<void> _generateAccountStatement({', start)
text = text[:start] + r'''  Widget _buildTimelineBubble(_ProfileTimelineItem item, int index) {
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
        ? record.getStringValue('note')
        : record.getStringValue('description');
    final status = isPayment ? '' : record.getStringValue('status');
    final title = isPayment ? 'پارەدانەوە' : 'قەرز';
    final color = isPayment ? Colors.green : Colors.orange;
    final icon = isPayment
        ? Icons.south_west_rounded
        : Icons.north_east_rounded;
    final formattedAmount = AppHelpers.formatCurrencyWithType(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: currency == 'USD',
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 180 + (index * 20).clamp(0, 220)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 6 * (1 - value)),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.card : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : const Color(0xFFE9EDF3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : const Color(0xFF1D2939),
                        ),
                      ),
                      if (!isPayment && status.isNotEmpty) ...[
                        const SizedBox(width: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.09),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            AppHelpers.statusName(status),
                            style: TextStyle(
                              color: color,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppHelpers.formatDateTime(item.date.toIso8601String()),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : const Color(0xFF98A2B3),
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 122),
              child: Text(
                formattedAmount,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: color,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                ),
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
      ),
    );
  }

''' + text[end:]

path.write_text(text)
