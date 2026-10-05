import 'package:supabase_flutter/supabase_flutter.dart';

class HikvisionGatewayStatus {
  const HikvisionGatewayStatus({
    required this.paired,
    required this.active,
    this.gatewayId,
    this.lastSeenAt,
    this.gatewayVersion,
    this.platform,
    this.lastError,
    this.queued = 0,
    this.processing = 0,
    this.ready = 0,
    this.failed = 0,
    this.missing = 0,
  });

  final bool paired;
  final bool active;
  final String? gatewayId;
  final DateTime? lastSeenAt;
  final String? gatewayVersion;
  final String? platform;
  final String? lastError;
  final int queued;
  final int processing;
  final int ready;
  final int failed;
  final int missing;

  factory HikvisionGatewayStatus.fromMap(Map<String, dynamic> map) {
    int integer(String key) => map[key] is num
        ? (map[key] as num).toInt()
        : int.tryParse('${map[key] ?? ''}') ?? 0;
    return HikvisionGatewayStatus(
      paired: map['paired'] == true,
      active: map['active'] == true,
      gatewayId: map['gateway_id']?.toString(),
      lastSeenAt: DateTime.tryParse('${map['last_seen_at'] ?? ''}')?.toLocal(),
      gatewayVersion: map['gateway_version']?.toString(),
      platform: map['platform']?.toString(),
      lastError: map['last_error']?.toString(),
      queued: integer('queued'),
      processing: integer('processing'),
      ready: integer('ready'),
      failed: integer('failed'),
      missing: integer('missing'),
    );
  }
}

class HikvisionCloudStatus {
  const HikvisionCloudStatus({
    required this.configured,
    this.serverAddress,
    this.areaDomain,
    this.tokenExpiresAt,
    this.lastTestAt,
    this.lastError,
  });

  final bool configured;
  final String? serverAddress;
  final String? areaDomain;
  final DateTime? tokenExpiresAt;
  final DateTime? lastTestAt;
  final String? lastError;

  bool get healthy => configured && (lastError == null || lastError!.isEmpty);

  factory HikvisionCloudStatus.fromMap(Map<String, dynamic> map) {
    DateTime? time(String key) =>
        DateTime.tryParse('${map[key] ?? ''}')?.toLocal();
    String? text(String key) {
      final value = '${map[key] ?? ''}'.trim();
      return value.isEmpty ? null : value;
    }

    return HikvisionCloudStatus(
      configured: map['configured'] == true,
      serverAddress: text('server_address'),
      areaDomain: text('area_domain'),
      tokenExpiresAt: time('token_expires_at'),
      lastTestAt: time('last_test_at'),
      lastError: text('last_error'),
    );
  }
}

class HikvisionCloudCamera {
  const HikvisionCloudCamera({
    required this.id,
    required this.name,
    required this.online,
    required this.deviceSerial,
    required this.channelNo,
  });

  final String id;
  final String name;
  final bool online;
  final String deviceSerial;
  final int channelNo;

  factory HikvisionCloudCamera.fromMap(Map<String, dynamic> map) =>
      HikvisionCloudCamera(
        id: '${map['id'] ?? ''}',
        name: '${map['name'] ?? ''}',
        online: map['online'] == true,
        deviceSerial: '${map['device_serial'] ?? ''}',
        channelNo: map['channel_no'] is num
            ? (map['channel_no'] as num).toInt()
            : int.tryParse('${map['channel_no'] ?? ''}') ?? 0,
      );
}

class HikvisionMarketConfig {
  const HikvisionMarketConfig({
    required this.enabled,
    required this.autoCapture,
    required this.nvrLabel,
    required this.nvrHost,
    required this.nvrModel,
    required this.nvrFirmware,
    required this.cashierChannelId,
    required this.preSeconds,
    required this.postSeconds,
    required this.timezone,
    required this.retentionDays,
    required this.captureProvider,
    required this.hikconnectCameraId,
    required this.hikconnectCameraName,
    required this.hikconnectDeviceSerial,
    required this.hikconnectServerAddress,
  });

