import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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

class _ReceiptItem {
  final String name;
  final int qty;
  final double price;
  final String currency;

  const _ReceiptItem({
    required this.name,
    required this.qty,
    required this.price,
    required this.currency,
  });
}

class _ReceiptData {
  final String sourceId;
  final String receiptNumber;
  final String customerName;
  final String customerPhone;
  final String created;
  final String dueDate;
  final String description;
  final String status;
  final String currency;
  final double dollarRate;
  final double amount;
  final double paid;
  final double remaining;
  final List<_ReceiptItem> items;

  const _ReceiptData({
    required this.sourceId,
    required this.receiptNumber,
    required this.customerName,
    required this.customerPhone,
    required this.created,
    required this.dueDate,
    required this.description,
    required this.status,
    required this.currency,
    required this.dollarRate,
    required this.amount,
    required this.paid,
    required this.remaining,
    required this.items,
  });

  _ReceiptData copyWith({String? receiptNumber}) => _ReceiptData(
        sourceId: sourceId,
        receiptNumber: receiptNumber ?? this.receiptNumber,
        customerName: customerName,
        customerPhone: customerPhone,
        created: created,
        dueDate: dueDate,
        description: description,
        status: status,
        currency: currency,
        dollarRate: dollarRate,
        amount: amount,
        paid: paid,
        remaining: remaining,
        items: items,
      );
}

class OfficialReceiptService {
  OfficialReceiptService._();

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

  static String _itemMoney(double amount, String currency) {
    if (currency.trim().toUpperCase() == 'USD') {
      return '\$${NumberFormat('#,##0.00', 'en').format(amount)}';
    }
    return '${NumberFormat('#,###', 'en').format(amount)} د.ع';
  }

  static String _label(String key, String mode) {
    const labels = <String, List<String>>{
      'receipt_no': ['ژمارەی پسوولە', 'رقم الوصل', 'Receipt No.'],
      'date': ['بەروار', 'التاريخ', 'Date'],
      'customer': ['کڕیار', 'الزبون', 'Customer'],
      'customer_phone': ['مۆبایلی کڕیار', 'هاتف الزبون', 'Customer phone'],
      'due': ['بەرواری دانەوە', 'تاريخ الاستحقاق', 'Due date'],
      'admin': ['بەڕێوەبەر', 'المدير', 'Manager'],
      'item': ['کاڵا', 'المادة', 'Item'],
      'qty': ['دانە', 'العدد', 'Qty'],
      'price': ['نرخ', 'السعر', 'Price'],
      'line_total': ['کۆ', 'المجموع', 'Total'],
      'total': ['کۆی گشتی', 'المجموع الكلي', 'Grand total'],
      'paid': ['پارەی وەرگیراو', 'المبلغ المستلم', 'Paid'],
      'remaining': ['ماوەی قەرز', 'المتبقي', 'Remaining'],
      'status': ['دۆخ', 'الحالة', 'Status'],
      'note': ['تێبینی', 'ملاحظة', 'Note'],
      'payment_method': ['جۆری پارەدان', 'طريقة الدفع', 'Payment method'],
      'vat': ['باج / VAT', 'الضريبة / VAT', 'VAT'],
      'discount': ['داشکاندن', 'الخصم', 'Discount'],
      'customer_signature': ['واژۆی کڕیار', 'توقيع الزبون', 'Customer signature'],
      'market_stamp': ['مۆر / واژۆی مارکێت', 'ختم / توقيع السوق', 'Market stamp / signature'],
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
      case 'ku':
      default:
        return values[0];
    }
  }

