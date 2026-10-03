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
      postSeconds: integer('post_seconds', 30),
      timezone: '${map['timezone'] ?? 'Asia/Baghdad'}',
      retentionDays: integer('retention_days', 90),
    );
  }
}

class HikvisionAdminState {
  const HikvisionAdminState({
    required this.marketName,
    this.config,
    this.gateway,
  });

  final String marketName;
  final HikvisionMarketConfig? config;
  final HikvisionGatewayStatus? gateway;
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

  static Future<HikvisionAdminState> status() async {
    final data = await _invoke('status');
    final configRaw = data['config'];
    final gatewayRaw = data['gateway'];
    return HikvisionAdminState(
      marketName: '${data['market_name'] ?? ''}',
      config: configRaw is Map
          ? HikvisionMarketConfig.fromMap(Map<String, dynamic>.from(configRaw))
          : null,
      gateway: gatewayRaw is Map
          ? HikvisionGatewayStatus.fromMap(Map<String, dynamic>.from(gatewayRaw))
          : null,
    );
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
    if (value.contains('gateway_not_registered')) {
      return 'Gateway ـی ئەم مارکێتە هێشتا لە backend تۆمار نەکراوە.';
    }
    if (value.contains('invalid_config')) {
      return 'ڕێکخستنی کامێرا دروست نییە.';
    }
    return 'پەیوەندی Hikvision سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.';
  }
}
