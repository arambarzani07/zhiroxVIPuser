part of 'pdf_service.dart';

class _PdfServiceDocuments {
  static Future<void> generateInvoice({
    required RecordModel debt,
    required String marketName,
    required String adminName,
    String adminPhone = '',
  }) async {
    final font = await rootBundle.load("assets/fonts/NotoKufiArabic.ttf");
    final ttf = pw.Font.ttf(font);
    final boldFont = await rootBundle.load(
      "assets/fonts/NotoKufiArabic-Bold.ttf",
    );
    final ttfBold = pw.Font.ttf(boldFont);

    final pdf = pw.Document();
    final formatter = NumberFormat('#,###', 'en');

    // Parse Items
    List<Map<String, dynamic>> items = [];
    try {
      final rawItems = debt.data['items'];
      if (rawItems is String && rawItems.isNotEmpty && rawItems != '[]') {
        final List<dynamic> decoded = jsonDecode(rawItems);
        items = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      } else if (rawItems is List) {
        items = rawItems.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}

    // Calculation
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final paid = amount - remaining;
    final status = debt.getStringValue('status');
    final description = debt.getStringValue('description');

    // Customer
    final customer = AppHelpers.expandedRecord(debt, 'customer');
    final customerName = customer?.getStringValue('name') ?? 'نەناسراو';

    // Date
    final created = AppHelpers.formatDate(debt.getStringValue('created'));
    final dueDate = debt.getStringValue('due_date');
    final dueDateFormatted = dueDate.isNotEmpty
        ? AppHelpers.formatDate(dueDate)
        : '-';
    final invoiceId = debt.id.substring(debt.id.length - 6).toUpperCase();
    final now = DateTime.now();
    final timeStr = DateFormat('hh:mm a').format(now);

    String statusText = 'چاوەڕوان';
    if (status == 'partial') statusText = 'بەشێک دراوە';
    if (status == 'paid') statusText = 'دراوە';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        build: (pw.Context context) {
          return [
            // ══════════════════════════════════════════════
            // HEADER
            // ══════════════════════════════════════════════
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  color: PdfColor.fromHex('#1a237e'),
                  width: 2,
                ),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                children: [
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 12),
                    decoration: const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFF1a237e),
                      borderRadius: pw.BorderRadius.only(
                        topLeft: pw.Radius.circular(2),
                        topRight: pw.Radius.circular(2),
                      ),
                    ),
                    child: pw.Center(
                      child: pw.Text(
                        PdfService._reshape(marketName),
                        style: pw.TextStyle(
                          font: ttfBold,
                          fontSize: 24,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ),
                  if (adminPhone.isNotEmpty)
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.symmetric(vertical: 6),
                      color: PdfColor.fromHex('#e8eaf6'),
                      child: pw.Center(
                        child: pw.Text(
                          PdfService._reshape('مۆبایل: $adminPhone'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 11,
                            color: PdfColor.fromHex('#1a237e'),
                          ),
                        ),
                      ),
                    ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 10),
                    child: pw.Center(
                      child: pw.Text(
                        PdfService._reshape('وەسڵی قەرز'),
                        style: pw.TextStyle(
                          font: ttfBold,
                          fontSize: 16,
                          color: PdfColor.fromHex('#1a237e'),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 14),

            // ══════════════════════════════════════════════
            // INFO ROW - Customer / Date / Invoice#
            // ══════════════════════════════════════════════
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                children: [
                  // Customer Name
                  pw.Expanded(
                    flex: 3,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          left: pw.BorderSide(color: PdfColors.grey400),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            PdfService._reshape('ناوی کڕیار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            PdfService._reshape(customerName),
                            style: pw.TextStyle(
                              font: ttfBold,
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Date
                  pw.Expanded(
                    flex: 2,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          left: pw.BorderSide(color: PdfColors.grey400),
                        ),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            PdfService._reshape('بەروار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            PdfService._reshape(created),
                            style: pw.TextStyle(font: ttfBold, fontSize: 11),
                          ),
                          pw.Text(
                            timeStr,
                            style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                            textDirection: pw.TextDirection.ltr,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Invoice#
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            PdfService._reshape('ژ.وەسڵ'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            invoiceId,
                            style: pw.TextStyle(
                              font: ttfBold,
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#1a237e'),
                            ),
                            textDirection: pw.TextDirection.ltr,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Due date + status row
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 12,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          PdfService._reshape(dueDateFormatted),
                          style: pw.TextStyle(font: ttfBold, fontSize: 10),
                        ),
                        pw.Text(
                          PdfService._reshape('بەرواری دانەوە:'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 14,
                  ),
                  decoration: pw.BoxDecoration(
                    color: status == 'paid'
                        ? PdfColor.fromHex('#e8f5e9')
                        : status == 'partial'
                        ? PdfColor.fromHex('#fff3e0')
                        : PdfColor.fromHex('#ffebee'),
                    border: pw.Border.all(
                      color: status == 'paid'
                          ? PdfColors.green400
                          : status == 'partial'
                          ? PdfColors.orange400
                          : PdfColor.fromHex('#c62828'),
                    ),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    PdfService._reshape(statusText),
                    style: pw.TextStyle(
                      font: ttfBold,
                      fontSize: 10,
                      color: status == 'paid'
                          ? PdfColors.green800
                          : status == 'partial'
                          ? PdfColors.orange800
                          : PdfColor.fromHex('#c62828'),
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 14),

            // ══════════════════════════════════════════════
            // ITEMS TABLE
            // ══════════════════════════════════════════════
            if (items.isNotEmpty) ...[
              pw.TableHelper.fromTextArray(
                headers: [
                  'کۆی گشتی',
                  'نرخ',
                  'دانە',
                  'کاڵا',
                  '#',
                ].map((h) => PdfService._reshape(h)).toList(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(0.8),
                  3: const pw.FlexColumnWidth(3),
                  4: const pw.FlexColumnWidth(0.5),
                },
                data: List<List<dynamic>>.generate(items.length, (index) {
                  final item = items[index];
                  final name = item['name'] ?? '-';
                  final qty = item['qty'] ?? 1;
                  final price = (item['price'] ?? 0).toDouble();
                  final total = price * qty;

                  return [
                    PdfService._reshape(formatter.format(total)),
                    PdfService._reshape(formatter.format(price)),
                    PdfService._reshape(qty.toString()),
                    PdfService._reshape(name.toString()),
                    (index + 1).toString(),
                  ];
                }),
                headerStyle: pw.TextStyle(
                  font: ttfBold,
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF1a237e),
                ),
                cellStyle: pw.TextStyle(font: ttf, fontSize: 9),
                cellAlignment: pw.Alignment.center,
                headerAlignment: pw.Alignment.center,
                cellHeight: 28,
                headerHeight: 32,
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                oddRowDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFF5F5F5),
                ),
              ),
            ] else if (description.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(4),
                  color: PdfColor.fromInt(0xFFF5F5F5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      PdfService._reshape('وەسف:'),
                      style: pw.TextStyle(
                        font: ttf,
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      PdfService._reshape(description),
                      style: pw.TextStyle(font: ttfBold, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ] else ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Center(
                  child: pw.Text(
                    PdfService._reshape('قەرزی ڕاستەوخۆ'),
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 11,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ),
            ],

            pw.SizedBox(height: 16),

            // ══════════════════════════════════════════════
            // SUMMARY BOXES
            // ══════════════════════════════════════════════
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          PdfService._reshape('کۆی گشتی'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          PdfService._reshape('د.ع ${formatter.format(amount)}'),
                          style: pw.TextStyle(
                            font: ttfBold,
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textDirection: pw.TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.green400),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColor.fromHex('#e8f5e9'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          PdfService._reshape('دراوەتەوە'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.green800,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          PdfService._reshape('د.ع ${formatter.format(paid)}'),
                          style: pw.TextStyle(
                            font: ttfBold,
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.green800,
                          ),
                          textDirection: pw.TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColor.fromHex('#c62828'),
                        width: 1.5,
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                      color: PdfColor.fromHex('#ffebee'),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          PdfService._reshape('ماوە'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColor.fromHex('#c62828'),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          PdfService._reshape('د.ع ${formatter.format(remaining)}'),
                          style: pw.TextStyle(
                            font: ttfBold,
                            fontSize: 15,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#c62828'),
                          ),
                          textDirection: pw.TextDirection.ltr,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 32),

            // ══════════════════════════════════════════════
            // SIGNATURES
            // ══════════════════════════════════════════════
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 20),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  PdfService._buildSignatureBlock(PdfService._reshape('واژووی فرۆشیار'), ttf),
                  PdfService._buildSignatureBlock(PdfService._reshape('واژووی کڕیار'), ttf),
                ],
              ),
            ),

            pw.Spacer(),

            // ══════════════════════════════════════════════
            // FOOTER
            // ══════════════════════════════════════════════
            pw.Container(
              padding: const pw.EdgeInsets.only(top: 8),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    PdfService._reshape(
                      'ئەم بەڵگەنامەیە ڕەسمییە و لەلایەن $marketName ەوە دەرچووە',
                    ),
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Invoice_$invoiceId',
    );
  }

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

    String money(double storageValue, String currency, double rate) {
      final normalized = currency.trim().toUpperCase();
      if (normalized == 'USD' && rate > 0) {
        final displayUsd = storageValue / rate;
        final usd = NumberFormat('#,##0.00', 'en').format(displayUsd);
        return '\$$usd (${formatter.format(storageValue)} د.ع)';
      }
      // Without a historical rate the only trustworthy value is storage IQD.
      return '${formatter.format(storageValue)} د.ع';
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
        PdfService._reshape(typeText),
        PdfService._reshape(AppHelpers.formatDateTime(entry['date']?.toString() ?? '')),
        PdfService._reshape(entry['description']?.toString().isNotEmpty == true
            ? entry['description'].toString()
            : '-'),
        PdfService._reshape(signedAmount),
        balance == null ? '-' : PdfService._reshape('${formatter.format(balance)} د.ع'),
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
                  PdfService._reshape('کەشفی چاتی دارایی'),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 20,
                    color: PdfColor.fromHex('#1D4ED8'),
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  PdfService._reshape('$marketName • $customerName'),
                  style: pw.TextStyle(font: bold, fontSize: 12),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  PdfService._reshape('بەڕێوەبەر: $adminName${adminPhone.isEmpty ? '' : ' • $adminPhone'}'),
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
                if (filterSummary.isNotEmpty) ...[
                  pw.SizedBox(height: 6),
                  pw.Text(
                    PdfService._reshape('فلتەر: $filterSummary'),
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: [
              PdfService._reshape('جۆر'),
              PdfService._reshape('بەروار'),
              PdfService._reshape('وردەکاری'),
              PdfService._reshape('بڕ'),
              PdfService._reshape('ماوەی هەژمار'),
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
              PdfService._reshape('ژمارەی مامەڵەکان: ${entries.length}'),
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
}
