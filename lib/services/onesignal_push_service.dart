import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

/// Secure OneSignal push sender for the ZHIROX User application.
///
/// The OneSignal REST API key never exists in the Flutter binary. All sends
/// are authorized and delivered by the `onesignal-send` Supabase Edge
/// Function, which enforces tenant isolation and employee permissions.
class OneSignalPushService {
  const OneSignalPushService._();

  static SupabaseClient get _client => PBService.client;

  static Future<Map<String, dynamic>> sendToUser({
    required String targetUserId,
    required String title,
    required String body,
    Map<String, dynamic> data = const <String, dynamic>{},
  }) async {
    final target = targetUserId.trim();
    final cleanTitle = title.trim();
    final cleanBody = body.trim();

    if (target.isEmpty) {
      throw ArgumentError.value(targetUserId, 'targetUserId', 'Required');
    }
    if (cleanTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Required');
    }
    if (cleanBody.isEmpty) {
      throw ArgumentError.value(body, 'body', 'Required');
    }

    await PBService.ensureInitialized();

    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('authentication_required');
    }

    final response = await _client.functions.invoke(
      'onesignal-send',
      body: <String, dynamic>{
        'target_user_id': target,
        'title': cleanTitle,
        'body': cleanBody,
        'data': data,
      },
    );

    final payload = response.data;
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return Map<String, dynamic>.from(payload);

    if (kDebugMode) {
      debugPrint('Unexpected OneSignal response: $payload');
    }
    return <String, dynamic>{'ok': response.status == 200};
  }

  static Future<Map<String, dynamic>> paymentReceived({
    required String targetUserId,
    required String customerId,
    required String customerName,
    required String amount,
    String? paymentId,
  }) {
    return sendToUser(
      targetUserId: targetUserId,
      title: 'پارەدانەوە وەرگیرا',
      body: '$customerName بڕی $amount داوەتەوە.',
      data: <String, dynamic>{
        'type': 'payment_received',
        'customer_id': customerId,
        if (paymentId?.trim().isNotEmpty ?? false)
          'payment_id': paymentId!.trim(),
        'open_financial_chat': true,
      },
    );
  }

  static Future<Map<String, dynamic>> debtCreated({
    required String targetUserId,
    required String customerId,
    required String customerName,
    required String amount,
    String? debtId,
  }) {
    return sendToUser(
      targetUserId: targetUserId,
      title: 'قەرزی نوێ تۆمارکرا',
      body: 'قەرزی $amount بۆ $customerName تۆمارکرا.',
      data: <String, dynamic>{
        'type': 'new_debt',
        'customer_id': customerId,
        if (debtId?.trim().isNotEmpty ?? false) 'debt_id': debtId!.trim(),
        'open_financial_chat': true,
      },
    );
  }

  static Future<Map<String, dynamic>> debtLimitWarning({
    required String targetUserId,
    required String customerId,
    required String customerName,
    required String currentDebt,
    required String limit,
  }) {
    return sendToUser(
      targetUserId: targetUserId,
      title: 'ئاگاداری سنووری قەرز',
      body: 'قەرزی $customerName گەیشتووەتە $currentDebt؛ سنوور: $limit.',
      data: <String, dynamic>{
        'type': 'debt_limit_warning',
        'customer_id': customerId,
        'open_financial_chat': true,
      },
    );
  }

  static Future<Map<String, dynamic>> syncError({
    required String targetUserId,
    required String source,
    required String message,
    String? customerId,
  }) {
    return sendToUser(
      targetUserId: targetUserId,
      title: 'کێشەی Sync',
      body: '$source: $message',
      data: <String, dynamic>{
        'type': 'sync_error',
        'source': source,
        if (customerId?.trim().isNotEmpty ?? false)
          'customer_id': customerId!.trim(),
      },
    );
  }
}
