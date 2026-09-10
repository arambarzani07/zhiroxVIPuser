from pathlib import Path

path = Path('lib/screens/shared/debt_detail_screen.dart')
text = path.read_text()

# Add focused action helpers before build().
build_marker = "  @override\n  Widget build(BuildContext context) {\n"
if "Future<void> _printDebtInvoice()" not in text:
    helpers = r'''  Future<void> _printDebtInvoice() async {
    if (_debt == null) return;
    final auth = context.read<AuthProvider>();
    String marketName = auth.marketName;
    String adminPhone = '';

    if (marketName.isEmpty) {
      try {
        final admin = await PBService.getUser(auth.adminId);
        marketName = admin.getStringValue('market_name');
        adminPhone = admin.getStringValue('phone');
      } catch (_) {
        marketName = 'Zhirox System';
      }
    } else {
      adminPhone = auth.user?.getStringValue('phone') ?? '';
    }

    await PdfService.generateInvoice(
      debt: _debt!,
      marketName: marketName,
      adminName: auth.userName,
      adminPhone: adminPhone,
    );
  }

  Future<void> _editCurrentDebt() async {
    if (_debt == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddDebtScreen(
          debt: _debt,
          customerId: _debt!.getStringValue('customer'),
        ),
      ),
    );
    if (result == true && mounted) {
      await _loadData();
    }
  }

  Future<void> _handleDebtAction(String action) async {
    switch (action) {
      case 'print':
        await _printDebtInvoice();
        break;
      case 'edit':
        await _editCurrentDebt();
        break;
      case 'delete':
        if (mounted) _confirmDelete();
        break;
    }
  }

'''
    if build_marker not in text:
        raise SystemExit('build marker not found')
    text = text.replace(build_marker, helpers + build_marker, 1)

# amountUsd is no longer needed by the compact header.
text = text.replace("    final amountUsd = _debt!.getDoubleValue('amount_usd');\n", "")

start_marker = "          // ───── Gradient Header ─────\n"
end_marker = "          // ───── Items List (if any) ─────\n"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start == -1 or end == -1:
    raise SystemExit('detail header/info markers not found')

replacement = r'''          // ───── Compact Debt Header ─────
          SliverToBoxAdapter(
            child: Container(
              color: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'گەڕانەوە',
                            icon: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 20,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF344054),
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Text(
                              'وردەکاری قەرز',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? AppDarkColors.textPrimary
                                    : const Color(0xFF101828),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'کردارەکان',
                            onSelected: _handleDebtAction,
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF344054),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'print',
                                child: Row(
                                  children: [
                                    Icon(Icons.print_outlined, size: 19),
                                    SizedBox(width: 10),
                                    Text('چاپ / وەصڵ'),
                                  ],
                                ),
                              ),
                              if (!isCustomer && auth.canEditDebts)
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 19),
                                      SizedBox(width: 10),
                                      Text('دەستکاری'),
                                    ],
                                  ),
                                ),
                              if (!isCustomer && auth.userRole == 'admin')
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline_rounded,
                                        size: 19,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'سڕینەوە',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        status == 'paid' ? 'کۆی قەرز' : 'ماوەی قەرز',
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.78),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        AppHelpers.formatCurrencyWithType(
                                          (currency == 'USD' && dollarRate > 0)
                                              ? (status == 'paid' ? amount : remaining) /
                                                  dollarRate
                                              : (status == 'paid' ? amount : remaining),
                                          (currency == 'USD' && dollarRate > 0)
                                              ? 'USD'
                                              : 'IQD',
                                          dollarRate: dollarRate,
                                          showConversion: false,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w900,
                                          height: 1.1,
                                        ),
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        AppHelpers.statusName(status),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (customerName.isNotEmpty ||
                                _debt!.getStringValue('description').isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                [
                                  if (customerName.isNotEmpty) customerName,
                                  if (_debt!.getStringValue('description').isNotEmpty)
                                    _debt!.getStringValue('description'),
                                ].join('  •  '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: paidPercent.clamp(0.0, 1.0),
                                minHeight: 5,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.20),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${(paidPercent.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}% دراوە',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'دراوە: ${AppHelpers.formatCurrency(paid)}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.76),
                                    fontSize: 10.5,
                                  ),
                                  textDirection: TextDirection.ltr,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ───── Compact Metadata ─────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isDark ? AppDarkColors.card : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : const Color(0xFFE9EDF3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildMetaCell(
                          Icons.monetization_on_outlined,
                          'کۆی قەرز',
                          AppHelpers.formatCurrency(amount),
                          AppColors.primary,
                        ),
                        _buildMetaCell(
                          Icons.event_outlined,
                          'بەرواری دانەوە',
                          _debt!.getStringValue('due_date').isEmpty
                              ? 'دیاری نەکراوە'
                              : AppHelpers.formatDate(
                                  _debt!.getStringValue('due_date'),
                                ),
                          Colors.orange,
                        ),
                      ],
                    ),
                    Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF0F2F5),
                    ),
                    Row(
                      children: [
                        _buildMetaCell(
                          Icons.calendar_month_outlined,
                          'بەرواری قەرز',
                          AppHelpers.formatDate(
                            _debt!.getStringValue('custom_date').isNotEmpty
                                ? _debt!.getStringValue('custom_date')
                                : _debt!.created,
                          ),
                          Colors.purple,
                        ),
                        _buildMetaCell(
                          Icons.schedule_outlined,
                          'کاتژمێر',
                          AppHelpers.formatTime(
                            _debt!.getStringValue('custom_date').isNotEmpty
                                ? _debt!.getStringValue('custom_date')
                                : _debt!.created,
                          ),
                          Colors.teal,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

'''
text = text[:start] + replacement + text[end:]

# Replace old heavy info-chip widget with a compact metadata cell.
helper_start = text.find("  Widget _buildInfoChip(\n")
helper_end = text.find("  List<Widget> _buildItemsSliver() {\n", helper_start)
if helper_start == -1 or helper_end == -1:
    raise SystemExit('info chip helper markers not found')
meta_helper = r'''  Widget _buildMetaCell(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : const Color(0xFF98A2B3),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : const Color(0xFF344054),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
text = text[:helper_start] + meta_helper + text[helper_end:]

path.write_text(text)
