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

    return MarketReceiptSettings(
      adminId: text('admin_id', fallbackAdminId),
      receiptTitle: text('receipt_title', 'پسوولەی فەرمی'),
      address: text('address'),
      phone: text('phone', fallbackPhone),
      secondaryPhone: text('secondary_phone'),
      registrationNo: text('registration_no'),
      footerNote: text('footer_note', 'سوپاس بۆ مامەڵەکردنتان'),
      paperSize: text('paper_size', 'a4') == 'thermal80' ? 'thermal80' : 'a4',
      showCustomerPhone: row['show_customer_phone'] is bool
          ? row['show_customer_phone'] as bool
          : true,
      showAdminName:
          row['show_admin_name'] is bool ? row['show_admin_name'] as bool : true,
    );
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
        'paper_size': paperSize == 'thermal80' ? 'thermal80' : 'a4',
        'show_customer_phone': showCustomerPhone,
        'show_admin_name': showAdminName,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

class ReceiptSettingsService {
  ReceiptSettingsService._();

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

  static Future<void> save(MarketReceiptSettings settings) async {
    await PBService.ensureInitialized();
    await PBService.client
        .from('market_receipt_settings')
        .upsert(settings.toMap(), onConflict: 'admin_id');
  }
}
