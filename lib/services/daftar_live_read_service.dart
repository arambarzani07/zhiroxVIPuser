import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum DaftarReadSource { live, mirror, zhiroxPrimary }

class DaftarReadMeta {
  const DaftarReadMeta({
    required this.source,
    required this.asOf,
    required this.stale,
    required this.fallbackReason,
  });

  final DaftarReadSource source;
  final DateTime? asOf;
  final bool stale;
  final String? fallbackReason;
}

class DaftarReadResponse<T> {
  const DaftarReadResponse({required this.data, required this.meta});

  final T data;
  final DaftarReadMeta meta;
}

class DaftarLiveReadService {
  static final ValueNotifier<DaftarReadMeta?> lastMeta =
      ValueNotifier<DaftarReadMeta?>(null);

  static DaftarReadResponse<Map<String, dynamic>> parseMapEnvelope(
    Map<String, dynamic> envelope,
  ) {
    if (envelope['ok'] != true) {
      throw const FormatException('invalid_daftar_live_read_envelope');
    }

    final sourceRaw = envelope['source']?.toString();
    final source = switch (sourceRaw) {
      'live' => DaftarReadSource.live,
      'mirror' => DaftarReadSource.mirror,
      'zhirox_primary' => DaftarReadSource.zhiroxPrimary,
      _ => throw const FormatException('invalid_daftar_live_read_source'),
    };

    final rawData = envelope['data'];
    if (rawData is! Map) {
      throw const FormatException('invalid_daftar_live_read_data');
    }

    final asOfRaw = envelope['as_of']?.toString();
    final asOf = asOfRaw == null || asOfRaw.isEmpty
        ? null
        : DateTime.tryParse(asOfRaw);
    if (asOfRaw != null && asOfRaw.isNotEmpty && asOf == null) {
      throw const FormatException('invalid_daftar_live_read_as_of');
    }

    final staleRaw = envelope['stale'];
    if (staleRaw is! bool) {
      throw const FormatException('invalid_daftar_live_read_stale');
    }

    final fallbackRaw = envelope['fallback_reason'];
    if (fallbackRaw != null && fallbackRaw is! String) {
      throw const FormatException('invalid_daftar_live_read_fallback');
    }

    final meta = DaftarReadMeta(
      source: source,
      asOf: asOf,
      stale: staleRaw,
      fallbackReason: fallbackRaw as String?,
    );
    final result = DaftarReadResponse<Map<String, dynamic>>(
      data: Map<String, dynamic>.from(rawData),
      meta: meta,
    );
    lastMeta.value = meta;
    return result;
  }

  static Future<DaftarReadResponse<Map<String, dynamic>>> invokeMap(
    String operation, [
    Map<String, dynamic> params = const <String, dynamic>{},
  ]) async {
    final response = await Supabase.instance.client.functions.invoke(
      'daftar-live-read',
      body: {
        'operation': operation,
        'params': params,
      },
    );

    final raw = response.data;
    if (raw is! Map) {
      throw const FormatException('invalid_daftar_live_read_response');
    }
    return parseMapEnvelope(Map<String, dynamic>.from(raw));
  }
}
