import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/utils/kurdish_reshaper.dart';
import 'dart:convert';

class PdfService {
  // Helper to reshape text
  static String _reshape(String text) {
    return KurdishReshaper.convert(text);
  }

  static Future<void> generateReport({
    required Map<String, dynamic> stats,
    required List<RecordModel> recentActivity,
    required String adminName,
    required String marketName,
    bool isCustomerStatement = false,
  }) async {
    final font = await rootBundle.load("assets/fonts/NotoKufiArabic.ttf");
    final ttf = pw.Font.ttf(font);
    final boldFont = await rootBundle.load(
      "assets/fonts/NotoKufiArabic-Bold.ttf",
    );
    final ttfBold = pw.Font.ttf(boldFont);

    final pdf = pw.Document();

    final totalCustomers = (stats['totalCustomers'] ?? 0).toString();
    final totalDebt = (stats['totalDebt'] ?? 0).toDouble();
    final totalRemaining = (stats['totalRemaining'] ?? 0).toDouble();
    final totalPayments = (stats['totalPayments'] ?? 0).toDouble();
    final pendingDebts = (stats['pendingDebts'] ?? 0).toString();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return [
            _buildHeader(marketName, adminName, ttfBold),
            pw.SizedBox(height: 20),
            _buildSummaryTable(
              totalDebt,
              totalRemaining,
              totalPayments,
              totalCustomers,
              pendingDebts,
              ttfBold,
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              _reshape('چالاکییە تازەکان'),
              style: pw.TextStyle(
                font: ttfBold,
                fontSize: 18,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 10),
            _buildActivityTable(
              recentActivity,
              ttfBold,
              isCustomerStatement: isCustomerStatement,
            ),
            pw.Spacer(),
            _buildFooter(marketName),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'Report_${AppHelpers.formatDate(DateTime.now().toString()).replaceAll('/', '-')}',
    );
  }

  static pw.Widget _buildHeader(
    String marketName,
    String adminName,
    pw.Font font,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _reshape('ڕاپۆرتی گشتی (جەرد)'),
              style: pw.TextStyle(
                font: font,
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue800,
              ),
            ),
            pw.Text(
              _reshape(
                'بەروار: ${AppHelpers.formatDateTime(DateTime.now().toString())}',
              ),
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              _reshape(marketName),
              style: pw.TextStyle(
                font: font,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Text(
              _reshape('بەڕێوەبەر: $adminName'),
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildSummaryTable(
    double totalDebt,
    double remaining,
    double received,
    String customers,
    String pending,
    pw.Font font,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
        color: PdfColors.grey50,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryItem(
            'کۆی گشتی قەرز',
            totalDebt,
            PdfColors.black,
            font,
            isCurrency: true,
          ),
          _buildSummaryItem(
            'ماوە (قەرز)',
            remaining,
            PdfColors.red800,
            font,
            isCurrency: true,
          ),
          _buildSummaryItem(
            'وەرگیراو',
            received,
            PdfColors.green800,
            font,
            isCurrency: true,
          ),
          _buildSummaryItem(
            'ژ. کڕیار',
            double.tryParse(customers) ?? 0,
            PdfColors.blue800,
            font,
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryItem(
    String label,
    double value,
    PdfColor color,
    pw.Font font, {
    bool isCurrency = false,
  }) {
    // Note: Numbers generally do not need reshaping unless they are Arabic-Indic digits
    // mixed with text. Here we keep them separate mostly.
    String textValue = value.toInt().toString();
    if (isCurrency) {
      final formatter = NumberFormat('#,###', 'en');
      // Currency symbol on LEFT: "د.ع 1,000"
      textValue = 'د.ع ${formatter.format(value)}';
    }

    return pw.Column(
      children: [
        pw.Text(
          _reshape(label),
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          isCurrency ? _reshape(textValue) : textValue,
          style: pw.TextStyle(
            font: font,
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
          textDirection: pw.TextDirection.ltr,
        ),
      ],
    );
  }

  static pw.Widget _buildActivityTable(
    List<RecordModel> activities,
    pw.Font font, {
    bool isCustomerStatement = false,
  }) {
    if (activities.isEmpty) {
      return pw.Center(child: pw.Text(_reshape('هیچ چالاکیەک نییە')));
    }

    // Reordered for Visual RTL
    final headers = [
      'دۆخ',
      'بەرواری کۆتایی',
      'بەرواری قەرز',
      'بڕی دراو',
      'بڕی قەرز',
      isCustomerStatement ? 'کاڵاکان' : 'ناوی کڕیار', // Dynamic Header
      '#',
    ].map((h) => _reshape(h)).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: List<List<dynamic>>.generate(activities.length, (index) {
        final activity = activities[index];
        final amount = activity.getDoubleValue('amount');
        final remaining = activity.getDoubleValue('remaining');
        final paid = amount - remaining;

        final customDate = activity.getStringValue('custom_date');
        final created = AppHelpers.formatDate(
          customDate.isNotEmpty ? customDate : activity.created,
        );
        final updated = AppHelpers.formatDate(activity.updated);

        final status = activity.getStringValue('status');
        String statusText = status;
        if (status == 'pending') statusText = 'قەرز';
        if (status == 'partial') statusText = 'بەشێک';
        if (status == 'paid') statusText = 'دراوە';

        final formatter = NumberFormat('#,###', 'en');
        final amountStr = formatter.format(amount);
        final paidStr = formatter.format(paid);

        // Dynamic Column Content
        String mainColumnContent = '';
        if (isCustomerStatement) {
          // Show Items
          try {
            final itemsJson = activity.getStringValue('items');
            if (itemsJson.isNotEmpty && itemsJson != '[]') {
              final List<dynamic> decoded = jsonDecode(itemsJson);
              final itemNames = decoded
                  .map((e) => e['name'] as String)
                  .toList();
              mainColumnContent = itemNames.join('، '); // Comma separated
            } else {
              mainColumnContent = 'قەرزی راستەوخۆ';
            }
          } catch (_) {
            mainColumnContent = 'قەرزی راستەوخۆ';
          }
        } else {
          // Show Customer Name
          final customer = activity.expand['customer']?.first;
          mainColumnContent = customer?.getStringValue('name') ?? 'نەناسراو';
        }

        return [
          _reshape(statusText),
          _reshape(updated),
          _reshape(created),
          _reshape(paidStr),
          _reshape(amountStr),
          _reshape(mainColumnContent),
          (index + 1).toString(),
        ];
      }),
      headerStyle: pw.TextStyle(
        font: font,
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue800),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
      ),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
    );
  }

  static pw.Widget _buildFooter(String marketName) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _reshape(
                'ئەم ڕاپۆرتە لەلایەن سیستەمی $marketName ەوە دروستکراوە',
              ),
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
            ),
          ],
        ),
      ],
    );
  }
  // ==================== Invoice Generation ====================

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
    final customer = debt.expand['customer']?.first;
    final customerName = customer?.getStringValue('name') ?? 'نەناسراو';

    // Date
    final created = AppHelpers.formatDate(debt.created);
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
                        _reshape(marketName),
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
                          _reshape('مۆبایل: $adminPhone'),
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
                        _reshape('وەصڵی قەرز'),
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
                            _reshape('ناوی کڕیار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            _reshape(customerName),
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
                            _reshape('بەروار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            _reshape(created),
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
                            _reshape('ژ.وەصڵ'),
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
                          _reshape(dueDateFormatted),
                          style: pw.TextStyle(font: ttfBold, fontSize: 10),
                        ),
                        pw.Text(
                          _reshape('بەرواری دانەوە:'),
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
                    _reshape(statusText),
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
                ].map((h) => _reshape(h)).toList(),
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
                    _reshape(formatter.format(total)),
                    _reshape(formatter.format(price)),
                    _reshape(qty.toString()),
                    _reshape(name.toString()),
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
                      _reshape('وەسف:'),
                      style: pw.TextStyle(
                        font: ttf,
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _reshape(description),
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
                    _reshape('قەرزی ڕاستەوخۆ'),
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
                          _reshape('کۆی گشتی'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(amount)}'),
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
                          _reshape('دراوەتەوە'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.green800,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(paid)}'),
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
                          _reshape('ماوە'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColor.fromHex('#c62828'),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(remaining)}'),
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
                  _buildSignatureBlock(_reshape('واژووی فرۆشیار'), ttf),
                  _buildSignatureBlock(_reshape('واژووی کڕیار'), ttf),
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
                    _reshape(
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

  // ==================== Admin Report (Professional, per-customer summary) ====================

  static Future<void> generateAdminReport({
    required List<RecordModel> allDebts,
    required String marketName,
    required String adminName,
    required String adminPhone,
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
    required int totalCustomers,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final font = await rootBundle.load("assets/fonts/NotoKufiArabic.ttf");
    final ttf = pw.Font.ttf(font);
    final boldFont = await rootBundle.load(
      "assets/fonts/NotoKufiArabic-Bold.ttf",
    );
    final ttfBold = pw.Font.ttf(boldFont);

    final pdf = pw.Document();
    final formatter = NumberFormat('#,###', 'en');
    final now = DateTime.now();
    final dateStr = AppHelpers.formatDate(now.toString());
    final timeStr = DateFormat('hh:mm a').format(now);

    // Date range display
    final bool hasDateRange = fromDate != null && toDate != null;
    final String dateRangeStr = hasDateRange
        ? 'لە ${AppHelpers.formatDate(fromDate.toString())} بۆ ${AppHelpers.formatDate(toDate.toString())}'
        : '';

    // Group debts by customer
    final Map<String, Map<String, dynamic>> customerMap = {};
    for (var debt in allDebts) {
      final customer = debt.expand['customer']?.first;
      final customerId = debt.getStringValue('customer');
      final customerName = customer?.getStringValue('name') ?? 'نەناسراو';
      final amount = debt.getDoubleValue('amount');
      final remaining = debt.getDoubleValue('remaining');
      final status = debt.getStringValue('status');

      if (!customerMap.containsKey(customerId)) {
        customerMap[customerId] = {
          'name': customerName,
          'totalDebt': 0.0,
          'totalRemaining': 0.0,
          'totalPaid': 0.0,
          'debtCount': 0,
          'paidCount': 0,
          'activeCount': 0,
          'firstDebtDate': debt.created,
          'lastDebtDate': debt.created,
        };
      }
      // Track earliest and latest debt dates
      if (debt.created.compareTo(customerMap[customerId]!['firstDebtDate']) <
          0) {
        customerMap[customerId]!['firstDebtDate'] = debt.created;
      }
      if (debt.created.compareTo(customerMap[customerId]!['lastDebtDate']) >
          0) {
        customerMap[customerId]!['lastDebtDate'] = debt.created;
      }
      customerMap[customerId]!['totalDebt'] += amount;
      customerMap[customerId]!['totalRemaining'] += remaining;
      customerMap[customerId]!['totalPaid'] += (amount - remaining);
      customerMap[customerId]!['debtCount']++;
      if (status == 'paid') {
        customerMap[customerId]!['paidCount']++;
      } else {
        customerMap[customerId]!['activeCount']++;
      }
    }

    // Sort by remaining descending (biggest debtors first)
    final sortedCustomers = customerMap.entries.toList()
      ..sort(
        (a, b) => (b.value['totalRemaining'] as double).compareTo(
          a.value['totalRemaining'] as double,
        ),
      );

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
                        _reshape(marketName),
                        style: pw.TextStyle(
                          font: ttfBold,
                          fontSize: 24,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    color: PdfColor.fromHex('#e8eaf6'),
                    child: pw.Center(
                      child: pw.Text(
                        adminPhone.isNotEmpty
                            ? _reshape('مۆبایل: $adminPhone')
                            : _reshape('بەڕێوەبەر: $adminName'),
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
                    child: pw.Column(
                      children: [
                        pw.Center(
                          child: pw.Text(
                            _reshape(
                              hasDateRange
                                  ? 'کەشفی حیساب'
                                  : 'ڕاپۆرتی گشتی - کەشفی حیساب',
                            ),
                            style: pw.TextStyle(
                              font: ttfBold,
                              fontSize: 16,
                              color: PdfColor.fromHex('#1a237e'),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        if (hasDateRange) ...[
                          pw.SizedBox(height: 4),
                          pw.Center(
                            child: pw.Text(
                              _reshape(dateRangeStr),
                              style: pw.TextStyle(
                                font: ttf,
                                fontSize: 11,
                                color: PdfColor.fromHex('#1a237e'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 14),

            // ══════════════════════════════════════════════
            // INFO ROW
            // ══════════════════════════════════════════════
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                children: [
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
                        children: [
                          pw.Text(
                            _reshape('بەڕێوەبەر'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            _reshape(adminName),
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
                        children: [
                          pw.Text(
                            _reshape('بەروار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            _reshape(dateStr),
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
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        children: [
                          pw.Text(
                            _reshape('ژ.کڕیار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '$totalCustomers',
                            style: pw.TextStyle(
                              font: ttfBold,
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#e65100'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 14),

            // ══════════════════════════════════════════════
            // CUSTOMERS TABLE
            // ══════════════════════════════════════════════
            if (sortedCustomers.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.green300),
                  borderRadius: pw.BorderRadius.circular(4),
                  color: PdfColor.fromHex('#e8f5e9'),
                ),
                child: pw.Center(
                  child: pw.Text(
                    _reshape('هیچ قەرزێک نییە'),
                    style: pw.TextStyle(
                      font: ttfBold,
                      fontSize: 14,
                      color: PdfColors.green800,
                    ),
                  ),
                ),
              )
            else
              _buildAdminCustomerTable(
                sortedCustomers,
                ttfBold,
                ttf,
                formatter,
              ),

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
                          _reshape('کۆی گشتی'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.grey600,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(totalDebt)}'),
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
                          _reshape('دراوەتەوە'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColors.green800,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(totalPaid)}'),
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
                          _reshape('ماوە'),
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: 9,
                            color: PdfColor.fromHex('#c62828'),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          _reshape('د.ع ${formatter.format(totalRemaining)}'),
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
            // SIGNATURE
            // ══════════════════════════════════════════════
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 20),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildSignatureBlock(_reshape('واژووی بەڕێوەبەر'), ttf),
                  _buildSignatureBlock(_reshape('واژووی ژمێریار'), ttf),
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
                    _reshape(
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
      name:
          'AdminReport_${AppHelpers.formatDate(now.toString()).replaceAll('/', '-')}',
    );
  }

  /// Per-customer summary table for admin report
  static pw.Widget _buildAdminCustomerTable(
    List<MapEntry<String, Map<String, dynamic>>> customers,
    pw.Font fontBold,
    pw.Font fontRegular,
    NumberFormat formatter,
  ) {
    final headers = [
      'دۆخ',
      'بەروار',
      'ماوە',
      'دراوەتەوە',
      'کۆی قەرز',
      'ناوی کڕیار',
      '#',
    ].map((h) => _reshape(h)).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5), // Status
        1: const pw.FlexColumnWidth(1.4), // Date
        2: const pw.FlexColumnWidth(1.5), // Remaining
        3: const pw.FlexColumnWidth(1.5), // Paid
        4: const pw.FlexColumnWidth(1.5), // Total
        5: const pw.FlexColumnWidth(2.2), // Name
        6: const pw.FlexColumnWidth(0.5), // #
      },
      data: List<List<dynamic>>.generate(customers.length, (index) {
        final entry = customers[index];
        final data = entry.value;
        final paid = data['totalPaid'] as double;
        final remaining = data['totalRemaining'] as double;
        final total = data['totalDebt'] as double;
        final activeCount = data['activeCount'] as int;
        final paidCount = data['paidCount'] as int;
        final firstDate = data['firstDebtDate'] as String;

        // Format the date
        String dateDisplay = '';
        try {
          final parsed = DateTime.parse(firstDate);
          dateDisplay =
              '${parsed.year}/${parsed.month.toString().padLeft(2, '0')}/${parsed.day.toString().padLeft(2, '0')}';
        } catch (_) {
          dateDisplay = '-';
        }

        String statusText = '';
        if (activeCount > 0 && paidCount > 0) {
          statusText = '$activeCount چالاک / $paidCount دراو';
        } else if (activeCount > 0) {
          statusText = '$activeCount چالاک';
        } else {
          statusText = '$paidCount دراو';
        }

        return [
          _reshape(statusText),
          _reshape(dateDisplay),
          _reshape(formatter.format(remaining)),
          _reshape(formatter.format(paid)),
          _reshape(formatter.format(total)),
          _reshape(data['name'] as String),
          (index + 1).toString(),
        ];
      }),
      headerStyle: pw.TextStyle(
        font: fontBold,
        fontSize: 8,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF1a237e),
      ),
      headerAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.center,
      },
      cellStyle: pw.TextStyle(font: fontRegular, fontSize: 8),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      cellHeight: 26,
      headerHeight: 30,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF5F5F5),
      ),
    );
  }

  // ==================== Customer Statement (Official Receipt) ====================

  static Future<void> generateCustomerStatement({
    required List<RecordModel> activeDebts,
    required String customerName,
    required String marketName,
    required String adminName,
    required String adminPhone,
    required double totalDebt,
    required double totalRemaining,
    required double totalPaid,
  }) async {
    final font = await rootBundle.load("assets/fonts/NotoKufiArabic.ttf");
    final ttf = pw.Font.ttf(font);
    final boldFont = await rootBundle.load(
      "assets/fonts/NotoKufiArabic-Bold.ttf",
    );
    final ttfBold = pw.Font.ttf(boldFont);

    final pdf = pw.Document();
    final formatter = NumberFormat('#,###', 'en');
    final now = DateTime.now();
    final dateStr = AppHelpers.formatDate(now.toString());
    final timeStr = DateFormat('hh:mm a').format(now);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        build: (pw.Context context) {
          return [
            // ══════════════════════════════════════════════
            // HEADER - Market Name + Contact + Title
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
                  // Top bar - Market Name
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
                        _reshape(marketName),
                        style: pw.TextStyle(
                          font: ttfBold,
                          fontSize: 24,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                  ),
                  // Contact info
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 6),
                    color: PdfColor.fromHex('#e8eaf6'),
                    child: pw.Center(
                      child: pw.Text(
                        adminPhone.isNotEmpty
                            ? _reshape('مۆبایل: $adminPhone')
                            : _reshape(adminName),
                        style: pw.TextStyle(
                          font: ttf,
                          fontSize: 11,
                          color: PdfColor.fromHex('#1a237e'),
                        ),
                      ),
                    ),
                  ),
                  // Title
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 10),
                    child: pw.Center(
                      child: pw.Text(
                        _reshape('کەشفی حیسابی کڕیار'),
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
            // INFO ROW - Customer / Date / Count
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
                            _reshape('ناوی کڕیار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            _reshape(customerName),
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
                            _reshape('بەروار'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            _reshape(dateStr),
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
                  // Count
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            _reshape('ژ.قەرز'),
                            style: pw.TextStyle(
                              font: ttf,
                              fontSize: 9,
                              color: PdfColors.grey600,
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '${activeDebts.length}',
                            style: pw.TextStyle(
                              font: ttfBold,
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#e65100'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 14),

            // ══════════════════════════════════════════════
            // DEBTS TABLE
            // ══════════════════════════════════════════════
            if (activeDebts.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.green300),
                  borderRadius: pw.BorderRadius.circular(4),
                  color: PdfColor.fromHex('#e8f5e9'),
                ),
                child: pw.Center(
                  child: pw.Text(
                    _reshape('هیچ قەرزێکی چالاک نییە'),
                    style: pw.TextStyle(
                      font: ttfBold,
                      fontSize: 14,
                      color: PdfColors.green800,
                    ),
                  ),
                ),
              )
            else
              _buildStatementTable(activeDebts, ttfBold, ttf),

            pw.SizedBox(height: 16),

            // ══════════════════════════════════════════════
            // SUMMARY - Total Debt Only
            // ══════════════════════════════════════════════
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 16,
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
                    _reshape('کۆی گشتی قەرز'),
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 11,
                      color: PdfColor.fromHex('#c62828'),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    _reshape('د.ع ${formatter.format(totalRemaining)}'),
                    style: pw.TextStyle(
                      font: ttfBold,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#c62828'),
                    ),
                    textDirection: pw.TextDirection.ltr,
                  ),
                ],
              ),
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
                  _buildSignatureBlock(_reshape('واژووی فرۆشیار'), ttf),
                  _buildSignatureBlock(_reshape('واژووی کڕیار'), ttf),
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
                    _reshape(
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
      name:
          'Statement_${customerName}_${AppHelpers.formatDate(now.toString()).replaceAll('/', '-')}',
    );
  }

  static pw.Widget _buildSignatureBlock(String label, pw.Font font) {
    return pw.Column(
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: font,
            fontSize: 10,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 35),
        pw.Container(
          width: 160,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: PdfColors.grey400,
                width: 0.8,
                style: pw.BorderStyle.dashed,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Table for customer statement - only active debts
  static pw.Widget _buildStatementTable(
    List<RecordModel> debts,
    pw.Font fontBold,
    pw.Font fontRegular,
  ) {
    final formatter = NumberFormat('#,###', 'en');

    final headers = [
      'دۆخ',
      'بەرواری دانەوە',
      'بەرواری قەرز',
      'ماوە',
      'بڕی قەرز',
      'وەسف',
      '#',
    ].map((h) => _reshape(h)).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.2), // Status
        1: const pw.FlexColumnWidth(1.5), // Due date
        2: const pw.FlexColumnWidth(1.5), // Created
        3: const pw.FlexColumnWidth(1.5), // Remaining
        4: const pw.FlexColumnWidth(1.5), // Amount
        5: const pw.FlexColumnWidth(2.5), // Description
        6: const pw.FlexColumnWidth(0.5), // #
      },
      data: List<List<dynamic>>.generate(debts.length, (index) {
        final debt = debts[index];
        final amount = debt.getDoubleValue('amount');
        final remaining = debt.getDoubleValue('remaining');
        final customDate = debt.getStringValue('custom_date');
        final created = AppHelpers.formatDate(
          customDate.isNotEmpty ? customDate : debt.created,
        );
        final dueDate = debt.getStringValue('due_date');
        final dueDateFormatted = dueDate.isNotEmpty
            ? AppHelpers.formatDate(dueDate)
            : '-';

        final status = debt.getStringValue('status');
        String statusText = '';
        if (status == 'pending') statusText = 'چاوەڕوان';
        if (status == 'partial') statusText = 'بەشێک';

        // Description
        String desc = '';
        try {
          final rawItems = debt.data['items'];
          List itemsList = [];
          if (rawItems is String && rawItems.isNotEmpty && rawItems != '[]') {
            itemsList = jsonDecode(rawItems);
          } else if (rawItems is List) {
            itemsList = rawItems;
          }
          if (itemsList.isNotEmpty) {
            desc = itemsList.map((e) => e['name'] ?? '').join('، ');
          }
        } catch (_) {}
        if (desc.isEmpty) {
          desc = debt.getStringValue('description');
          if (desc.isEmpty) desc = '-';
        }

        return [
          _reshape(statusText),
          _reshape(dueDateFormatted),
          _reshape(created),
          _reshape(formatter.format(remaining)),
          _reshape(formatter.format(amount)),
          _reshape(desc),
          (index + 1).toString(),
        ];
      }),
      headerStyle: pw.TextStyle(
        font: fontBold,
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFF1a237e),
      ),
      headerAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.center,
      },
      cellStyle: pw.TextStyle(font: fontRegular, fontSize: 9),
      cellAlignment: pw.Alignment.center,
      headerAlignment: pw.Alignment.center,
      cellHeight: 28,
      headerHeight: 32,
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      oddRowDecoration: const pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF5F5F5),
      ),
    );
  }
}
