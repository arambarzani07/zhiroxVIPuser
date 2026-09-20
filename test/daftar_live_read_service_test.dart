import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/daftar_live_read_service.dart';

void main() {
  test('parses live envelope and metadata', () {
    final result = DaftarLiveReadService.parseMapEnvelope({
      'ok': true,
      'source': 'live',
      'as_of': '2026-09-20T00:00:00Z',
      'stale': false,
      'fallback_reason': null,
      'data': {'total_remaining_iqd': 125000},
    });

    expect(result.meta.source, DaftarReadSource.live);
    expect(result.meta.stale, isFalse);
    expect(result.data['total_remaining_iqd'], 125000);
  });

  test('parses mirror fallback without losing data', () {
    final result = DaftarLiveReadService.parseMapEnvelope({
      'ok': true,
      'source': 'mirror',
      'as_of': '2026-09-19T23:59:00Z',
      'stale': false,
      'fallback_reason': 'source_timeout',
      'data': {'items': <dynamic>[]},
    });

    expect(result.meta.source, DaftarReadSource.mirror);
    expect(result.meta.fallbackReason, 'source_timeout');
    expect(result.data['items'], isEmpty);
  });


  test('parses zhirox primary envelope', () {
    final result = DaftarLiveReadService.parseMapEnvelope({
      'ok': true,
      'source': 'zhirox_primary',
      'as_of': null,
      'stale': false,
      'fallback_reason': null,
      'data': {'total_remaining_iqd': 125000},
    });

    expect(result.meta.source, DaftarReadSource.zhiroxPrimary);
    expect(result.meta.stale, isFalse);
    expect(result.data['total_remaining_iqd'], 125000);
  });

  test('rejects malformed live-read envelopes', () {
    expect(
      () => DaftarLiveReadService.parseMapEnvelope({
        'ok': true,
        'source': 'unexpected',
        'data': <String, dynamic>{},
      }),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => DaftarLiveReadService.parseMapEnvelope({
        'ok': false,
        'source': 'live',
        'data': <String, dynamic>{},
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
