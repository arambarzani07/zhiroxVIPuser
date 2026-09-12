import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class MarketReceiptSettings {
  final String adminId;
  final String receiptTitle;
  final String address;
  final String phone;
  final String secondaryPhone;
  final String registrationNo;
  final String footerNote;
  final String paperSize;
  final bool showCustomerPhone;
  final bool showAdminName;
  final String templateStyle;
  final String debtTemplate;
  final String paymentTemplate;
  final String purchaseTemplate;
  final String logoPath;
  final String stampPath;
  final String signaturePath;
  final String primaryColor;
  final double fontScale;
  final String headerAlignment;
  final bool showQr;
  final bool showBarcode;
  final String receiptPrefix;
  final double vatPercent;
  final double discountPercent;
  final String defaultPaymentMethod;
  final List<Map<String, String>> customFields;
  final double marginMm;
  final String languageMode;
  final int templateVersion;

  const MarketReceiptSettings({
    required this.adminId,
    required this.receiptTitle,
    required this.address,
    required this.phone,
    required this.secondaryPhone,
    required this.registrationNo,
    required this.footerNote,
    required this.paperSize,
    required this.showCustomerPhone,
    required this.showAdminName,
    required this.templateStyle,
    required this.debtTemplate,
    required this.paymentTemplate,
    required this.purchaseTemplate,
    required this.logoPath,
    required this.stampPath,
    required this.signaturePath,
    required this.primaryColor,
    required this.fontScale,
    required this.headerAlignment,
    required this.showQr,
    required this.showBarcode,
    required this.receiptPrefix,
    required this.vatPercent,
    required this.discountPercent,
    required this.defaultPaymentMethod,
    required this.customFields,
    required this.marginMm,
    required this.languageMode,
    required this.templateVersion,
  });

  factory MarketReceiptSettings.defaults({
    required String adminId,
    String marketName = '',
    String phone = '',
  }) {
    return MarketReceiptSettings(
      adminId: adminId,
      receiptTitle: 'پسوولەی فەرمی',
      address: '',
      phone: phone,
      secondaryPhone: '',
      registrationNo: '',
      footerNote: 'سوپاس بۆ مامەڵەکردنتان',
      paperSize: 'a4',
      showCustomerPhone: true,
      showAdminName: true,
      templateStyle: 'modern',
      debtTemplate: 'modern',
      paymentTemplate: 'classic',
      purchaseTemplate: 'modern',
      logoPath: '',
      stampPath: '',
      signaturePath: '',
      primaryColor: '#0F766E',
      fontScale: 1,
      headerAlignment: 'center',
      showQr: true,
      showBarcode: false,
      receiptPrefix: 'INV',
      vatPercent: 0,
      discountPercent: 0,
      defaultPaymentMethod: 'debt',
      customFields: const [],
      marginMm: 8,
      languageMode: 'ku',
      templateVersion: 1,
    );
  }

  factory MarketReceiptSettings.fromMap(
    Map<String, dynamic> row, {
    required String fallbackAdminId,
    String fallbackPhone = '',
  }) {
    String text(String key, [String fallback = '']) {
      final value = row[key]?.toString().trim() ?? '';
      return value.isEmpty ? fallback : value;
    }

    double number(String key, double fallback) {
      final value = row[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? fallback;
    }

    int integer(String key, int fallback) {
      final value = row[key];
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? fallback;
    }

    bool flag(String key, bool fallback) {
      final value = row[key];
      return value is bool ? value : fallback;
    }

    List<Map<String, String>> customFields() {
      final raw = row['custom_fields'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .map((entry) => {
                'label': entry['label']?.toString().trim() ?? '',
                'value': entry['value']?.toString().trim() ?? '',
              })
          .where((entry) => entry['label']!.isNotEmpty)
          .toList(growable: false);
    }

    final paper = text('paper_size', 'a4');
    final safePaper = const {'a4', 'thermal80', 'thermal58'}.contains(paper)
        ? paper
        : 'a4';
    final language = text('language_mode', 'ku');
    final safeLanguage = const {'ku', 'ar', 'en', 'ku_ar', 'ku_en'}
            .contains(language)
        ? language
        : 'ku';

    return MarketReceiptSettings(
      adminId: text('admin_id', fallbackAdminId),
      receiptTitle: text('receipt_title', 'پسوولەی فەرمی'),
      address: text('address'),
      phone: text('phone', fallbackPhone),
      secondaryPhone: text('secondary_phone'),
      registrationNo: text('registration_no'),
      footerNote: text('footer_note', 'سوپاس بۆ مامەڵەکردنتان'),
      paperSize: safePaper,
      showCustomerPhone: flag('show_customer_phone', true),
      showAdminName: flag('show_admin_name', true),
      templateStyle: text('template_style', 'modern'),
      debtTemplate: text('debt_template', 'modern'),
      paymentTemplate: text('payment_template', 'classic'),
      purchaseTemplate: text('purchase_template', 'modern'),
      logoPath: text('logo_path'),
      stampPath: text('stamp_path'),
      signaturePath: text('signature_path'),
      primaryColor: text('primary_color', '#0F766E'),
      fontScale: number('font_scale', 1).clamp(0.75, 1.5).toDouble(),
      headerAlignment: text('header_alignment', 'center'),
      showQr: flag('show_qr', true),
      showBarcode: flag('show_barcode', false),
      receiptPrefix: text('receipt_prefix', 'INV').toUpperCase(),
      vatPercent: number('vat_percent', 0).clamp(0, 100).toDouble(),
      discountPercent:
          number('discount_percent', 0).clamp(0, 100).toDouble(),
      defaultPaymentMethod: text('default_payment_method', 'debt'),
      customFields: customFields(),
      marginMm: number('margin_mm', 8).clamp(0, 30).toDouble(),
      languageMode: safeLanguage,
      templateVersion: integer('template_version', 1),
    );
  }

  factory MarketReceiptSettings.fromSnapshot(
    Map<String, dynamic> snapshot, {
    required String adminId,
  }) {
    return MarketReceiptSettings.fromMap(
      {...snapshot, 'admin_id': adminId},
      fallbackAdminId: adminId,
    );
  }

  String templateFor(String type) {
    switch (type) {
      case 'payment':
        return paymentTemplate;
      case 'purchase':
        return purchaseTemplate;
      case 'debt':
      default:
        return debtTemplate;
    }
  }

  MarketReceiptSettings copyWith({
    String? receiptTitle,
    String? address,
    String? phone,
    String? secondaryPhone,
    String? registrationNo,
    String? footerNote,
    String? paperSize,
    bool? showCustomerPhone,
    bool? showAdminName,
    String? templateStyle,
    String? debtTemplate,
    String? paymentTemplate,
    String? purchaseTemplate,
    String? logoPath,
    String? stampPath,
    String? signaturePath,
    String? primaryColor,
    double? fontScale,
    String? headerAlignment,
    bool? showQr,
    bool? showBarcode,
    String? receiptPrefix,
    double? vatPercent,
    double? discountPercent,
    String? defaultPaymentMethod,
    List<Map<String, String>>? customFields,
    double? marginMm,
    String? languageMode,
    int? templateVersion,
  }) {
    return MarketReceiptSettings(
      adminId: adminId,
      receiptTitle: receiptTitle ?? this.receiptTitle,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      secondaryPhone: secondaryPhone ?? this.secondaryPhone,
      registrationNo: registrationNo ?? this.registrationNo,
      footerNote: footerNote ?? this.footerNote,
      paperSize: paperSize ?? this.paperSize,
      showCustomerPhone: showCustomerPhone ?? this.showCustomerPhone,
      showAdminName: showAdminName ?? this.showAdminName,
      templateStyle: templateStyle ?? this.templateStyle,
      debtTemplate: debtTemplate ?? this.debtTemplate,
      paymentTemplate: paymentTemplate ?? this.paymentTemplate,
      purchaseTemplate: purchaseTemplate ?? this.purchaseTemplate,
      logoPath: logoPath ?? this.logoPath,
      stampPath: stampPath ?? this.stampPath,
      signaturePath: signaturePath ?? this.signaturePath,
      primaryColor: primaryColor ?? this.primaryColor,
      fontScale: fontScale ?? this.fontScale,
      headerAlignment: headerAlignment ?? this.headerAlignment,
      showQr: showQr ?? this.showQr,
      showBarcode: showBarcode ?? this.showBarcode,
      receiptPrefix: receiptPrefix ?? this.receiptPrefix,
      vatPercent: vatPercent ?? this.vatPercent,
      discountPercent: discountPercent ?? this.discountPercent,
      defaultPaymentMethod:
          defaultPaymentMethod ?? this.defaultPaymentMethod,
      customFields: customFields ?? this.customFields,
      marginMm: marginMm ?? this.marginMm,
      languageMode: languageMode ?? this.languageMode,
      templateVersion: templateVersion ?? this.templateVersion,
    );
  }

  Map<String, dynamic> toMap() => {
        'admin_id': adminId,
        'receipt_title': receiptTitle.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
        'secondary_phone': secondaryPhone.trim(),
        'registration_no': registrationNo.trim(),
        'footer_note': footerNote.trim(),
        'paper_size': paperSize,
        'show_customer_phone': showCustomerPhone,
        'show_admin_name': showAdminName,
        'template_style': templateStyle,
        'debt_template': debtTemplate,
        'payment_template': paymentTemplate,
        'purchase_template': purchaseTemplate,
        'logo_path': logoPath.trim(),
        'stamp_path': stampPath.trim(),
        'signature_path': signaturePath.trim(),
        'primary_color': primaryColor.trim().toUpperCase(),
        'font_scale': fontScale,
        'header_alignment': headerAlignment,
        'show_qr': showQr,
        'show_barcode': showBarcode,
        'receipt_prefix': receiptPrefix.trim().toUpperCase(),
        'vat_percent': vatPercent,
        'discount_percent': discountPercent,
        'default_payment_method': defaultPaymentMethod,
        'custom_fields': customFields,
        'margin_mm': marginMm,
        'language_mode': languageMode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Map<String, dynamic> toSnapshot() {
    final map = toMap();
    map.remove('updated_at');
    map.remove('admin_id');
    map['template_version'] = templateVersion;
    return map;
  }
}

class ReceiptSettingsService {
  ReceiptSettingsService._();

  static const brandingBucket = 'market-branding';

  static Future<MarketReceiptSettings> load({
    required String adminId,
    String fallbackMarketName = '',
    String fallbackPhone = '',
  }) async {
    if (adminId.trim().isEmpty) {
      return MarketReceiptSettings.defaults(
        adminId: adminId,
        marketName: fallbackMarketName,
        phone: fallbackPhone,
      );
    }

    await PBService.ensureInitialized();
    final row = await PBService.client
        .from('market_receipt_settings')
        .select()
        .eq('admin_id', adminId)
        .maybeSingle();

    if (row == null) {
      return MarketReceiptSettings.defaults(
        adminId: adminId,
        marketName: fallbackMarketName,
        phone: fallbackPhone,
      );
    }

    return MarketReceiptSettings.fromMap(
      Map<String, dynamic>.from(row),
      fallbackAdminId: adminId,
      fallbackPhone: fallbackPhone,
    );
  }

  static Future<MarketReceiptSettings> save(
    MarketReceiptSettings settings,
  ) async {
    await PBService.ensureInitialized();
    final row = await PBService.client
        .from('market_receipt_settings')
        .upsert(settings.toMap(), onConflict: 'admin_id')
        .select()
        .single();
    return MarketReceiptSettings.fromMap(
      Map<String, dynamic>.from(row),
      fallbackAdminId: settings.adminId,
      fallbackPhone: settings.phone,
    );
  }

  static Future<String> uploadBrandAsset({
    required String adminId,
    required String kind,
    required Uint8List bytes,
    required String fileName,
    String? contentType,
  }) async {
    await PBService.ensureInitialized();
    final lowerName = fileName.toLowerCase();
    final extension = lowerName.endsWith('.png')
        ? 'png'
        : lowerName.endsWith('.webp')
            ? 'webp'
            : 'jpg';
    final mime = contentType ??
        (extension == 'png'
            ? 'image/png'
            : extension == 'webp'
                ? 'image/webp'
                : 'image/jpeg');
    final safeKind = const {'logo', 'stamp', 'signature'}.contains(kind)
        ? kind
        : 'asset';
    final path =
        '$adminId/branding/${safeKind}_${DateTime.now().microsecondsSinceEpoch}.$extension';

    await PBService.client.storage.from(brandingBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    return path;
  }

  static Future<Uint8List?> loadBrandAsset(String path) async {
    final clean = path.trim();
    if (clean.isEmpty) return null;
    await PBService.ensureInitialized();
    try {
      return await PBService.client.storage.from(brandingBucket).download(clean);
    } catch (_) {
      return null;
    }
  }
}
