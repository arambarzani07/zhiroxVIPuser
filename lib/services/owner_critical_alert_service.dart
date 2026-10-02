import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/pb_service.dart';

class OwnerCriticalAlertService {
  const OwnerCriticalAlertService._();

  static Future<List<Map<String, dynamic>>> recent({int limit = 50}) async {
    await PBService.ensureInitialized();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const [];
    final rows = await Supabase.instance.client
        .from('app_realtime_notifications')
        .select()
        .eq('recipient_user_id', user.id)
        .inFilter('event_type', const [
          'owner_autopilot_critical',
          'owner_autopilot_recovery',
        ])
        .order('created_at', ascending: false)
        .limit(limit.clamp(1, 100));
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static Future<int> unreadCount() async {
    final rows = await recent(limit: 100);
    return rows.where((row) => row['read_at'] == null).length;
  }

  static Future<void> markRead(String id) async {
    await PBService.ensureInitialized();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || id.trim().isEmpty) return;
    await Supabase.instance.client
        .from('app_realtime_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .eq('recipient_user_id', user.id);
  }

  static Future<void> markDelivered(String id) async {
    await PBService.ensureInitialized();
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || id.trim().isEmpty) return;
    await Supabase.instance.client
        .from('app_realtime_notifications')
        .update({'delivered_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .eq('recipient_user_id', user.id);
  }
}
