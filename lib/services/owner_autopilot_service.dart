import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class OwnerAutoPilotService {
  const OwnerAutoPilotService._();
  static Future<Map<String, dynamic>> overview({String search = '', String health = 'all'}) async {
    await PBService.ensureInitialized();
    try {
      final response = await Supabase.instance.client.functions.invoke('owner-autopilot-dashboard', body: {'search': search.trim(), 'health': health, 'page': 1, 'per_page': 50});
      if (response.data is! Map) throw Exception('وەڵامی سێرڤەر دروست نییە');
      final map = Map<String, dynamic>.from(response.data as Map);
      final code = map['error']?.toString() ?? '';
      if (code.isNotEmpty) throw Exception(_message(code));
      return map;
    } on FunctionException catch (e) {
      if (e.details is Map) {
        final code = (e.details as Map)['error']?.toString() ?? '';
        if (code.isNotEmpty) throw Exception(_message(code));
      }
      throw Exception('پەیوەندی بە AutoPilot Control Center سەرکەوتوو نەبوو');
    }
  }
  static String _message(String code) {
    if (code == 'system_owner_required') return 'تەنها System Owner دەستی پێ دەگات';
    if (code == 'authentication_required') return 'تکایە دووبارە بچۆ ژوورەوە';
    if (code == 'dashboard_unavailable') return 'زانیارییەکانی AutoPilot بەردەست نین';
    return 'هەڵەی AutoPilot: ' + code;
  }
}