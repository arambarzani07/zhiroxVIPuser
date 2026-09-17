import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/debt_push_enqueue.dart';

void main() {
  test('best-effort debt push forwards the created debt id exactly once', () async {
    final seen = <String>[];

    await enqueueDebtPushBestEffort(
      debtId: 'debt-123',
      invoke: (debtId) async {
        seen.add(debtId);
      },
    );

    expect(seen, ['debt-123']);
  });

  test('best-effort debt push swallows push failure and reports it', () async {
    Object? reported;

    await expectLater(
      enqueueDebtPushBestEffort(
        debtId: 'debt-456',
        invoke: (_) async {
          throw StateError('push unavailable');
        },
        onError: (error) {
          reported = error;
        },
      ),
      completes,
    );

    expect(reported, isA<StateError>());
    expect(reported.toString(), contains('push unavailable'));
  });
}
