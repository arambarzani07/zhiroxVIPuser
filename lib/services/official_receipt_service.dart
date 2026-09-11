import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pocketbase/pocketbase.dart';
import 'package:printing/printing.dart';
import 'package:zhirox/services/receipt_settings_service.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/utils/kurdish_reshaper.dart';

class OfficialReceiptService {
  OfficialReceiptService._();

  static String _r(String value) => KurdishReshaper.convert(value);

  static String _itemMoney(double amount, String currency) {
    if (currency.trim().toUpperCase() == 'USD') {
      return '\$${NumberFormat('#,##0.00', 'en').format(amount)}';
    }
    return '${NumberFormat('#,###', 'en').format(amount)} د.ع';
  }

  static Future<void> generateDebtReceipt({
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final font = pw.Font.ttf(fontData);
    final bold = pw.Font.ttf(boldData);

    final currency = debt.getStringValue('currency').trim().toUpperCase();
    final dollarRate = debt.getDoubleValue('dollar_rate');
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final paid = amount - remaining;
    final description = debt.getStringValue('description').trim();
    final status = debt.getStringValue('status');
    final customDate = debt.getStringValue('custom_date').trim();
    final createdRaw = customDate.isNotEmpty
        ? customDate
        : debt.getStringValue('created');
    final dueRaw = debt.getStringValue('due_date').trim();
    final created = AppHelpers.formatDateTime(createdRaw);
    final dueDate = dueRaw.isEmpty ? '-' : AppHelpers.formatDate(dueRaw);
    final shortId = debt.id.length > 6
        ? debt.id.substring(debt.id.length - 6).toUpperCase()
        : debt.id.toUpperCase();

    final customer = AppHelpers.expandedRecord(debt, 'customer');
    final customerName = customer?.getStringValue('name').trim() ?? '';
    final customerPhone = customer?.getStringValue('phone').trim() ?? '';

    final items = <Map<String, dynamic>>[];
    try {
      final raw = debt.data['items'];
      if (raw is String && raw.trim().isNotEmpty && raw.trim() != '[]') {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is Map) items.add(Map<String, dynamic>.from(entry));
          }
        }
      } else if (raw is List) {
        for (final entry in raw) {
          if (entry is Map) items.add(Map<String, dynamic>.from(entry));
        }
      }
    } catch (_) {}

    final phone = settings.phone.trim().isNotEmpty
        ? settings.phone.trim()
        : fallbackPhone.trim();
    final isThermal = settings.paperSize == 'thermal80';
    final pageFormat = isThermal
        ? PdfPageFormat(
            80 * PdfPageFormat.mm,
            240 * PdfPageFormat.mm,
            marginAll: 4 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;
    final baseFontSize = isThermal ? 8.5 : 10.0;

    pw.Widget infoLine(String label, String value, {bool ltr = false}) {
      if (value.trim().isEmpty) return pw.SizedBox.shrink();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _r(label),
              style: pw.TextStyle(font: bold, fontSize: baseFontSize),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                ltr ? value : _r(value),
                textAlign: pw.TextAlign.left,
                textDirection:
                    ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
                style: pw.TextStyle(font: font, fontSize: baseFontSize),
              ),
            ),
          ],
        ),
      );
    }

    final itemRows = <List<String>>[];
    for (final item in items) {
      final name = item['name']?.toString().trim() ?? '';
      final qty = item['qty'] is num
          ? (item['qty'] as num).toInt()
          : int.tryParse('${item['qty'] ?? 1}') ?? 1;
      final price = item['price'] is num
          ? (item['price'] as num).toDouble()
          : double.tryParse('${item['price'] ?? 0}') ?? 0;
      final itemCurrency = (item['currency']?.toString().trim().isNotEmpty ?? false)
          ? item['currency'].toString().trim().toUpperCase()
          : currency;
      itemRows.add([
        _r(name.isEmpty ? 'کاڵا' : name),
        qty.toString(),
        _r(_itemMoney(price, itemCurrency)),
        _r(_itemMoney(price * qty, itemCurrency)),
      ]);
    }

    final totalText = AppHelpers.formatStoredFinancialAmount(
      amount,
      currency,
      dollarRate: dollarRate,
      showConversion: true,
    );
    final paidText = AppHelpers.formatStoredFinancialAmount(
      paid,
      currency,
      dollarRate: dollarRate,
      showConversion: true,
    );
    final remainingText = AppHelpers.formatStoredFinancialAmount(
      remaining,
      currency,
      dollarRate: dollarRate,
      showConversion: true,
    );

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: isThermal
            ? const pw.EdgeInsets.all(0)
            : const pw.EdgeInsets.symmetric(horizontal: 34, vertical: 28),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  _r(marketName),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: isThermal ? 16 : 24,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _r(settings.receiptTitle),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: isThermal ? 11 : 15,
                  ),
                ),
                if (settings.address.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    _r(settings.address.trim()),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: font, fontSize: baseFontSize),
                  ),
                ],
                if (phone.isNotEmpty || settings.secondaryPhone.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    [
                      if (phone.isNotEmpty) phone,
                      if (settings.secondaryPhone.trim().isNotEmpty)
                        settings.secondaryPhone.trim(),
                    ].join(' / '),
                    textDirection: pw.TextDirection.ltr,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: font, fontSize: baseFontSize),
                  ),
                ],
                if (settings.registrationNo.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    _r('ژمارەی تۆمار: ${settings.registrationNo.trim()}'),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: font, fontSize: baseFontSize),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: isThermal ? 8 : 14),
          pw.Divider(),
          infoLine('ژمارەی پسوولە', shortId, ltr: true),
          infoLine('بەروار', created),
          infoLine('کڕیار', customerName.isEmpty ? 'نەناسراو' : customerName),
          if (settings.showCustomerPhone && customerPhone.isNotEmpty)
            infoLine('مۆبایلی کڕیار', customerPhone, ltr: true),
          infoLine('بەرواری دانەوە', dueDate),
          if (settings.showAdminName && adminName.trim().isNotEmpty)
            infoLine('بەڕێوەبەر', adminName.trim()),
          pw.SizedBox(height: isThermal ? 6 : 10),
          if (itemRows.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: [
                _r('کاڵا'),
                _r('دانە'),
                _r('نرخ'),
                _r('کۆ'),
              ],
              data: itemRows,
              headerStyle: pw.TextStyle(
                font: bold,
                fontSize: isThermal ? 7 : 9,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey800),
              cellStyle: pw.TextStyle(font: font, fontSize: isThermal ? 6.5 : 8.5),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            )
          else
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Text(
                _r(description.isEmpty ? 'قەرزی ڕاستەوخۆ' : description),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: font, fontSize: baseFontSize),
              ),
            ),
          pw.SizedBox(height: isThermal ? 8 : 14),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(isThermal ? 7 : 12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              children: [
                infoLine('کۆی گشتی', totalText),
                infoLine('پارەی وەرگیراو', paidText),
                infoLine('ماوەی قەرز', remainingText),
                infoLine('دۆخ', AppHelpers.statusName(status)),
              ],
            ),
          ),
          if (description.isNotEmpty && itemRows.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            infoLine('تێبینی', description),
          ],
          pw.SizedBox(height: isThermal ? 12 : 24),
          if (!isThermal)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text(_r('واژۆی کڕیار'), style: pw.TextStyle(font: bold, fontSize: 9)),
                    pw.SizedBox(height: 24),
                    pw.Container(width: 120, height: 1, color: PdfColors.grey600),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text(_r('مۆر / واژۆی مارکێت'), style: pw.TextStyle(font: bold, fontSize: 9)),
                    pw.SizedBox(height: 24),
                    pw.Container(width: 120, height: 1, color: PdfColors.grey600),
                  ],
                ),
              ],
            ),
          pw.SizedBox(height: isThermal ? 8 : 18),
          pw.Divider(),
          pw.Center(
            child: pw.Text(
              _r(settings.footerNote.trim().isEmpty
                  ? 'سوپاس بۆ مامەڵەکردنتان'
                  : settings.footerNote.trim()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: isThermal ? 7.5 : 9),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              'ZHIROX • $shortId',
              textDirection: pw.TextDirection.ltr,
              style: pw.TextStyle(font: font, fontSize: isThermal ? 6 : 7, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (_) async => pdf.save(),
      name: 'Receipt_$shortId',
    );
  }
}
