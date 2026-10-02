import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class OwnerAutoPilotService {
  const OwnerAutoPilotService._();

  static Future<Map<String, dynamic>> overview({
    String search = '',
    String health = 'all',
    int page = 1,
    int perPage = 25,
  }) async {
    await PBService.ensureInitialized();
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'owner-autopilot-dashboard',
        body: {
          'search': search.trim(),
          'health': health,
          'page': page,
          'per_page': perPage,
        },
      );
      final data = response.data;
      if (data is! Map) {
        throw Exception('وەڵامی سێرڤەر دروست نییە');
      }
      final map = Map<String, dynamic>.from(data);
      final code = map['error']?.toString() ?? '';
      if (code.isNotEmpty) throw Exception(_message(code));
      return map;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map) {
        final code = details['error']?.toString() ?? '';
        if (code.isNotEmpty) throw Exception(_message(code));
      }
      throw Exception('پەیوەندی بە AutoPilot Control Center سەرکەوتوو نەبوو');
    }
  }

  static String _message(String code) {
    switch (code) {
      case 'system_owner_required':
        return 'تەنها System Owner دەستی پێ دەگات';
      case 'authentication_required':
        return 'تکایە دووبارە بچۆ ژوورەوە';
      case 'dashboard_unavailable':
        return 'زانیارییەکانی AutoPilot بەردەست نین';
      case 'invalid_health_filter':
        return 'فیلتەری دۆخ دروست نییە';
      case 'invalid_dashboard_response':
        return 'وەڵامی AutoPilot Control Center دروست نییە';
      default:
        return 'هەڵەی AutoPilot: $code';
    }
  }
}
