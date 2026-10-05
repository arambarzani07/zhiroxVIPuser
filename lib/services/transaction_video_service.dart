import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionVideoService {
  static Future<Map<String, dynamic>?> status(String type, String id) async {
    final response = await Supabase.instance.client.functions.invoke(
      'hikvision-admin',
      body: {'action': 'video_status', 'source_type': type, 'source_id': id},
    );
    final raw = response.data;
    if (raw is! Map || raw['ok'] != true) {
      throw StateError('video_status_failed');
    }
    final evidence = raw['evidence'];
    return evidence is Map ? Map<String, dynamic>.from(evidence) : null;
  }

  // The server checks the authenticated market and creates a short-lived URL.
  // Never persist the URL or expose a storage path as a public video link.
  static Future<Map<String, dynamic>> playbackDetails(
    String type,
    String id,
  ) async {
    final response = await Supabase.instance.client.functions.invoke(
      'hikvision-admin',
      body: {'action': 'video_url', 'source_type': type, 'source_id': id},
    );
    playbackUri(response.data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<Uri> playback(String type, String id) async =>
      playbackUri(await playbackDetails(type, id));

  static Future<void> rebuild(String type, String id) async {
    final response = await Supabase.instance.client.functions.invoke(
      'hikvision-admin',
      body: {'action': 'rebuild_video', 'source_type': type, 'source_id': id},
    );
    if (response.data is! Map || response.data['ok'] != true) {
      throw StateError('rebuild_failed');
    }
  }

  static bool clockMismatch(Map<String, dynamic>? evidence) {
    final metadata = evidence?['playback_metadata'];
    return metadata is Map &&
        metadata['clock_check'] is Map &&
        metadata['clock_check']['status'] == 'mismatch';
  }

  static String clockLabel(Map<String, dynamic>? evidence) {
    final metadata = evidence?['playback_metadata'];
    final check = metadata is Map ? metadata['clock_check'] : null;
    if (check is! Map || check['status'] == 'unknown') {
      return 'کاتی ناو دیمەن هێشتا پشتڕاست نەکراوەتەوە.';
    }
    if (check['status'] == 'matched') {
      return 'کاتی خوێندراوەی دیمەن لەگەڵ ماوەی داواکراوی مامەڵە دەگونجێت.';
    }
    if (check['status'] == 'mismatch') {
      final seconds = (check['offset_seconds'] as num?)?.round();
      return 'ئاگاداری: کاتی دیمەن لەگەڵ کاتی داواکراو ناگونجێت.${seconds == null ? '' : ' جیاوازی: $seconds چرکە.'}';
    }
    return 'کاتی ناو دیمەن هێشتا پشتڕاست نەکراوەتەوە.';
  }

  static Uri playbackUri(dynamic data) {
    if (data is! Map || data['ready'] != true) {
      throw StateError('video_not_ready');
    }
    final uri = Uri.tryParse('${data['signed_url'] ?? ''}');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw StateError('invalid_video_url');
    }
    return uri;
  }

  static String statusLabel(String? status) => switch (status) {
    'queued' => 'کلیپ لە چاوەڕوانیدایە',
    'processing' => 'کلیپ ئامادە دەکرێت',
    'retrying' => 'گرتنی کلیپ دووبارە هەوڵ دەدرێتەوە',
    'uploading' => 'کلیپ بار دەکرێت',
    'ready' => 'کلیپ ئامادەیە',
    'missing' => 'تۆماری کامێرا بۆ ئەم کاتە نەدۆزرایەوە',
    'failed' => 'وەرگرتنی کلیپ سەرکەوتوو نەبوو',
    'expired' => 'ماوەی هەڵگرتنی کلیپ تەواو بووە',
    _ => 'کلیپێک بۆ ئەم مامەڵەیە تۆمار نەکراوە',
  };
}
