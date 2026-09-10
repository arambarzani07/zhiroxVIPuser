import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/utils/kurdish_reshaper.dart';

/// PDF output used by the customer/end-user application.
///
/// Admin dashboards, employee reports and full-market ledgers belong to C-Panel
/// and intentionally are not compiled into this app.
class PdfService {
  static String _rtl(String value) => KurdishReshaper.convert(value);

  static String _date(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return '—';
    return DateFormat('yyyy/MM/dd').format(date);
  }

  static String _money(double value, String currency) {
    if (currency == 'USD') {
      return '\$${NumberFormat('#,##0.00', 'en').format(value)}';
    }
    return '${NumberFormat('#,###', 'en').format(value)} د.ع';
  }

  static pw.TextStyle _style(
    pw.Font font, {
    double size = 10,
    PdfColor color = PdfColors.black,
  }) {
    return pw.TextStyle(font: font, fontSize: size, color: color);
  }

  static pw.Widget _labelValue({
    required String label,
    required String value,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F6F8FC'),
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 0.6),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              _rtl(label),
              textDirection: pw.TextDirection.rtl,
              style: _style(regular, size: 9, color: PdfColor.fromHex('#64748B')),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            _rtl(value),
            textDirection: pw.TextDirection.rtl,
            style: _style(bold, size: 10, color: PdfColor.fromHex('#0F172A')),
          ),
        ],
      ),
    );
  }

  static pw.Widget _summaryBox({
    required String title,
    required String value,
    required PdfColor accent,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(11),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: accent, width: 1),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _rtl(title),
              textDirection: pw.TextDirection.rtl,
              style: _style(regular, size: 8.5, color: PdfColor.fromHex('#64748B')),
            ),
            pw.SizedBox(height: 5),
            pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                _rtl(value),
                textDirection: pw.TextDirection.rtl,
                style: _style(bold, size: 14, color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _tableCell(
    String value,
    pw.Font font, {
    bool header = false,
    pw.Alignment alignment = pw.Alignment.centerRight,
  }) {
    return pw.Container(
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(
        _rtl(value),
        textDirection: pw.TextDirection.rtl,
        maxLines: 2,
        style: _style(
          font,
          size: header ? 8.5 : 8,
          color: header ? PdfColors.white : PdfColor.fromHex('#1E293B'),
        ),
      ),
    );
  }

  static pw.TableRow _headerRow(pw.Font bold) {
    const headers = [
      '#',
      'وەسف',
      'بەروار',
      'بەرواری دوایین',
      'کۆی قەرز',
      'ماوە',
      'دۆخ',
    ];
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#1E3A8A')),
      children: [
        _tableCell(headers[0], bold, header: true, alignment: pw.Alignment.center),
        _tableCell(headers[1], bold, header: true),
        _tableCell(headers[2], bold, header: true, alignment: pw.Alignment.center),
        _tableCell(headers[3], bold, header: true, alignment: pw.Alignment.center),
        _tableCell(headers[4], bold, header: true, alignment: pw.Alignment.center),
        _tableCell(headers[5], bold, header: true, alignment: pw.Alignment.center),
        _tableCell(headers[6], bold, header: true, alignment: pw.Alignment.center),
      ],
    );
  }

  static String _status(RecordModel debt) {
    switch (debt.getStringValue('status')) {
      case 'paid':
        return 'دراوە';
      case 'partial':
        return 'بەشێکی دراوە';
      case 'pending':
        return 'چاوەڕوانە';
      default:
        return debt.getStringValue('status').isEmpty
            ? '—'
            : debt.getStringValue('status');
    }
  }

  static pw.TableRow _debtRow(
    RecordModel debt,
    int index,
    pw.Font regular,
  ) {
    final currency = debt.getStringValue('currency').isEmpty
        ? 'IQD'
        : debt.getStringValue('currency');
    final created = debt.getStringValue('custom_date').isNotEmpty
        ? debt.getStringValue('custom_date')
        : debt.created;
    final description = debt.getStringValue('description').trim();

    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: index.isEven ? PdfColors.white : PdfColor.fromHex('#F8FAFC'),
      ),
      children: [
        _tableCell('${index + 1}', regular, alignment: pw.Alignment.center),
        _tableCell(description.isEmpty ? 'قەرز' : description, regular),
        _tableCell(_date(created), regular, alignment: pw.Alignment.center),
        _tableCell(
          _date(debt.getStringValue('due_date')),
          regular,
          alignment: pw.Alignment.center,
        ),
        _tableCell(
          _money(debt.getDoubleValue('amount'), currency),
          regular,
          alignment: pw.Alignment.center,
        ),
        _tableCell(
          _money(debt.getDoubleValue('remaining'), currency),
          regular,
          alignment: pw.Alignment.center,
        ),
        _tableCell(_status(debt), regular, alignment: pw.Alignment.center),
      ],
    );
  }

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
    final regularData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final regular = pw.Font.ttf(regularData);
    final bold = pw.Font.ttf(boldData);

    final now = DateTime.now();
    final generatedDate = DateFormat('yyyy/MM/dd').format(now);
    final generatedTime = DateFormat('HH:mm').format(now);
    final marketTitle = marketName.trim().isEmpty ? 'Zhirox' : marketName.trim();
    final managerTitle = adminName.trim().isEmpty ? 'بەڕێوەبەر' : adminName.trim();

    final document = pw.Document(
      title: 'Zhirox Customer Statement',
      author: marketTitle,
      creator: 'Zhirox Customer App',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 26),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: pw.TextDirection.rtl,
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 7),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _rtl('ژیرۆکس — کەشفی حیسابی کڕیار'),
                textDirection: pw.TextDirection.rtl,
                style: _style(regular, size: 7.5, color: PdfColors.grey600),
              ),
              pw.Text(
                '${context.pageNumber} / ${context.pagesCount}',
                style: _style(regular, size: 7.5, color: PdfColors.grey600),
              ),
            ],
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#1E3A8A'),
              borderRadius: pw.BorderRadius.circular(7),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  _rtl(marketTitle),
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                  style: _style(bold, size: 22, color: PdfColors.white),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  _rtl('کەشفی حیسابی کڕیار'),
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                  style: _style(regular, size: 11, color: PdfColor.fromHex('#DBEAFE')),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              pw.Expanded(
                child: _labelValue(
                  label: 'ناوی کڕیار',
                  value: customerName.trim().isEmpty ? '—' : customerName.trim(),
                  regular: regular,
                  bold: bold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _labelValue(
                  label: 'بەروار و کات',
                  value: '$generatedDate  $generatedTime',
                  regular: regular,
                  bold: bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Row(
            children: [
              pw.Expanded(
                child: _labelValue(
                  label: 'بەڕێوەبەر',
                  value: managerTitle,
                  regular: regular,
                  bold: bold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _labelValue(
                  label: 'ژمارەی پەیوەندی',
                  value: adminPhone.trim().isEmpty ? '—' : adminPhone.trim(),
                  regular: regular,
                  bold: bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              _summaryBox(
                title: 'کۆی قەرز',
                value: _money(totalDebt, 'IQD'),
                accent: PdfColor.fromHex('#1D4ED8'),
                regular: regular,
                bold: bold,
              ),
              pw.SizedBox(width: 8),
              _summaryBox(
                title: 'دراوەتەوە',
                value: _money(totalPaid, 'IQD'),
                accent: PdfColor.fromHex('#15803D'),
                regular: regular,
                bold: bold,
              ),
              pw.SizedBox(width: 8),
              _summaryBox(
                title: 'ماوە',
                value: _money(totalRemaining, 'IQD'),
                accent: PdfColor.fromHex('#B91C1C'),
                regular: regular,
                bold: bold,
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _rtl('قەرزە چالاکەکان'),
                textDirection: pw.TextDirection.rtl,
                style: _style(bold, size: 13, color: PdfColor.fromHex('#0F172A')),
              ),
              pw.Text(
                _rtl('${activeDebts.length} تۆمار'),
                textDirection: pw.TextDirection.rtl,
                style: _style(regular, size: 9, color: PdfColor.fromHex('#64748B')),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          if (activeDebts.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(24),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F0FDF4'),
                border: pw.Border.all(color: PdfColor.fromHex('#86EFAC')),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                _rtl('هیچ قەرزێکی چالاک نییە'),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
                style: _style(bold, size: 11, color: PdfColor.fromHex('#166534')),
              ),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromHex('#CBD5E1'), width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(0.45),
                1: pw.FlexColumnWidth(2.0),
                2: pw.FlexColumnWidth(1.15),
                3: pw.FlexColumnWidth(1.2),
                4: pw.FlexColumnWidth(1.35),
                5: pw.FlexColumnWidth(1.35),
                6: pw.FlexColumnWidth(1.2),
              },
              children: [
                _headerRow(bold),
                for (var index = 0; index < activeDebts.length; index++)
                  _debtRow(activeDebts[index], index, regular),
              ],
            ),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF7ED'),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColor.fromHex('#FDBA74'), width: 0.6),
            ),
            child: pw.Text(
              _rtl(
                'ئەم کەشفە بەپێی زانیارییە تۆمارکراوەکانی سیستەمی ژیرۆکس '
                'لە کاتی دەرکردنی بەڵگەنامەکە دروست کراوە.',
              ),
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
              style: _style(regular, size: 8.5, color: PdfColor.fromHex('#9A3412')),
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Text(
                    _rtl('واژووی بەڕێوەبەر'),
                    textDirection: pw.TextDirection.rtl,
                    style: _style(regular, size: 8.5, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(width: 120, height: 0.6, color: PdfColors.grey500),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text(
                    _rtl('واژووی کڕیار'),
                    textDirection: pw.TextDirection.rtl,
                    style: _style(regular, size: 8.5, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(width: 120, height: 0.6, color: PdfColors.grey500),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final safeName = customerName
        .trim()
        .replaceAll(RegExp(r'[^\u0600-\u06FFa-zA-Z0-9_-]+'), '_');
    await Printing.layoutPdf(
      name: 'Zhirox_Statement_${safeName.isEmpty ? 'Customer' : safeName}_$generatedDate',
      onLayout: (_) => document.save(),
    );
  }
}
