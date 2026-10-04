import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/transaction_video_service.dart';

void main() {
  test('playback rejects unavailable clips and unsafe or missing URLs', () {
    for (final response in [
      null,
      {'ready': false, 'signed_url': 'https://example.com/clip.mp4'},
      {'ready': true},
      {'ready': true, 'signed_url': 'file:///private/config.json'},
      {'ready': true, 'signed_url': 'http://example.com/clip.mp4'},
      {'ready': true, 'signed_url': 'https:///clip.mp4'},
    ]) {
      expect(
        () => TransactionVideoService.playbackUri(response),
        throwsStateError,
      );
    }
  });

  test(
    'playback preserves the signed URL including its authentication query',
    () {
      const url = 'https://example.com/storage/clip.mp4?token=signed-test';
      expect(
        TransactionVideoService.playbackUri({'ready': true, 'signed_url': url})
            .toString(),
        url,
      );
    },
  );
  test(
    'unknown clocks never claim a match; mismatch shows the clock offset',
    () {
      expect(TransactionVideoService.clockMismatch(null), false);
      expect(
        TransactionVideoService.clockLabel(null),
        contains('پشتڕاست نەکراوەتەوە'),
      );
      final evidence = <String, dynamic>{
        'playback_metadata': {
          'clock_check': {'status': 'mismatch', 'offset_seconds': -14400},
        },
      };
      expect(TransactionVideoService.clockMismatch(evidence), true);
      expect(TransactionVideoService.clockLabel(evidence), contains('-14400'));
      expect(
        TransactionVideoService.clockLabel({
          'playback_metadata': {
            'clock_check': {'status': 'matched'},
          },
        }),
        contains('دەگونجێت'),
      );
    },
  );
}
