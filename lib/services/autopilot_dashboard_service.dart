import 'package:zhirox/services/pb_service.dart';

class AutoPilotDashboardService {
  const AutoPilotDashboardService._();

  static Future<Map<String, dynamic>> load() async {
    await PBService.ensureInitialized();
    final response = await PBService.client.functions.invoke('autopilot-dashboard');
    final raw = response.data;
    if (raw is! Map) {
      throw Exception('invalid_autopilot_dashboard');
    }
    return Map<String, dynamic>.from(raw);
  }
}
