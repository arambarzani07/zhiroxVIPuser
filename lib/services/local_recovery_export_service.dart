import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalRecoveryExportResult {
  const LocalRecoveryExportResult({
    required this.path,
    required this.cacheKeys,
    required this.recoveredCollections,
  });

  final String path;
  final int cacheKeys;
  final int recoveredCollections;
}

/// Extracts only locally cached ZHIROX data from the existing app install.
///
/// This deliberately does not contact the old backend. It is intended for the
/// quota-restriction recovery path where the server returns HTTP 402.
///
/// Passwords, auth/session tokens, bot tokens, API keys and other credential
/// material are removed recursively before the recovery file is written.
class LocalRecoveryExportService {
  LocalRecoveryExportService._();

  static const _secureStorage = FlutterSecureStorage();

  static const _allowedPreferencePrefixes = <String>[
    'cached_',
  ];

  static bool _isSensitiveKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('credential') ||
        normalized.contains('service_role') ||
        normalized.contains('api_key') ||
        normalized.contains('apikey') ||
        normalized.contains('bot_token') ||
        normalized.contains('authorization') ||
        normalized.contains('session');
  }

  static dynamic _sanitize(dynamic value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((rawKey, rawValue) {
        final key = rawKey.toString();
        if (_isSensitiveKey(key)) return;
        out[key] = _sanitize(rawValue);
      });
      return out;
    }
    if (value is List) {
      return value.map(_sanitize).toList(growable: false);
    }
    return value;
  }

  static dynamic _decodeBestEffort(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  static bool _shouldIncludePreference(String key) {
    return _allowedPreferencePrefixes.any(key.startsWith);
  }

  static Future<Map<String, dynamic>> collect() async {
    final prefs = await SharedPreferences.getInstance();
    final cache = <String, dynamic>{};

    final keys = prefs.getKeys().toList()..sort();
    for (final key in keys) {
      if (!_shouldIncludePreference(key)) continue;
      final value = prefs.get(key);
      if (value is String) {
        cache[key] = _sanitize(_decodeBestEffort(value));
      } else if (value is List<String>) {
        cache[key] = _sanitize(value);
      } else if (value is num || value is bool) {
        cache[key] = value;
      }
    }

    String? storedUserId;
    dynamic storedUserData;
    try {
      storedUserId = await _secureStorage.read(key: 'user_id');
      final raw = await _secureStorage.read(key: 'user_data');
      if (raw != null && raw.trim().isNotEmpty) {
        storedUserData = _sanitize(_decodeBestEffort(raw));
      }
    } catch (_) {
      // Keychain/Keystore can be unavailable on some devices or old installs.
      // Cache recovery should still continue without secure-storage metadata.
    }

    var collections = 0;
    for (final value in cache.values) {
      if (value is List && value.isNotEmpty) collections++;
      if (value is Map && value.isNotEmpty) collections++;
    }
    if (storedUserData != null) collections++;

    return <String, dynamic>{
      'format': 'zhirox_local_recovery_v1',
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'source': 'device_local_cache',
      'safety': <String, dynamic>{
        'credentials_removed': true,
        'server_contacted': false,
      },
      'identity': <String, dynamic>{
        if (storedUserId != null && storedUserId.trim().isNotEmpty)
          'user_id': storedUserId.trim(),
        if (storedUserData != null) 'user_data': storedUserData,
      },
      'cache': cache,
      'summary': <String, dynamic>{
        'cache_keys': cache.length,
        'recovered_collections': collections,
      },
    };
  }

  static Future<LocalRecoveryExportResult> exportAndShare() async {
    final payload = await collect();
    final summary = Map<String, dynamic>.from(
      payload['summary'] as Map? ?? const <String, dynamic>{},
    );
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${dir.path}/zhirox_local_recovery_$stamp.json');

    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(payload),
      flush: true,
    );

    await Share.shareXFiles(
      <XFile>[XFile(file.path, mimeType: 'application/json')],
      subject: 'ZHIROX Local Recovery',
      text:
          'فایلی ڕزگارکردنی داتای ناوخۆی ZHIROX. وشەی نهێنی و token ـەکان لابراون.',
    );

    return LocalRecoveryExportResult(
      path: file.path,
      cacheKeys: (summary['cache_keys'] as num?)?.toInt() ?? 0,
      recoveredCollections:
          (summary['recovered_collections'] as num?)?.toInt() ?? 0,
    );
  }
}
