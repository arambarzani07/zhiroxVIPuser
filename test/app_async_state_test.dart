import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/widgets/app_async_state.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('ready state renders feature content', (tester) async {
    await tester.pumpWidget(
      host(
        const AppAsyncStateView(
          state: AppAsyncState.ready,
          child: Text('ready-content'),
        ),
      ),
    );

    expect(find.text('ready-content'), findsOneWidget);
  });

  testWidgets('error state exposes retry action', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      host(
        AppAsyncStateView(
          state: AppAsyncState.error,
          child: const SizedBox.shrink(),
          message: 'هەڵەی تاقیکردنەوە',
          onRetry: () async {
            retries++;
          },
        ),
      ),
    );

    expect(find.text('هەڵەی تاقیکردنەوە'), findsOneWidget);
    await tester.tap(find.text('دووبارە هەوڵ بدە'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('empty state uses a consistent message surface', (tester) async {
    await tester.pumpWidget(
      host(
        const AppAsyncStateView(
          state: AppAsyncState.empty,
          child: SizedBox.shrink(),
          emptyTitle: 'هیچ کڕیارێک نییە',
          emptyMessage: 'کڕیاری نوێ زیاد بکە.',
        ),
      ),
    );

    expect(find.text('هیچ کڕیارێک نییە'), findsOneWidget);
    expect(find.text('کڕیاری نوێ زیاد بکە.'), findsOneWidget);
  });
}