  final bool enabled;
  final bool autoCapture;
  final String nvrLabel;
  final String nvrHost;
  final String nvrModel;
  final String nvrFirmware;
  final int cashierChannelId;
  final int preSeconds;
  final int postSeconds;
  final String timezone;
  final int retentionDays;
  final String captureProvider;
  final String hikconnectCameraId;
  final String hikconnectCameraName;
  final String hikconnectDeviceSerial;
  final String hikconnectServerAddress;

  bool get usesCloud => captureProvider == 'hikconnect_cloud';

  factory HikvisionMarketConfig.fromMap(Map<String, dynamic> map) {
    int integer(String key, int fallback) => map[key] is num
        ? (map[key] as num).toInt()
        : int.tryParse('${map[key] ?? ''}') ?? fallback;
    return HikvisionMarketConfig(
      enabled: map['enabled'] != false,
      autoCapture: map['auto_capture'] != false,
      nvrLabel: '${map['nvr_label'] ?? 'Hikvision NVR'}',
      nvrHost: '${map['nvr_host'] ?? ''}',
      nvrModel: '${map['nvr_model'] ?? ''}',
      nvrFirmware: '${map['nvr_firmware'] ?? ''}',
      cashierChannelId: integer('cashier_channel_id', 1),
      preSeconds: integer('pre_seconds', 15),
      postSeconds: integer('post_seconds', 15),
      timezone: '${map['timezone'] ?? 'Asia/Baghdad'}',
      retentionDays: integer('retention_days', 90),
      captureProvider: '${map['capture_provider'] ?? 'local_gateway'}',
      hikconnectCameraId: '${map['hikconnect_camera_id'] ?? ''}',
      hikconnectCameraName: '${map['hikconnect_camera_name'] ?? ''}',
      hikconnectDeviceSerial: '${map['hikconnect_device_serial'] ?? ''}',
      hikconnectServerAddress: '${map['hikconnect_server_address'] ?? ''}',
    );
  }
}

class HikvisionAdminState {
  const HikvisionAdminState({
    required this.marketName,
    this.config,
    this.gateway,
    this.cloud,
    this.integrity = const {},
  });

  final String marketName;
  final HikvisionMarketConfig? config;
  final HikvisionGatewayStatus? gateway;
  final HikvisionCloudStatus? cloud;
  final Map<String, dynamic> integrity;
}

class HikvisionAdminService {
  HikvisionAdminService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static Future<Map<String, dynamic>> _invoke(
    String action, [
    Map<String, dynamic> extra = const {},
  ]) async {
    try {
      final response = await _client.functions.invoke(
        'hikvision-admin',
        body: {'action': action, ...extra},
      );
      final raw = response.data;
      if (raw is! Map) throw Exception('hikvision_invalid_response');
      final data = Map<String, dynamic>.from(raw);
      final error = data['error']?.toString();
      if (error != null && error.isNotEmpty) throw Exception(error);
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      if (details is Map && details['error'] != null) {
        throw Exception(details['error'].toString());
      }
      throw Exception('hikvision_request_failed');
    }
  }

  static Future<GatewayHealth> gatewayHealth() async {
    final data = await _invoke('gateway_health');
    return GatewayHealth.fromMap(
      Map<String, dynamic>.from(data['health'] as Map),
    );
  }

  static Future<void> setGatewayAlerts(bool enabled) async {
    await _invoke('gateway_alerts_setting', {'enabled': enabled});
  }

  static Future<HikvisionAdminState> status() async {
    final data = await _invoke('status');
    final configRaw = data['config'];
    final gatewayRaw = data['gateway'];
    final cloudRaw = data['cloud'];
    return HikvisionAdminState(
      marketName: '${data['market_name'] ?? ''}',
      integrity: data['integrity'] is Map
          ? Map<String, dynamic>.from(data['integrity'])
          : const {},
      config: configRaw is Map
          ? HikvisionMarketConfig.fromMap(Map<String, dynamic>.from(configRaw))
          : null,
      gateway: gatewayRaw is Map
          ? HikvisionGatewayStatus.fromMap(
              Map<String, dynamic>.from(gatewayRaw),
            )
          : null,
      cloud: cloudRaw is Map
          ? HikvisionCloudStatus.fromMap(Map<String, dynamic>.from(cloudRaw))
          : const HikvisionCloudStatus(configured: false),
    );
  }

