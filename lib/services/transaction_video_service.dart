import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionVideoService {
  static Future<Map<String, dynamic>?> status(String type, String id) async {
    return Supabase.instance.client
        .from('transaction_video_evidence')
        .select('status,channel_id,clip_start_at,clip_end_at')
        .eq('source_type', type)
        .eq('source_id', id)
        .maybeSingle();
  }

  // The server checks the authenticated market and creates a short-lived URL.
  // Never persist the URL or expose a storage path as a public video link.
  static Future<Uri> playback(String type, String id) async {
    final response = await Supabase.instance.client.functions.invoke(
      'hikvision-admin',
      body: {'action': 'video_url', 'source_type': type, 'source_id': id},
    );
    return playbackUri(response.data);
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
    'uploading' => 'کلیپ بار دەکرێت',
    'ready' => 'کلیپ ئامادەیە',
    'missing' => 'تۆماری کامێرا بۆ ئەم کاتە نەدۆزرایەوە',
    'failed' => 'وەرگرتنی کلیپ سەرکەوتوو نەبوو',
    'expired' => 'ماوەی هەڵگرتنی کلیپ تەواو بووە',
    _ => 'کلیپێک بۆ ئەم مامەڵەیە تۆمار نەکراوە',
  };
}