  static String _paymentMethod(String value, String mode) {
    const names = <String, List<String>>{
      'cash': ['نەقد', 'نقدي', 'Cash'],
      'fib': ['FIB', 'FIB', 'FIB'],
      'transfer': ['حەواڵە', 'حوالة', 'Transfer'],
      'card': ['کارت', 'بطاقة', 'Card'],
      'debt': ['قەرز', 'دين', 'Debt'],
    };
    final values = names[value] ?? names['debt']!;
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

  static _ReceiptData _dataFromDebt(RecordModel debt) {
    final currency = debt.getStringValue('currency').trim().toUpperCase();
    final dollarRate = debt.getDoubleValue('dollar_rate');
    final amount = debt.getDoubleValue('amount');
    final remaining = debt.getDoubleValue('remaining');
    final paid = amount - remaining;
    final description = debt.getStringValue('description').trim();
    final status = debt.getStringValue('status');
    final customDate = debt.getStringValue('custom_date').trim();
    final createdRaw =
        customDate.isNotEmpty ? customDate : debt.getStringValue('created');
    final dueRaw = debt.getStringValue('due_date').trim();
    final customer = AppHelpers.expandedRecord(debt, 'customer');
    final customerName = customer?.getStringValue('name').trim() ?? '';
    final customerPhone = customer?.getStringValue('phone').trim() ?? '';
    final items = <_ReceiptItem>[];

    try {
      final raw = debt.data['items'];
      dynamic decoded = raw;
      if (raw is String && raw.trim().isNotEmpty && raw.trim() != '[]') {
        decoded = jsonDecode(raw);
      }
      if (decoded is List) {
        for (final entry in decoded.whereType<Map>()) {
          final item = Map<String, dynamic>.from(entry);
          final name = item['name']?.toString().trim() ?? '';
          final qty = item['qty'] is num
              ? (item['qty'] as num).toInt()
              : int.tryParse('${item['qty'] ?? 1}') ?? 1;
          final price = item['price'] is num
              ? (item['price'] as num).toDouble()
              : double.tryParse('${item['price'] ?? 0}') ?? 0;
          final itemCurrency =
              (item['currency']?.toString().trim().isNotEmpty ?? false)
                  ? item['currency'].toString().trim().toUpperCase()
                  : currency;
          items.add(_ReceiptItem(
            name: name.isEmpty ? 'کاڵا' : name,
            qty: qty,
            price: price,
            currency: itemCurrency,
          ));
        }
      }
    } catch (_) {}

    final shortId = debt.id.length > 6
        ? debt.id.substring(debt.id.length - 6).toUpperCase()
        : debt.id.toUpperCase();

    return _ReceiptData(
      sourceId: debt.id,
      receiptNumber: shortId,
      customerName: customerName,
      customerPhone: customerPhone,
      created: AppHelpers.formatDateTime(createdRaw),
      dueDate: dueRaw.isEmpty ? '-' : AppHelpers.formatDate(dueRaw),
      description: description,
      status: status,
      currency: currency,
      dollarRate: dollarRate,
      amount: amount,
      paid: paid,
      remaining: remaining,
      items: items,
    );
  }

  static Future<({MarketReceiptSettings settings, _ReceiptData data})>
      _resolveVersion({
    required RecordModel debt,
    required MarketReceiptSettings settings,
  }) async {
    final baseData = _dataFromDebt(debt);
    if (settings.adminId.isEmpty) return (settings: settings, data: baseData);
    try {
      final version = await ReceiptDocumentService.ensure(
        adminId: settings.adminId,
        sourceType: 'debt',
        sourceId: debt.id,
        currentSettings: settings,
      );
      return (
        settings: version.settings,
        data: baseData.copyWith(receiptNumber: version.receiptNumber),
      );
    } catch (_) {
      return (settings: settings, data: baseData);
    }
  }

  static Future<Uint8List> buildDebtReceiptBytes({
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final resolved = await _resolveVersion(debt: debt, settings: settings);
    return _buildReceiptBytes(
      data: resolved.data,
      marketName: marketName,
      adminName: adminName,
      fallbackPhone: fallbackPhone,
      settings: resolved.settings,
      documentType: 'debt',
    );
  }

  static Future<Uint8List> buildSettingsPreview({
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) {
    final year = DateTime.now().year;
    final data = _ReceiptData(
      sourceId: 'preview',
      receiptNumber: '${settings.receiptPrefix}-$year-000123',
      customerName: 'نموونەی کڕیار',
      customerPhone: '0750 000 0000',
      created: DateFormat('yyyy/MM/dd  HH:mm').format(DateTime.now()),
      dueDate: DateFormat('yyyy/MM/dd').format(
        DateTime.now().add(const Duration(days: 30)),
      ),
      description: 'نموونەی پسوولەی فەرمی',
      status: 'partial',
      currency: 'IQD',
      dollarRate: 0,
      amount: 125000,
      paid: 50000,
      remaining: 75000,
      items: const [
        _ReceiptItem(name: 'کاڵای یەکەم', qty: 2, price: 25000, currency: 'IQD'),
        _ReceiptItem(name: 'کاڵای دووەم', qty: 1, price: 75000, currency: 'IQD'),
      ],
    );
    return _buildReceiptBytes(
      data: data,
      marketName: marketName.isEmpty ? 'ناوی مارکێت' : marketName,
      adminName: adminName.isEmpty ? 'بەڕێوەبەر' : adminName,
      fallbackPhone: fallbackPhone,
      settings: settings,
      documentType: 'debt',
    );
  }

  static Future<void> generateDebtReceipt({
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final bytes = await buildDebtReceiptBytes(
      debt: debt,
      marketName: marketName,
      adminName: adminName,
      fallbackPhone: fallbackPhone,
      settings: settings,
    );
    final number = _dataFromDebt(debt).receiptNumber;
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Receipt_$number',
    );
  }

  static Future<void> shareDebtReceiptPdf({
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final resolved = await _resolveVersion(debt: debt, settings: settings);
    final bytes = await _buildReceiptBytes(
      data: resolved.data,
      marketName: marketName,
      adminName: adminName,
      fallbackPhone: fallbackPhone,
      settings: resolved.settings,
      documentType: 'debt',
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Receipt_${resolved.data.receiptNumber}.pdf',
    );
  }

  static Future<void> shareDebtReceiptImage({
    required RecordModel debt,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
  }) async {
    final resolved = await _resolveVersion(debt: debt, settings: settings);
    final bytes = await _buildReceiptBytes(
      data: resolved.data,
      marketName: marketName,
      adminName: adminName,
      fallbackPhone: fallbackPhone,
      settings: resolved.settings,
      documentType: 'debt',
    );
    final raster = await Printing.raster(
      bytes,
      pages: const [0],
      dpi: 144,
    ).first;
    final png = await raster.toPng();
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/Receipt_${resolved.data.receiptNumber}.png',
    );
    await file.writeAsBytes(png, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: '$marketName • ${resolved.data.receiptNumber}',
    );
  }

  static Future<Uint8List> _buildReceiptBytes({
    required _ReceiptData data,
    required String marketName,
    required String adminName,
    required String fallbackPhone,
    required MarketReceiptSettings settings,
    required String documentType,
  }) async {
    final fontData = await rootBundle.load('assets/fonts/NotoKufiArabic.ttf');
    final boldData =
        await rootBundle.load('assets/fonts/NotoKufiArabic-Bold.ttf');
    final font = pw.Font.ttf(fontData);
    final bold = pw.Font.ttf(boldData);

    final logoBytes = await ReceiptSettingsService.loadBrandAsset(settings.logoPath);
    final stampBytes =
        await ReceiptSettingsService.loadBrandAsset(settings.stampPath);
    final signatureBytes =
        await ReceiptSettingsService.loadBrandAsset(settings.signaturePath);

    final phone = settings.phone.trim().isNotEmpty
        ? settings.phone.trim()
        : fallbackPhone.trim();
    final is58 = settings.paperSize == 'thermal58';
    final is80 = settings.paperSize == 'thermal80';
    final isThermal = is58 || is80;
    final widthMm = is58 ? 58.0 : 80.0;
    final pageFormat = isThermal
        ? PdfPageFormat(
            widthMm * PdfPageFormat.mm,
            320 * PdfPageFormat.mm,
            marginAll: settings.marginMm * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;
    final baseFontSize = (is58 ? 6.8 : is80 ? 8.2 : 10.0) * settings.fontScale;
    final brand = _brandColor(settings.primaryColor);
    final template = settings.templateFor(documentType);
    final modern = template == 'modern';
    final language = settings.languageMode;
    final headerAlignment = settings.headerAlignment == 'start'
        ? pw.Alignment.centerRight
        : settings.headerAlignment == 'end'
            ? pw.Alignment.centerLeft
            : pw.Alignment.center;

    pw.Widget infoLine(String label, String value, {bool ltr = false}) {
      if (value.trim().isEmpty) return pw.SizedBox.shrink();
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
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

    final itemRows = data.items
        .map((item) => [
              _r(item.name),
              item.qty.toString(),
              _r(_itemMoney(item.price, item.currency)),
              _r(_itemMoney(item.price * item.qty, item.currency)),
            ])
        .toList(growable: false);

    final totalText = AppHelpers.formatStoredFinancialAmount(
      data.amount,
      data.currency,
      dollarRate: data.dollarRate,
      showConversion: true,
    );
    final paidText = AppHelpers.formatStoredFinancialAmount(
      data.paid,
      data.currency,
      dollarRate: data.dollarRate,
      showConversion: true,
    );
    final remainingText = AppHelpers.formatStoredFinancialAmount(
      data.remaining,
      data.currency,
      dollarRate: data.dollarRate,
      showConversion: true,
    );

    pw.Widget brandingHeader() {
      final details = pw.Column(
        crossAxisAlignment: settings.headerAlignment == 'start'
            ? pw.CrossAxisAlignment.end
            : settings.headerAlignment == 'end'
                ? pw.CrossAxisAlignment.start
                : pw.CrossAxisAlignment.center,
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
            _r(marketName),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold,
              fontSize: (isThermal ? 15 : 23) * settings.fontScale,
              color: modern ? PdfColors.white : PdfColors.black,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            _r(settings.receiptTitle),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: bold,
              fontSize: (isThermal ? 10 : 14) * settings.fontScale,
              color: modern ? PdfColors.white : brand,
            ),
          ),
          if (settings.address.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              _r(settings.address.trim()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: font,
                fontSize: baseFontSize,
                color: modern ? PdfColors.white : PdfColors.black,
              ),
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
              style: pw.TextStyle(
                font: font,
                fontSize: baseFontSize,
                color: modern ? PdfColors.white : PdfColors.black,
              ),
            ),
          ],
          if (settings.registrationNo.trim().isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(
              _r('ژمارەی تۆمار: ${settings.registrationNo.trim()}'),
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

      if (!modern) {
        return pw.Container(
          alignment: headerAlignment,
          width: double.infinity,
          child: details,
        );
      }
      return pw.Container(
        alignment: headerAlignment,
        width: double.infinity,
        padding: pw.EdgeInsets.all(isThermal ? 8 : 14),
        decoration: pw.BoxDecoration(
          color: brand,
          borderRadius: pw.BorderRadius.circular(isThermal ? 4 : 10),
        ),
        child: details,
      );
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: isThermal
            ? const pw.EdgeInsets.all(0)
            : pw.EdgeInsets.all(settings.marginMm * PdfPageFormat.mm),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        textDirection: pw.TextDirection.rtl,
        build: (_) => [
          brandingHeader(),
          pw.SizedBox(height: isThermal ? 7 : 13),
          pw.Divider(color: modern ? brand : PdfColors.grey500),
          infoLine(_label('receipt_no', language), data.receiptNumber, ltr: true),
          infoLine(_label('date', language), data.created),
          infoLine(
            _label('customer', language),
            data.customerName.isEmpty ? 'نەناسراو' : data.customerName,
          ),
          if (settings.showCustomerPhone && data.customerPhone.isNotEmpty)
            infoLine(
              _label('customer_phone', language),
              data.customerPhone,
              ltr: true,
            ),
          infoLine(_label('due', language), data.dueDate),
          if (settings.showAdminName && adminName.trim().isNotEmpty)
            infoLine(_label('admin', language), adminName.trim()),
          infoLine(
            _label('payment_method', language),
            _paymentMethod(settings.defaultPaymentMethod, language),
          ),
          for (final field in settings.customFields)
            infoLine(field['label'] ?? '', field['value'] ?? ''),
          pw.SizedBox(height: isThermal ? 5 : 9),
          if (itemRows.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headers: [
                _r(_label('item', language)),
                _r(_label('qty', language)),
                _r(_label('price', language)),
                _r(_label('line_total', language)),
              ],
              data: itemRows,
              headerStyle: pw.TextStyle(
                font: bold,
                fontSize: isThermal ? baseFontSize * 0.82 : baseFontSize * 0.9,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: modern ? brand : PdfColors.grey800),
              cellStyle: pw.TextStyle(
                font: font,
                fontSize: isThermal ? baseFontSize * 0.76 : baseFontSize * 0.86,
              ),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            )
          else
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: modern ? brand : PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                _r(data.description.isEmpty ? 'قەرزی ڕاستەوخۆ' : data.description),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: font, fontSize: baseFontSize),
              ),
            ),
          pw.SizedBox(height: isThermal ? 7 : 13),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.all(isThermal ? 6 : 11),
            decoration: pw.BoxDecoration(
              color: modern ? PdfColor(0.96, 0.98, 0.98) : PdfColors.white,
              border: pw.Border.all(color: modern ? brand : PdfColors.grey500),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              children: [
                infoLine(_label('total', language), totalText),
                if (settings.discountPercent > 0)
                  infoLine(
                    _label('discount', language),
                    '${settings.discountPercent.toStringAsFixed(2)}%',
                    ltr: true,
                  ),
                if (settings.vatPercent > 0)
                  infoLine(
                    _label('vat', language),
                    '${settings.vatPercent.toStringAsFixed(2)}%',
                    ltr: true,
                  ),
                infoLine(_label('paid', language), paidText),
                infoLine(_label('remaining', language), remainingText),
                infoLine(_label('status', language), AppHelpers.statusName(data.status)),
              ],
            ),
          ),
          if (data.description.isNotEmpty && itemRows.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            infoLine(_label('note', language), data.description),
          ],
          pw.SizedBox(height: isThermal ? 10 : 20),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (!is58)
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        _r(_label('customer_signature', language)),
                        style: pw.TextStyle(font: bold, fontSize: baseFontSize * 0.85),
                      ),
                      pw.SizedBox(height: isThermal ? 12 : 22),
                      pw.Container(height: 1, color: PdfColors.grey600),
                    ],
                  ),
                ),
              if (!is58) pw.SizedBox(width: 16),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    if (stampBytes != null || signatureBytes != null)
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          if (stampBytes != null)
                            pw.Image(
                              pw.MemoryImage(stampBytes),
                              width: isThermal ? 40 : 62,
                              height: isThermal ? 40 : 62,
                              fit: pw.BoxFit.contain,
                            ),
                          if (stampBytes != null && signatureBytes != null)
                            pw.SizedBox(width: 6),
                          if (signatureBytes != null)
                            pw.Image(
                              pw.MemoryImage(signatureBytes),
                              width: isThermal ? 40 : 62,
                              height: isThermal ? 32 : 48,
                              fit: pw.BoxFit.contain,
                            ),
                        ],
                      )
                    else ...[
                      pw.Text(
                        _r(_label('market_stamp', language)),
                        style: pw.TextStyle(font: bold, fontSize: baseFontSize * 0.85),
                      ),
                      pw.SizedBox(height: isThermal ? 12 : 22),
                      pw.Container(height: 1, color: PdfColors.grey600),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (settings.showQr || settings.showBarcode) ...[
            pw.SizedBox(height: isThermal ? 8 : 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                if (settings.showQr)
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data:
                        'ZHIROX|${data.receiptNumber}|${data.sourceId}|${data.amount.toStringAsFixed(2)}',
                    width: isThermal ? 48 : 64,
                    height: isThermal ? 48 : 64,
                  ),
                if (settings.showQr && settings.showBarcode)
                  pw.SizedBox(width: 12),
                if (settings.showBarcode)
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: data.receiptNumber,
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
              _r(settings.footerNote.trim().isEmpty
                  ? 'سوپاس بۆ مامەڵەکردنتان'
                  : settings.footerNote.trim()),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: font, fontSize: baseFontSize * 0.88),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              'ZHIROX • ${data.receiptNumber}',
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
}