  static Future<void> saveCloudCredentials({
    required String serverAddress,
    required String appKey,
    required String secretKey,
  }) async {
    await _invoke('save_cloud_credentials', {
      'server_address': serverAddress.trim(),
      'app_key': appKey.trim(),
      'secret_key': secretKey.trim(),
    });
  }

  static Future<List<HikvisionCloudCamera>> cloudCameras() async {
    final data = await _invoke('cloud_cameras');
    final raw = data['cameras'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              HikvisionCloudCamera.fromMap(Map<String, dynamic>.from(item)),
        )
        .where((camera) => camera.id.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> selectCloudCamera(String cameraId) async {
    await _invoke('select_cloud_camera', {'camera_id': cameraId});
  }

  static Future<void> useLocalGateway() async {
    await _invoke('use_local_gateway');
  }

  static Future<String> issueGatewayToken() async {
    final data = await _invoke('issue_gateway_token');
    final token = '${data['gateway_token'] ?? ''}'.trim();
    if (token.length < 32) throw Exception('hikvision_token_missing');
    return token;
  }

  static Future<void> updateConfig({
    required bool enabled,
    required bool autoCapture,
    required int cashierChannelId,
    required int preSeconds,
    required int postSeconds,
    required int retentionDays,
  }) async {
    await _invoke('update_config', {
      'enabled': enabled,
      'auto_capture': autoCapture,
      'cashier_channel_id': cashierChannelId,
      'pre_seconds': preSeconds,
      'post_seconds': postSeconds,
      'retention_days': retentionDays,
    });
  }

  static String userMessage(Object error) {
    final value = error.toString();
    if (value.contains('admin_required')) {
      return 'تەنها بەڕێوەبەری مارکێت دەتوانێت Hikvision ڕێکبخات.';
    }
    if (value.contains('invalid_cloud_credentials')) {
      return 'App Key، Secret Key یان سێرڤەری Hik-Connect دروست نییە.';
    }
    if (value.contains('hikconnect_auth_failed')) {
      return 'پەیوەندی بە Hik-Connect Team سەرکەوتوو نەبوو. AK/SK و ناونیشانی سێرڤەر بپشکنەوە.';
    }
    if (value.contains('camera_not_found')) {
      return 'کامێراکە لە Hik-Connect Cloud نەدۆزرایەوە.';
    }
    if (value.contains('invalid_camera_channel')) {
      return 'ژمارەی Channel ـی کامێراکە دروست نییە.';
    }
    if (value.contains('gateway_not_registered')) {
      return 'Gateway ـی ئەم مارکێتە هێشتا لە backend تۆمار نەکراوە.';
    }
    if (value.contains('invalid_config')) {
      return 'ڕێکخستنی کامێرا دروست نییە.';
    }
    return 'پەیوەندی Hikvision سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.';
  }
}

class GatewayHealth {
  const GatewayHealth({
    required this.status,
    required this.alertsEnabled,
    this.lastSeenAt,
    this.events = const [],
  });
  final String status;
  final bool alertsEnabled;
  final DateTime? lastSeenAt;
  final List<Map<String, dynamic>> events;
  factory GatewayHealth.fromMap(Map<String, dynamic> data) => GatewayHealth(
    status: '${data['status'] ?? 'unknown'}',
    alertsEnabled: data['alerts_enabled'] == true,
    lastSeenAt: DateTime.tryParse('${data['last_seen_at'] ?? ''}')?.toLocal(),
    events: data['events'] is List
        ? (data['events'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const [],
  );
  String get label => switch (status) {
    'online' => 'Gateway چالاکە',
    'offline' => 'پەیوەندی Gateway پچڕاوە',
    'starting' => 'چاوەڕوانی یەکەم پەیامی Gateway',
    'unpaired' => 'Gateway هێشتا بەستراو نییە',
    'disabled' => 'Local Gateway بەکارناهێنرێت',
    _ => 'دۆخی Gateway پشتڕاست نەکراوەتەوە',
  };
}
