from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f'{label} marker not found')


profile_path = Path('lib/screens/shared/user_profile_screen.dart')
profile = profile_path.read_text(encoding='utf-8')

# Currency-aware ledger helpers + overdue detection.
helper_marker = "  Future<void> _pickFinancialDateRange() async {\n"
helpers = r'''  String _timelineLedgerKey(_ProfileTimelineItem item) =>
      '${item.kind}:${item.record.id}';

  double? _timelineAmountInIqd(_ProfileTimelineItem item) {
    if (item.isSystem) return 0;
    final amount = item.record.getDoubleValue('amount');
    final debt = item.isPayment ? item.relatedDebt : item.record;
    if (debt == null) return null;
    final currency = debt.getStringValue('currency').isEmpty
        ? 'IQD'
        : debt.getStringValue('currency');
    if (currency != 'USD') return amount;
    final rate = debt.getDoubleValue('dollar_rate');
    if (rate <= 0) return null;
    return amount * rate;
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

'''
if '_financialRunningBalances(' not in profile:
    profile = replace_once(profile, helper_marker, helpers + helper_marker, 'ledger helpers')

# Calculate balances before filters so filtered views never distort the ledger.
profile = replace_once(
    profile,
    "    final allTimelineItems = _buildTimelineItems();\n    final timelineItems = _filterFinancialTimeline(allTimelineItems);\n    final health = _debtHealth(totalRemaining, totalDebt);\n",
    "    final allTimelineItems = _buildTimelineItems();\n    final timelineItems = _filterFinancialTimeline(allTimelineItems);\n    final runningBalances = _financialRunningBalances(allTimelineItems);\n    final health = _debtHealth(totalRemaining, totalDebt);\n",
    'running balances in card',
)
profile = replace_once(
    profile,
    "              ..._buildFinancialChatMessages(timelineItems),\n",
    "              ..._buildFinancialChatMessages(timelineItems, runningBalances),\n",
    'message balance argument',
)
profile = replace_once(
    profile,
    "  List<Widget> _buildFinancialChatMessages(\n    List<_ProfileTimelineItem> timelineItems,\n  ) {\n",
    "  List<Widget> _buildFinancialChatMessages(\n    List<_ProfileTimelineItem> timelineItems,\n    Map<String, double?> runningBalances,\n  ) {\n",
    'message signature',
)
profile = replace_once(
    profile,
    "            : _buildTimelineBubble(item, index),\n",
    "            : _buildTimelineBubble(\n                item,\n                index,\n                balanceAfter: runningBalances[_timelineLedgerKey(item)],\n              ),\n",
    'bubble balance argument',
)
profile = replace_once(
    profile,
    "  Widget _buildTimelineBubble(_ProfileTimelineItem item, int index) {\n",
    "  Widget _buildTimelineBubble(\n    _ProfileTimelineItem item,\n    int index, {\n    double? balanceAfter,\n  }) {\n",
    'bubble signature',
)
profile = replace_once(
    profile,
    "    final receiptPath = isPayment ? '' : record.getStringValue('receipt_image');\n\n",
    "    final receiptPath = isPayment ? '' : record.getStringValue('receipt_image');\n    final overdueLabel = isPayment ? null : _overdueDebtLabel(record);\n    final auth = context.read<AuthProvider>();\n    final canQuickPay = !isPayment &&\n        auth.userRole != 'customer' &&\n        record.getDoubleValue('remaining') > 0;\n\n",
    'bubble finance metadata',
)

feature_anchor = """                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (receiptPath.isNotEmpty) ...[
"""
feature_block = r'''                    if (overdueLabel != null) ...[
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
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
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
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
                      const SizedBox(height: 5),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => unawaited(
                            _showFinancialPaymentSheet(
                              auth,
                              initialDebtId: record.id,
                            ),
                          ),
                          icon: const Icon(Icons.payments_outlined, size: 14),
                          label: const Text('پارەدانەوەی خێرا'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green.shade700,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        if (receiptPath.isNotEmpty) ...[
'''
if 'ماوەی هەژمار' not in profile:
    profile = replace_once(profile, feature_anchor, feature_block, 'bubble ledger UI')

# Quick pay can target the selected debt directly.
profile = replace_once(
    profile,
    "  Future<void> _showFinancialPaymentSheet(AuthProvider auth) async {\n",
    "  Future<void> _showFinancialPaymentSheet(\n    AuthProvider auth, {\n    String? initialDebtId,\n  }) async {\n",
    'payment sheet signature',
)
profile = replace_once(
    profile,
    "    var selectedDebtId = openDebts.first.id;\n    var saving = false;\n",
    "    String selectedDebtId = openDebts.first.id;\n    if (initialDebtId != null &&\n        openDebts.any((debt) => debt.id == initialDebtId)) {\n      selectedDebtId = initialDebtId;\n    }\n    var saving = false;\n",
    'payment sheet initial debt',
)

# Chat export should export the currently visible/filter-selected ledger, not all history.
profile = replace_once(
    profile,
    "                onPressed: () => _generateAccountStatement(\n                  totalDebt: totalDebt,\n                  totalRemaining: totalRemaining,\n                  totalPaid: totalPaid,\n                ),\n                icon: const Icon(Icons.ios_share_rounded, size: 17),\n",
    "                onPressed: _generateFilteredFinancialChatStatement,\n                icon: const Icon(Icons.ios_share_rounded, size: 17),\n",
    'filtered export button',
)

