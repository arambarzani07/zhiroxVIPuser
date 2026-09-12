import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pocketbase/pocketbase.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zhirox/services/receipt_document_service.dart';
import 'package:zhirox/services/receipt_settings_service.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/utils/kurdish_reshaper.dart';

class _ResolvedPaymentReceipt {
  final MarketReceiptSettings settings;
  final String receiptNumber;

  const _ResolvedPaymentReceipt({
    required this.settings,
    required this.receiptNumber,
  });
}

class PaymentReceiptService {
  PaymentReceiptService._();

  static String _r(String value) => KurdishReshaper.convert(value);

  static PdfColor _brandColor(String hex) {
    final clean = hex.replaceAll('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0x0F766E;
    return PdfColor(
      ((value >> 16) & 0xff) / 255,
      ((value >> 8) & 0xff) / 255,
      (value & 0xff) / 255,
    );
  }

  static String _label(String key, String mode) {
    const labels = <String, List<String>>{
      'title': ['پسوولەی پارەدانەوە', 'وصل دفعة', 'Payment receipt'],
      'receipt_no': ['ژمارەی پسوولە', 'رقم الوصل', 'Receipt No.'],
      'date': ['بەروار', 'التاريخ', 'Date'],
      'customer': ['کڕیار', 'الزبون', 'Customer'],
      'customer_phone': ['مۆبایل', 'الهاتف', 'Phone'],
      'manager': ['بەڕێوەبەر', 'المدير', 'Manager'],
      'debt': ['بابەتی قەرز', 'بيان الدين', 'Debt'],
      'paid': ['بڕی پارەدان', 'المبلغ المدفوع', 'Amount paid'],
      'remaining': ['ماوەی قەرز', 'المتبقي', 'Remaining'],
      'method': ['جۆری پارەدان', 'طريقة الدفع', 'Payment method'],
      'note': ['تێبینی', 'ملاحظة', 'Note'],
      'stamp': ['مۆر / واژۆی مارکێت', 'ختم / توقيع السوق', 'Market stamp / signature'],
    };
    final values = labels[key] ?? <String>[key, key, key];
    switch (mode) {
      case 'ar':
        return values[1];
      case 'en':
        return values[2];
      case 'ku_ar':
        return '${values[0]} / ${values[1]}';
      case 'ku_en':
        return '${values[0]} / ${values[2]}';
      default:
        return values[0];
    }
  }

  static String _paymentMethodName(String code, String mode) {
    const names = <String, List<String>>{
      'cash': ['نەقد', 'نقدي', 'Cash'],
      'fib': ['FIB', 'FIB', 'FIB'],
      'transfer': ['حەواڵە', 'حوالة', 'Transfer'],
      'card': ['کارت', 'بطاقة', 'Card'],
      'debt': ['قەرز', 'دين', 'Debt'],
    };
    final values = names[code] ?? names['cash']!;
    switch (mode) {
      case 'ar':
        return values[1];
      case 'en':
        return values[2];
      case 'ku_ar':
        return '${values[0]} / ${values[1]}';
      case 'ku_en':
        return '${values[0]} / ${values[2]}';
      default:
        return values[0];
    }
  }

  static String _paymentMethodCode(
    RecordModel payment,
    MarketReceiptSettings settings,
  ) {
    final reference = payment.getStringValue('reference_kind').trim().toLowerCase();
    for (final code in const ['fib', 'card', 'transfer', 'cash']) {
      if (reference.contains(code)) return code;
    }
    final configured = settings.defaultPaymentMethod.trim().toLowerCase();
    if (const {'fib', 'card', 'transfer', 'cash'}.contains(configured)) {
      return configured;
    }
    return 'cash';
  }

  static String _fallbackNumber(String id) {
    final shortId = id.length > 6 ? id.substring(id.length - 6) : id;
    return 'PAY-${shortId.toUpperCase()}';
  }

  static Future<_ResolvedPaymentReceipt> _resolve({
    required RecordModel payment,
    required MarketReceiptSettings settings,
  }) async {
    if (settings.adminId.isEmpty) {
      return _ResolvedPaymentReceipt(
        settings: settings,
        receiptNumber: _fallbackNumber(payment.id),
      );
    }
    try {
      final version = await ReceiptDocumentService.ensure(
        adminId: settings.adminId,
        sourceType: 'payment',
        sourceId: payment.id,
        currentSettings: settings,
      );
      return _ResolvedPaymentReceipt(
        settings: version.settings,
        receiptNumber: version.receiptNumber.trim().isEmpty
            ? _fallbackNumber(payment.id)
            : version.receiptNumber.trim(),
      );
    } catch (_) {
      return _ResolvedPaymentReceipt(
        settings: settings,
        receiptNumber: _fallbackNumber(payment.id),
      );
    }
  }

  static String _money(RecordModel debt, double storedAmount) {
    final currency = debt.getStringValue('currency').trim().toUpperCase();
    return AppHelpers.formatStoredFinancialAmount(
      storedAmount,
      currency.isEmpty ? 'IQD' : currency,
      dollarRate: debt.getDoubleValue('dollar_rate'),
      showConversion: true,
    );
  }

  static Future<Uint8List> buildPaymentReceiptBytes({
    required RecordModel payment,
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final resolved = await _resolve(payment: payment, settings: settings);
    final active = resolved.settings;
    final fontData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final font = pw.Font.ttf(fontData);
    final bold = pw.Font.ttf(boldData);

    final logoBytes = await ReceiptSettingsService.loadBrandAsset(active.logoPath);
    final stampBytes = await ReceiptSettingsService.loadBrandAsset(active.stampPath);
    final signatureBytes = await ReceiptSettingsService.loadBrandAsset(active.signaturePath);

    final customer = AppHelpers.expandedRecord(debt, 'customer');
    final customerName = customer?.getStringValue('name').trim() ?? '';
    final customerPhone = customer?.getStringValue('phone').trim() ?? '';
    final description = debt.getStringValue('description').trim();
    final paymentNote = payment.getStringValue('note').trim();
    final paymentAmount = payment.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final createdRaw = payment.getStringValue('created').trim();
    final created = createdRaw.isEmpty
        ? DateTime.now().toLocal().toString().substring(0, 16)
        : AppHelpers.formatDateTime(createdRaw);
    final language = active.languageMode;
    final method = _paymentMethodName(
      _paymentMethodCode(payment, active),
      language,
    );

    final is58 = active.paperSize == 'thermal58';
    final is80 = active.paperSize == 'thermal80';
    final isThermal = is58 || is80;
    final widthMm = is58 ? 58.0 : 80.0;
    final pageFormat = isThermal
        ? PdfPageFormat(
            widthMm * PdfPageFormat.mm,
            260 * PdfPageFormat.mm,
            marginAll: active.marginMm * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;
    final baseFontSize = (is58 ? 6.8 : is80 ? 8.2 : 10.0) * active.fontScale;
    final brand = _brandColor(active.primaryColor);
    final modern = active.templateFor('payment') == 'modern';
    final phone = active.phone.trim().isNotEmpty
        ? active.phone.trim()
        : fallbackPhone.trim();
    final headerAlignment = active.headerAlignment == 'start'
        ? pw.Alignment.centerRight
        : active.headerAlignment == 'end'
            ? pw.Alignment.centerLeft
            : pw.Alignment.center;

    pw.Widget infoLine(String label, String value, {bool ltr = false, bool strong = false}) {
      if (value.trim().isEmpty) return pw.SizedBox.shrink();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: isThermal ? 66 : 125,
              child: pw.Text(
                _r(label),
                style: pw.TextStyle(font: bold, fontSize: baseFontSize),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: pw.Text(
                ltr ? value : _r(value),
                textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
                textAlign: pw.TextAlign.left,
                style: pw.TextStyle(
                  font: strong ? bold : font,
                  fontSize: strong ? baseFontSize * 1.12 : baseFontSize,
                ),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget header() {
      final details = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logoBytes != null) ...[
            pw.Image(
              pw.MemoryImage(logoBytes),
              width: isThermal ? 42 : 66,
              height: isThermal ? 42 : 66,
              fit: pw.BoxFit.contain,
            ),
            pw.SizedBox(height: 5),
          ],
          pw.Text(
            _r(marketName.trim().isEmpty ? 'ZHIROX' : marketName.trim()),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold,
              fontSize: (isThermal ? 14 : 22) * active.fontScale,
              color: modern ? PdfColors.white : PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _r(_label('title', language)),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold,
              fontSize: (isThermal ? 10 : 14) * active.fontScale,
              color: modern ? PdfColors.white : brand,
            ),
          ),
          if (active.address.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              _r(active.address.trim()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: font,
                fontSize: baseFontSize,
                color: modern ? PdfColors.white : PdfColors.black,
              ),
            ),
          ],
          if (phone.isNotEmpty || active.secondaryPhone.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              [
                if (phone.isNotEmpty) phone,
                if (active.secondaryPhone.trim().isNotEmpty)
                  active.secondaryPhone.trim(),
              ].join(' / '),
              textDirection: pw.TextDirection.ltr,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: font,
                fontSize: baseFontSize,
                color: modern ? PdfColors.white : PdfColors.black,
              ),
            ),
          ],
        ],
      );

      return pw.Container(
        width: double.infinity,
        alignment: headerAlignment,
        padding: pw.EdgeInsets.all(modern ? (isThermal ? 8 : 14) : 0),
        decoration: modern
            ? pw.BoxDecoration(
                color: brand,
                borderRadius: pw.BorderRadius.circular(isThermal ? 4 : 10),
              )
            : null,
        child: details,
      );
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: isThermal
            ? const pw.EdgeInsets.all(0)
            : pw.EdgeInsets.all(active.marginMm * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          header(),
          pw.SizedBox(height: isThermal ? 7 : 14),
          infoLine(_label('receipt_no', language), resolved.receiptNumber, ltr: true),
          infoLine(_label('date', language), created),
          infoLine(
            _label('customer', language),
            customerName.isEmpty ? 'نەناسراو' : customerName,
          ),
          if (active.showCustomerPhone && customerPhone.isNotEmpty)
            infoLine(_label('customer_phone', language), customerPhone, ltr: true),
          if (active.showAdminName && adminName.trim().isNotEmpty)
            infoLine(_label('manager', language), adminName.trim()),
          if (description.isNotEmpty)
            infoLine(_label('debt', language), description),
          infoLine(_label('method', language), method),
          for (final field in active.customFields)
            infoLine(field['label'] ?? '', field['value'] ?? ''),
          pw.SizedBox(height: isThermal ? 6 : 10),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(isThermal ? 7 : 12),
            decoration: pw.BoxDecoration(
              color: modern ? PdfColor(0.96, 0.98, 0.98) : PdfColors.white,
              border: pw.Border.all(color: modern ? brand : PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              children: [
                infoLine(
                  _label('paid', language),
                  _money(debt, paymentAmount),
                  strong: true,
                ),
                infoLine(
                  _label('remaining', language),
                  _money(debt, remaining),
                ),
              ],
            ),
          ),
          if (paymentNote.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            infoLine(_label('note', language), paymentNote),
          ],
          pw.SizedBox(height: isThermal ? 12 : 22),
          pw.Center(
            child: pw.Column(
              children: [
                if (stampBytes != null || signatureBytes != null)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      if (stampBytes != null)
                        pw.Image(
                          pw.MemoryImage(stampBytes),
                          width: isThermal ? 44 : 66,
                          height: isThermal ? 44 : 66,
                          fit: pw.BoxFit.contain,
                        ),
                      if (stampBytes != null && signatureBytes != null)
                        pw.SizedBox(width: 8),
                      if (signatureBytes != null)
                        pw.Image(
                          pw.MemoryImage(signatureBytes),
                          width: isThermal ? 44 : 66,
                          height: isThermal ? 34 : 48,
                          fit: pw.BoxFit.contain,
                        ),
                    ],
                  )
                else ...[
                  pw.Text(
                    _r(_label('stamp', language)),
                    style: pw.TextStyle(font: bold, fontSize: baseFontSize * 0.9),
                  ),
                  pw.SizedBox(height: isThermal ? 14 : 24),
                  pw.Container(width: isThermal ? 100 : 160, height: 1, color: PdfColors.grey600),
                ],
              ],
            ),
          ),
          if (active.showQr || active.showBarcode) ...[
            pw.SizedBox(height: isThermal ? 9 : 15),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                if (active.showQr)
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data:
                        'ZHIROX|PAYMENT|${resolved.receiptNumber}|${payment.id}|${paymentAmount.toStringAsFixed(2)}',
                    width: isThermal ? 48 : 64,
                    height: isThermal ? 48 : 64,
                  ),
                if (active.showQr && active.showBarcode)
                  pw.SizedBox(width: 12),
                if (active.showBarcode)
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: resolved.receiptNumber,
                    width: isThermal ? 92 : 150,
                    height: isThermal ? 34 : 45,
                    drawText: true,
                    textStyle: pw.TextStyle(font: font, fontSize: baseFontSize * 0.7),
                  ),
              ],
            ),
          ],
          pw.SizedBox(height: isThermal ? 7 : 14),
          pw.Divider(color: modern ? brand : PdfColors.grey400),
          pw.Center(
            child: pw.Text(
              _r(active.footerNote.trim().isEmpty
                  ? 'سوپاس بۆ مامەڵەکردنتان'
                  : active.footerNote.trim()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: baseFontSize * 0.88),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              'ZHIROX • ${resolved.receiptNumber}',
              textDirection: pw.TextDirection.ltr,
              style: pw.TextStyle(
                font: font,
                fontSize: baseFontSize * 0.65,
                color: PdfColors.grey600,
              ),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static Future<String> _number({
    required RecordModel payment,
    required MarketReceiptSettings settings,
  }) async {
    final resolved = await _resolve(payment: payment, settings: settings);
    return resolved.receiptNumber;
  }

  static Future<void> generatePaymentReceipt({
    required RecordModel payment,
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final bytes = await buildPaymentReceiptBytes(
      payment: payment,
      debt: debt,
      marketName: marketName,
      adminName: adminName,
      fallbackPhone: fallbackPhone,
      settings: settings,
    );
    final number = await _number(payment: payment, settings: settings);
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Payment_$number',
    );
  }

  static Future<void> sharePaymentReceiptPdf({
    required RecordModel payment,
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final bytes = await buildPaymentReceiptBytes(
      payment: payment,
      debt: debt,
      marketName: marketName,
      adminName: adminName,
      fallbackPhone: fallbackPhone,
      settings: settings,
    );
    final number = await _number(payment: payment, settings: settings);
    await Printing.sharePdf(bytes: bytes, filename: 'Payment_$number.pdf');
  }

  static Future<void> sharePaymentReceiptImage({
    required RecordModel payment,
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final bytes = await buildPaymentReceiptBytes(
      payment: payment,
      debt: debt,
      marketName: marketName,
      adminName: adminName,
      fallbackPhone: fallbackPhone,
      settings: settings,
    );
    final number = await _number(payment: payment, settings: settings);
    final raster = await Printing.raster(bytes, pages: const [0], dpi: 144).first;
    final png = await raster.toPng();
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/Payment_$number.png');
    await file.writeAsBytes(png, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: '$marketName • $number',
    );
  }
}
