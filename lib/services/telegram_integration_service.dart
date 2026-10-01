import 'package:supabase_flutter/supabase_flutter.dart';

class TelegramIntegrationStatus {
  const TelegramIntegrationStatus({
    required this.serviceConfigured,
    required this.connected,
    this.telegramUsername,
    this.chatHint,
    this.connectedAt,
    this.lastTestedAt,
  });

  final bool serviceConfigured;
  final bool connected;
  final String? telegramUsername;
  final String? chatHint;
  final DateTime? connectedAt;
  final DateTime? lastTestedAt;

  factory TelegramIntegrationStatus.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null || value.toString().trim().isEmpty) return null;
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    return TelegramIntegrationStatus(
      serviceConfigured: map['service_configured'] == true,
      connected: map['connected'] == true,
      telegramUsername: map['telegram_username']?.toString(),
      chatHint: map['chat_hint']?.toString(),
      connectedAt: parseDate(map['connected_at']),
      lastTestedAt: parseDate(map['last_tested_at']),
    );
  }
}

class TelegramConnectLink {
  const TelegramConnectLink({
    required this.url,
    required this.botUsername,
    required this.expiresAt,
  });

  final Uri url;
  final String botUsername;
  final DateTime? expiresAt;
}

class TelegramIntegrationService {
  TelegramIntegrationService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<Map<String, dynamic>> _invoke(String action) async {
    try {
      final response = await _client.functions.invoke(
        'telegram-integration',
        body: {'action': action},
      );
      final raw = response.data;
      if (raw is! Map) throw Exception('telegram_invalid_response');
      final data = Map<String, dynamic>.from(raw);
      final error = data['error']?.toString();
      if (error != null && error.isNotEmpty) throw Exception(error);
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception('telegram_request_failed');
    }
  }

  static Future<TelegramIntegrationStatus> status() async {
    final data = await _invoke('status');
    return TelegramIntegrationStatus.fromMap(data);
  }

  static Future<TelegramConnectLink> createConnectLink() async {
    final data = await _invoke('create_link');
    final rawUrl = data['connect_url']?.toString() ?? '';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) throw Exception('telegram_invalid_link');
    return TelegramConnectLink(
      url: uri,
      botUsername: data['bot_username']?.toString() ?? 'Telegram',
      expiresAt: DateTime.tryParse(data['expires_at']?.toString() ?? '')?.toLocal(),
    );
  }

  static Future<void> testConnection() async {
    await _invoke('test');
  }

  static Future<void> disconnect() async {
    await _invoke('disconnect');
  }

  static String userMessage(Object error) {
    final value = error.toString();
    if (value.contains('telegram_service_not_configured')) {
      return 'خزمەتگوزاری Telegram هێشتا لەلایەن خاوەنی سیستەمەوە چالاک نەکراوە.';
    }
    if (value.contains('telegram_not_connected')) {
      return 'Telegram هێشتا بە هەژمارەکەت پەیوەست نەکراوە.';
    }
    if (value.contains('telegram_sendMessage_failed')) {
      return 'ناردنی پەیامی تاقیکردنەوە سەرکەوتوو نەبوو.';
    }
    if (value.contains('telegram_getMe_failed') ||
        value.contains('telegram_setWebhook_failed')) {
      return 'ڕێکخستنی بۆتی Telegram لە backend دروست نییە.';
    }
    return 'پەیوەندی Telegram سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.';
  }
}
