import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/a11_camera_coordinator.dart';
import 'package:zhirox/services/a11_camera_service.dart';
import 'package:zhirox/services/pb_service.dart';

class CameraSourceState {
  const CameraSourceState({
    required this.marketId,
    required this.activeProvider,
    required this.a11Configured,
  });

  final String marketId;
  final String activeProvider;
  final bool a11Configured;

  bool get isHikvision => activeProvider == CameraSourceService.hikvision;
  bool get isA11 => activeProvider == CameraSourceService.a11;
}

/// Keeps both camera integrations installed while selecting which provider
/// stamps NEW transaction video jobs. Existing evidence and provider-specific
/// workers are not deleted when the selection changes.
class CameraSourceService {
  CameraSourceService._();

  static final CameraSourceService instance = CameraSourceService._();

  static const String hikvision = 'local_gateway';
  static const String a11 = 'a11_local_rtsp';

  SupabaseClient get _client => Supabase.instance.client;

  Future<String> _requireAdminMarketId() async {
    await PBService.ensureInitialized();
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('not_authenticated');

    final profile = await _client
        .from('profiles')
        .select('id,role,active,approved')
        .eq('id', user.id)
        .single();

    if (profile['role'] != 'admin' ||
        profile['active'] != true ||
        profile['approved'] != true) {
      throw StateError('admin_required');
    }
    return profile['id'].toString();
  }

  Future<CameraSourceState> loadState() async {
    final marketId = await _requireAdminMarketId();
    final row = await _client
        .from('hikvision_market_config')
        .select('capture_provider')
        .eq('market_id', marketId)
        .single();
    final config = await A11CameraService.instance.loadConfig();

    return CameraSourceState(
      marketId: marketId,
      activeProvider: row['capture_provider']?.toString() ?? hikvision,
      a11Configured: config.enabled && config.password.isNotEmpty,
    );
  }

  Future<void> selectHikvision() async {
    final marketId = await _requireAdminMarketId();
    await _client
        .from('hikvision_market_config')
        .update({
          'capture_provider': hikvision,
          'enabled': true,
          'auto_capture': true,
        })
        .eq('market_id', marketId);

    // A11 is intentionally NOT deleted or disabled. Its local configuration
    // stays on the phone so switching back is immediate.
  }

  Future<void> selectA11() async {
    final marketId = await _requireAdminMarketId();
    final config = await A11CameraService.instance.loadConfig();
    if (!config.enabled || config.password.isEmpty) {
      throw StateError('a11_not_configured');
    }

    // Prove the local RTSP stream before changing the provider for new jobs.
    await A11CameraService.instance.stopBuffer();
    final reachable = await A11CameraService.instance.testConnection();
    if (!reachable) {
      await A11CameraService.instance.ensureBufferRunning();
      throw StateError('a11_rtsp_unreachable');
    }

    await _client
        .from('hikvision_market_config')
        .update({
          'capture_provider': a11,
          'enabled': true,
          'auto_capture': true,
        })
        .eq('market_id', marketId);

    await A11CameraService.instance.ensureBufferRunning();
    await A11CameraCoordinator.instance.start();
  }
}