export_marker = "  Future<void> _generateCurrentFinancialStatement() async {\n"
export_method = r'''  Future<void> _generateFilteredFinancialChatStatement() async {
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
      await PdfService.generateFinancialChatStatement(
        entries: entries,
        customerName: _user?.getStringValue('name') ?? '',
        marketName: context.read<AuthProvider>().marketName,
        adminName: context.read<AuthProvider>().userName,
        adminPhone:
            context.read<AuthProvider>().user?.getStringValue('phone') ?? '',
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
if '_generateFilteredFinancialChatStatement()' not in profile:
    profile = replace_once(profile, export_marker, export_method + export_marker, 'filtered export method')

profile_path.write_text(profile, encoding='utf-8')


# Add dedicated PDF export for the visible Financial Chat timeline.
pdf_path = Path('lib/services/pdf_service.dart')
pdf = pdf_path.read_text(encoding='utf-8')
pdf_marker = '  // ==================== Admin Report (Professional, per-customer summary) ====================\n'
pdf_method = r'''  // ==================== Financial Chat Statement ====================

  static Future<void> generateFinancialChatStatement({
    required List<Map<String, dynamic>> entries,
    required String customerName,
    required String marketName,
    required String adminName,
    String adminPhone = '',
    String filterSummary = '',
  }) async {
    final fontData = await rootBundle.load("assets/fonts/NotoKufiArabic.ttf");
    final boldData = await rootBundle.load(
      "assets/fonts/NotoKufiArabic-Bold.ttf",
    );
    final font = pw.Font.ttf(fontData);
    final bold = pw.Font.ttf(boldData);
    final formatter = NumberFormat('#,##0.##', 'en');
    final pdf = pw.Document();

    String money(double value, String currency, double rate) {
      if (currency == 'USD') {
        final usd = NumberFormat('#,##0.00', 'en').format(value);
        if (rate > 0) {
          return '\$$usd (${formatter.format(value * rate)} د.ع)';
        }
        return '\$$usd';
      }
      return '${formatter.format(value)} د.ع';
    }

    final rows = entries.map((entry) {
      final type = entry['type']?.toString() ?? '';
      final amount = (entry['amount'] as num?)?.toDouble() ?? 0;
      final currency = entry['currency']?.toString() ?? 'IQD';
      final rate = (entry['dollar_rate'] as num?)?.toDouble() ?? 0;
      final balance = (entry['balance_after_iqd'] as num?)?.toDouble();
      final typeText = switch (type) {
        'debt' => 'قەرز',
        'payment' => 'پارەدانەوە',
        _ => 'گۆڕانکاری',
      };
      final signedAmount = type == 'system'
          ? '-'
          : '${type == 'payment' ? '−' : '+'} ${money(amount, currency, rate)}';
      return [
        _reshape(typeText),
        _reshape(AppHelpers.formatDateTime(entry['date']?.toString() ?? '')),
        _reshape(entry['description']?.toString().isNotEmpty == true
            ? entry['description'].toString()
            : '-'),
        _reshape(signedAmount),
        balance == null ? '-' : _reshape('${formatter.format(balance)} د.ع'),
      ];
    }).toList(growable: false);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F4F7FB'),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  _reshape('کەشفی چاتی دارایی'),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 20,
                    color: PdfColor.fromHex('#1D4ED8'),
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  _reshape('$marketName • $customerName'),
                  style: pw.TextStyle(font: bold, fontSize: 12),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _reshape('بەڕێوەبەر: $adminName${adminPhone.isEmpty ? '' : ' • $adminPhone'}'),
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
                if (filterSummary.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    _reshape('فلتەر: $filterSummary'),
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: [
              _reshape('جۆر'),
              _reshape('بەروار'),
              _reshape('وردەکاری'),
              _reshape('بڕ'),
              _reshape('ماوەی هەژمار'),
            ],
            data: rows,
            headerStyle: pw.TextStyle(
              font: bold,
              fontSize: 9,
              color: PdfColors.white,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFF2563EB),
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.center,
            headerAlignment: pw.Alignment.center,
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 14),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              _reshape('ژمارەی مامەڵەکان: ${entries.length}'),
              style: pw.TextStyle(font: bold, fontSize: 9),
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'FinancialChat_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}',
    );
  }

'''
if 'generateFinancialChatStatement({' not in pdf:
    pdf = replace_once(pdf, pdf_marker, pdf_method + pdf_marker, 'financial chat PDF')
pdf_path.write_text(pdf, encoding='utf-8')


# Permanently verify Phase 7 markers.
verify_path = Path('scripts/verify_online_only.py')
verify = verify_path.read_text(encoding='utf-8')
verify_marker = "\n\nif violations:\n"
verify_block = r'''

# Financial Chat Phase 7: ledger intelligence, overdue visibility, targeted
# quick-pay and filter-aware PDF export must stay integrated in the customer chat.
for marker in (
    '_financialRunningBalances',
    '_timelineAmountInIqd',
    '_overdueDebtLabel',
    'ماوەی هەژمار',
    'پارەدانەوەی خێرا',
    'initialDebtId',
    '_generateFilteredFinancialChatStatement',
    'PdfService.generateFinancialChatStatement',
):
    if marker not in profile:
        fail(f'Financial Chat Phase 7 marker missing: {marker}')
pdf_source = (LIB / 'services/pdf_service.dart').read_text(encoding='utf-8')
if 'generateFinancialChatStatement({' not in pdf_source:
    fail('lib/services/pdf_service.dart: filter-aware Financial Chat PDF export missing')
'''
if 'Financial Chat Phase 7:' not in verify:
    verify = replace_once(verify, verify_marker, verify_block + verify_marker, 'phase 7 verifier')
verify_path.write_text(verify, encoding='utf-8')
