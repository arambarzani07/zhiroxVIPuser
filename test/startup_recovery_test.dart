import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/startup_deadline.dart';
import 'package:zhirox/widgets/startup_recovery_screen.dart';

void main() {
  test('a hung startup operation times out', () async {
    final deadline = StartupDeadline(const Duration(milliseconds: 10));
    await expectLater(deadline.run(Completer<void>().future), throwsA(isA<TimeoutException>()));
  });

  test('subsequent checks share the same startup budget', () async {
    final deadline = StartupDeadline(const Duration(milliseconds: 20));
    await deadline.run(Future<void>.delayed(const Duration(milliseconds: 10)));
    await expectLater(deadline.run(Completer<void>().future), throwsA(isA<TimeoutException>()));
    await expectLater(deadline.run(Completer<void>().future), throwsA(isA<TimeoutException>()));
  });

  testWidgets('startup failure offers an interactive retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(home: StartupRecoveryScreen(message: 'Connection failed', onRetry: () => retries++)));
    expect(find.text('Connection failed'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(retries, 1);
  });
}
