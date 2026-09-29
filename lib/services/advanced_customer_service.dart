import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class AdvancedCustomerService {
  AdvancedCustomerService._();

  static Future<Map<String, dynamic>> getCustomerCenter(
    String customerId,
  ) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_customer_advanced_center',
      params: {'p_customer_id': customerId},
    );
    if (raw is! Map) throw const FormatException('invalid advanced customer center');
    return Map<String, dynamic>.from(raw);
  }

  static Future<Map<String, dynamic>> saveRules({
    required String customerId,
    required bool creditFrozen,
    required String watchStatus,
    required int graceDays,
    int? maxDebtDays,
    double? managerApprovalAmount,
    double? twoStepApprovalAmount,
    required bool autoVipEnabled,
    required int autoVipMonths,
    DateTime? vipExpiresAt,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'save_customer_advanced_rules',
      params: {
        'p_customer_id': customerId,
        'p_credit_frozen': creditFrozen,
        'p_watch_status': watchStatus,
        'p_grace_days': graceDays,
        'p_max_debt_days': maxDebtDays,
        'p_manager_approval_amount': managerApprovalAmount,
        'p_two_step_approval_amount': twoStepApprovalAmount,
        'p_auto_vip_enabled': autoVipEnabled,
        'p_auto_vip_months': autoVipMonths,
        'p_vip_expires_at': vipExpiresAt?.toUtc().toIso8601String(),
      },
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static Future<List<Map<String, dynamic>>> getGroups() async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc('get_customer_groups_catalog');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<String> createGroup(String name, {String color = ''}) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'create_customer_group',
      params: {'p_name': name.trim(), 'p_color': color.trim()},
    );
    return raw?.toString() ?? '';
  }

  static Future<void> setGroups(
    String customerId,
    Iterable<String> groupIds,
  ) async {
    await PBService.ensureInitialized();
    await PBService.client.rpc(
      'set_customer_groups',
      params: {
        'p_customer_id': customerId,
        'p_group_ids': groupIds.toList(growable: false),
      },
    );
  }

  static Future<Map<String, dynamic>> saveBusinessProfile({
    required String customerId,
    required String companyName,
    String taxNumber = '',
    String representativeName = '',
    String representativePhone = '',
    String invoiceReference = '',
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'save_customer_business_profile',
      params: {
        'p_customer_id': customerId,
        'p_company_name': companyName.trim(),
        'p_tax_number': taxNumber.trim(),
        'p_representative_name': representativeName.trim(),
        'p_representative_phone': representativePhone.trim(),
        'p_invoice_reference': invoiceReference.trim(),
      },
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static Future<String> addRelationship({
    required String customerId,
    required String relatedCustomerId,
    required String relationType,
    String note = '',
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'add_customer_relationship',
      params: {
        'p_customer_id': customerId,
        'p_related_customer_id': relatedCustomerId,
        'p_relation_type': relationType.trim(),
        'p_note': note.trim(),
      },
    );
    return raw?.toString() ?? '';
  }

  static Future<String> addNote({
    required String customerId,
    required String type,
    String body = '',
    String mediaPath = '',
    String mimeType = '',
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'add_customer_note',
      params: {
        'p_customer_id': customerId,
        'p_note_type': type,
        'p_body': body.trim(),
        'p_media_path': mediaPath,
        'p_mime_type': mimeType,
      },
    );
    return raw?.toString() ?? '';
  }

  static Future<String> addDocument({
    required String customerId,
    required String kind,
    required String fileName,
    required String storagePath,
    String mimeType = '',
    int sizeBytes = 0,
    String note = '',
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'add_customer_document',
      params: {
        'p_customer_id': customerId,
        'p_kind': kind,
        'p_file_name': fileName,
        'p_storage_path': storagePath,
        'p_mime_type': mimeType,
        'p_size_bytes': sizeBytes,
        'p_note': note.trim(),
      },
    );
    return raw?.toString() ?? '';
  }

  static Future<Map<String, dynamic>> getAssets(String customerId) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_customer_assets',
      params: {'p_customer_id': customerId},
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static Future<String> uploadVaultBytes({
    required String customerId,
    required String fileName,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) async {
    await PBService.ensureInitialized();
    final currentId = PBService.client.auth.currentUser?.id ?? '';
    if (currentId.isEmpty) throw StateError('not authenticated');
    final actor = await PBService.getUser(currentId);
    final role = actor.getStringValue('role');
    final adminId = role == 'admin' ? actor.id : actor.getStringValue('admin_id');
    if (adminId.isEmpty) throw StateError('tenant unavailable');

    final safeName = fileName
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '$adminId/$customerId/$stamp-$safeName';
    await PBService.client.storage.from('customer-vault').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  static Future<Map<String, dynamic>> evaluateCreditPolicy({
    required String customerId,
    required double debtAmount,
    required double projectedBalance,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'evaluate_customer_credit_policy',
      params: {
        'p_customer_id': customerId,
        'p_debt_amount': debtAmount,
        'p_projected_balance': projectedBalance,
      },
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static Future<String> requestCreditApproval({
    required String customerId,
    required double debtAmount,
    required double projectedBalance,
    String reason = '',
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'request_credit_approval',
      params: {
        'p_customer_id': customerId,
        'p_debt_amount': debtAmount,
        'p_projected_balance': projectedBalance,
        'p_reason': reason.trim(),
      },
    );
    return raw?.toString() ?? '';
  }

  static Future<bool> consumeCreditApproval(String requestId) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'consume_credit_approval',
      params: {'p_request_id': requestId},
    );
    return raw == true;
  }

  static Future<List<Map<String, dynamic>>> getApprovalInbox({
    int limit = 100,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_credit_approval_inbox',
      params: {'p_limit': limit},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> decideApproval({
    required String requestId,
    required bool approve,
    String note = '',
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'decide_credit_approval',
      params: {
        'p_request_id': requestId,
        'p_decision': approve ? 'approved' : 'rejected',
        'p_note': note.trim(),
      },
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static Future<Map<String, dynamic>> getCashFlowForecast({
    int days = 30,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_cash_flow_forecast',
      params: {'p_days': days},
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static Future<List<Map<String, dynamic>>> getEmployeePerformance({
    int days = 30,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_employee_performance',
      params: {'p_days': days},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<List<Map<String, dynamic>>> getAnomalies({
    int limit = 100,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_customer_anomalies',
      params: {'p_limit': limit},
    );
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>> getDataQuality({
    int limit = 200,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_data_quality_center',
      params: {'p_limit': limit},
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  static Future<List<Map<String, dynamic>>> getScheduledReports() async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc('get_scheduled_reports');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<String> saveScheduledReport({
    String? id,
    required String reportKind,
    required String cadence,
    required int runHour,
    int? weekday,
    int? monthDay,
    List<String> recipients = const [],
    bool enabled = true,
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'save_scheduled_report',
      params: {
        'p_id': id,
        'p_report_kind': reportKind,
        'p_cadence': cadence,
        'p_run_hour': runHour,
        'p_weekday': weekday,
        'p_month_day': monthDay,
        'p_recipients': recipients,
        'p_enabled': enabled,
      },
    );
    return raw?.toString() ?? '';
  }

  static Future<Map<String, dynamic>> refreshAutoVip(
    String customerId,
  ) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'refresh_auto_vip',
      params: {'p_customer_id': customerId},
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }
}
