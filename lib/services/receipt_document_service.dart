import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/receipt_settings_service.dart';

class ReceiptDocumentVersion {
  final String id;
  final String adminId;
  final String sourceType;
  final String sourceId;
  final int versionNo;
  final String receiptNumber;
  final int settingsVersion;
  final MarketReceiptSettings settings;
  final DateTime? createdAt;

  const ReceiptDocumentVersion({
    required this.id,
    required this.adminId,
    required this.sourceType,
    required this.sourceId,
    required this.versionNo,
    required this.receiptNumber,
    required this.settingsVersion,
    required this.settings,
    required this.createdAt,
  });

  factory ReceiptDocumentVersion.fromMap(Map<String, dynamic> row) {
    final adminId = row['admin_id']?.toString() ?? '';
    final snapshotRaw = row['settings_snapshot'];
    final snapshot = snapshotRaw is Map
        ? Map<String, dynamic>.from(snapshotRaw)
        : <String, dynamic>{};
    return ReceiptDocumentVersion(
      id: row['id']?.toString() ?? '',
      adminId: adminId,
      sourceType: row['source_type']?.toString() ?? 'debt',
      sourceId: row['source_id']?.toString() ?? '',
      versionNo: (row['version_no'] as num?)?.toInt() ?? 1,
      receiptNumber: row['receipt_number']?.toString() ?? '',
      settingsVersion: (row['settings_version'] as num?)?.toInt() ?? 1,
      settings: MarketReceiptSettings.fromSnapshot(
        snapshot,
        adminId: adminId,
      ),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
    );
  }
}

class ReceiptDocumentService {
  ReceiptDocumentService._();

  static Future<ReceiptDocumentVersion?> latest({
    required String adminId,
    required String sourceType,
    required String sourceId,
  }) async {
    if (adminId.isEmpty || sourceId.isEmpty) return null;
    await PBService.ensureInitialized();
    final row = await PBService.client
        .from('receipt_documents')
        .select()
        .eq('admin_id', adminId)
        .eq('source_type', sourceType)
        .eq('source_id', sourceId)
        .order('version_no', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return ReceiptDocumentVersion.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<ReceiptDocumentVersion> ensure({
    required String adminId,
    required String sourceType,
    required String sourceId,
    required MarketReceiptSettings currentSettings,
  }) async {
    final existing = await latest(
      adminId: adminId,
      sourceType: sourceType,
      sourceId: sourceId,
    );
    if (existing != null) return existing;

    await PBService.ensureInitialized();
    final actorId = PBService.client.auth.currentUser?.id ?? '';
    if (actorId.isEmpty) {
      throw StateError('Authentication required for receipt versioning.');
    }

    try {
      final row = await PBService.client
          .from('receipt_documents')
          .insert({
            'admin_id': adminId,
            'source_type': sourceType,
            'source_id': sourceId,
            'version_no': 1,
            'receipt_number': '',
            'settings_version': currentSettings.templateVersion,
            'settings_snapshot': currentSettings.toSnapshot(),
            'created_by': actorId,
          })
          .select()
          .single();
      return ReceiptDocumentVersion.fromMap(Map<String, dynamic>.from(row));
    } catch (_) {
      final raced = await latest(
        adminId: adminId,
        sourceType: sourceType,
        sourceId: sourceId,
      );
      if (raced != null) return raced;
      rethrow;
    }
  }
}
