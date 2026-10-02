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
  const TelegramConnectLink({required this.url, required this.botUsername});
  final Uri url;
  final String botUsername;
}

class TelegramIntegrationService {
  TelegramIntegrationService._();
  static SupabaseClient get _client => Supabase.instance.client;

  static Future<Map<String, dynamic>> _invoke(String action) async {
    try {
      final response = await _client.functions.invoke('telegram-integration', body: {'action': action});
      if (response.data is! Map) throw Exception('telegram_invalid_response');
      final data = Map<String, dynamic>.from(response.data as Map);
      final error = data['error']?.toString() ?? '';
      if (error.isNotEmpty) throw Exception(error);
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) throw Exception(details['error'].toString());
      throw Exception('telegram_request_failed');
    }
  }

  static Future<TelegramIntegrationStatus> status() async => TelegramIntegrationStatus.fromMap(await _invoke('status'));
  static Future<TelegramConnectLink> createConnectLink() async {
    final data = await _invoke('create_link');
    final uri = Uri.tryParse(data['connect_url']?.toString() ?? '');
    if (uri == null || !uri.hasScheme) throw Exception('telegram_invalid_link');
    return TelegramConnectLink(url: uri, botUsername: data['bot_username']?.toString() ?? 'Telegram');
  }
  static Future<void> testConnection() async => _invoke('test');
  static Future<void> disconnect() async => _invoke('disconnect');

  static String userMessage(Object error) {
    final value = error.toString();
    if (value.contains('telegram_service_not_configured')) return 'خزمەتگوزاری Telegram هێشتا چالاک نییە.';
    if (value.contains('telegram_not_connected')) return 'Telegram هێشتا بە هەژماری Owner پەیوەست نییە.';
    if (value.contains('telegram_sendMessage_failed')) return 'ناردنی پەیامی تاقیکردنەوە سەرکەوتوو نەبوو.';
    return 'پەیوەندی Telegram سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.';
  }
}
