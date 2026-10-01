import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class TelegramAdminStatus {
  const TelegramAdminStatus({
    required this.configured,
    required this.verified,
    this.botUsername,
  });

  final bool configured;
  final bool verified;
  final String? botUsername;

  factory TelegramAdminStatus.fromMap(Map<String, dynamic> map) {
    return TelegramAdminStatus(
      configured: map['configured'] == true,
      verified: map['verified'] == true,
      botUsername: map['bot_username']?.toString(),
    );
  }
}

class TelegramAdminService {
  const TelegramAdminService._();

  static Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> body,
  ) async {
    await PBService.ensureInitialized();
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'telegram-admin-config',
        body: body,
      );
      final data = response.data;
      if (data is! Map) {
        throw Exception('وەڵامی سێرڤەر دروست نییە');
      }
      final map = Map<String, dynamic>.from(data);
      final error = map['error']?.toString() ?? '';
      if (error.isNotEmpty) throw Exception(_messageFor(error));
      return map;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map) {
        final code = details['error']?.toString() ?? '';
        if (code.isNotEmpty) throw Exception(_messageFor(code));
      }
      throw Exception('پەیوەندی بە Telegram config سەرکەوتوو نەبوو');
    }
  }

  static Future<TelegramAdminStatus> status() async {
    final data = await _invoke({'action': 'status'});
    return TelegramAdminStatus.fromMap(data);
  }

  static Future<TelegramAdminStatus> setToken(String token) async {
    final clean = token.trim();
    if (clean.length < 20 || clean.length > 512 || !clean.contains(':')) {
      throw Exception('Bot Token دروست نییە');
    }
    final data = await _invoke({
      'action': 'set_token',
      'bot_token': clean,
    });
    return TelegramAdminStatus.fromMap(data);
  }

  static Future<TelegramAdminStatus> clearToken() async {
    final data = await _invoke({'action': 'clear_token'});
    return TelegramAdminStatus.fromMap(data);
  }

  static String _messageFor(String code) {
    switch (code) {
      case 'system_owner_required':
        return 'تەنها خاوەنی سیستەم دەتوانێت Bot Token بگۆڕێت';
      case 'invalid_telegram_bot_token':
        return 'Bot Token دروست نییە';
      case 'telegram_getMe_failed':
        return 'Telegram ئەم Bot Token ـەی پەسەند نەکرد';
      case 'telegram_setWebhook_failed':
        return 'دانانی Telegram Webhook سەرکەوتوو نەبوو';
      case 'telegram_bot_username_missing':
        return 'ناوی bot لە Telegram نەدۆزرایەوە';
      case 'authentication_required':
        return 'تکایە دووبارە بچۆ ژوورەوە';
      case 'server_not_configured':
        return 'ڕێکخستنی backend تەواو نییە';
      default:
        return 'هەڵەی Telegram: $code';
    }
  }
}
