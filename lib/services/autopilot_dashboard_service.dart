import 'package:zhirox/services/pb_service.dart';

class AutoPilotDashboardService {
  const AutoPilotDashboardService._();

  static Future<Map<String, dynamic>> load() async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc('get_my_autopilot_dashboard');
    if (raw is! Map) {
      throw Exception('invalid_autopilot_dashboard');
    }
    return Map<String, dynamic>.from(raw);
  }
}
