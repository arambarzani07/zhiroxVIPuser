from pathlib import Path
import re

path = Path('lib/screens/shared/debt_detail_screen.dart')
text = path.read_text()

payments_header = r'''          // ───── Payments Header ─────.*?          // ───── Receipt Image ─────'''
new_payments_header = r'''          // ───── Compact Payments Header ─────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.payments_outlined,
                      size: 19,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.payments,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : const Color(0xFF1D2939),
                          ),
                        ),
                        Text(
                          '${_payments.length} تۆمار',
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
                  if (!isCustomer && status != 'paid')
                    TextButton.icon(
                      onPressed: _showAddPaymentDialog,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('پارەدانەوە'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: Colors.green.withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ───── Receipt Image ─────'''
text, n = re.subn(payments_header, new_payments_header, text, flags=re.S)
if n != 1:
    raise SystemExit(f'payments header replacement count={n}')

receipt_block = r'''          // ───── Receipt Image ─────.*?          // ───── Payment List ─────'''
new_receipt_block = r'''          // ───── Compact Receipt ─────
          ..._buildReceiptSliver(isDark),

          // ───── Payment List ─────'''
text, n = re.subn(receipt_block, new_receipt_block, text, flags=re.S)
if n != 1:
    raise SystemExit(f'receipt replacement count={n}')

# Compact the empty payments state without changing behavior.
text = text.replace(
'''              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 48,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 12),''',
'''              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 30,
                      color: Colors.grey[300],
                    ),
                    const SizedBox(height: 7),''')

items_and_payment = r'''  List<Widget> _buildItemsSliver\(\) \{.*?  Widget _buildPaymentCard\(RecordModel payment, int index\) \{.*?\n  \}\n\n  // ───── Actions ─────'''
new_methods = r'''  List<Widget> _buildItemsSliver() {
    if (_debt == null) return [];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      final rawItems = _debt!.data['items'];
      List itemsList = [];
      if (rawItems is String) {
        if (rawItems.isEmpty || rawItems == '[]') return [];
        itemsList = jsonDecode(rawItems);
      } else if (rawItems is List) {
        itemsList = rawItems;
      } else {
        return [];
      }
      if (itemsList.isEmpty) return [];

      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Container(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shopping_bag_outlined,
                          size: 17,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : const Color(0xFF667085),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'کاڵاکان',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF344054),
                            ),
                          ),
                        ),
                        Text(
                          '${itemsList.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : const Color(0xFF98A2B3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF0F2F5),
                  ),
                  ...itemsList.asMap().entries.map((entry) {
                    final item = entry.value;
                    final name = (item is Map ? item['name'] : '') ?? '';
                    final qty =
                        (item is Map ? item['quantity'] ?? item['qty'] : 1) ?? 1;
                    final price = (item is Map ? item['price'] : 0) ?? 0;
                    final itemCurrency =
                        (item is Map ? item['currency'] : null) ??
                            _debt!.getStringValue('currency');
                    final total = (price is num ? price.toDouble() : 0) *
                        (qty is num ? qty.toDouble() : 1);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        border: entry.key == itemsList.length - 1
                            ? null
                            : Border(
                                bottom: BorderSide(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : const Color(0xFFF4F5F7),
                                ),
                              ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              '$qty×',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              '$name',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF344054),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            AppHelpers.formatCurrencyWithType(
                              total,
                              itemCurrency,
                              dollarRate: _debt!.getDoubleValue('dollar_rate'),
                              showConversion: false,
                            ),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : const Color(0xFF667085),
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ];
    } catch (_) {
      return [];
    }
  }

  List<Widget> _buildReceiptSliver(bool isDark) {
    if (_debt == null || _debt!.getStringValue('receipt_image').isEmpty) {
      return [];
    }
    final imageUrl = PBService.pb
        .getFileUrl(_debt!, _debt!.getStringValue('receipt_image'))
        .toString();

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showReceiptPreview(imageUrl),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFE9EDF3),
                ),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      imageUrl,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        color: isDark
                            ? AppDarkColors.background
                            : const Color(0xFFF5F7FA),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'وێنەی وەصڵ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : const Color(0xFF344054),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'بۆ بینینی قەبارەی تەواو کلیک بکە',
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
                  Icon(
                    Icons.open_in_full_rounded,
                    size: 18,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  void _showReceiptPreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: InteractiveViewer(
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(RecordModel payment, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paymentAmount = payment.getDoubleValue('amount');
    final currency = _debt!.getStringValue('currency');
    final dollarRate = _debt!.getDoubleValue('dollar_rate');
    final note = payment.getStringValue('note');
    final created = payment.getStringValue('created');
    final displayAmount = AppHelpers.formatCurrencyWithType(
      (currency == 'USD' && dollarRate > 0)
          ? paymentAmount / dollarRate
          : paymentAmount,
      (currency == 'USD' && dollarRate > 0) ? 'USD' : 'IQD',
      dollarRate: dollarRate,
      showConversion: false,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFE9EDF3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.south_west_rounded,
              color: Colors.green,
              size: 17,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppHelpers.formatDateTime(created),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
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
          const SizedBox(width: 8),
          Text(
            displayAmount,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Colors.green,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }

  // ───── Actions ─────'''
text, n = re.subn(items_and_payment, new_methods, text, flags=re.S)
if n != 1:
    raise SystemExit(f'items/payment replacement count={n}')

path.write_text(text)
print('Compact debt sections applied')
