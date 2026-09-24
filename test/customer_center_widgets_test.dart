import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/features/customers/customer_center_widgets.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 390, child: child),
      ),
    );

void main() {
  testWidgets('customer center header exposes search filter count and add',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var search = '';
    var filter = '';
    var addCount = 0;

    await tester.pumpWidget(
      host(
        CustomerCenterHeader(
          title: 'کڕیارەکان',
          icon: Icons.people,
          totalCount: 12,
          countLabel: 'کڕیار',
          searchController: controller,
          onSearchChanged: (value) => search = value,
          onClearSearch: controller.clear,
          canAdd: true,
          onAdd: () => addCount++,
          showFilters: true,
          selectedFilter: 'all',
          onFilterSelected: (value) => filter = value,
        ),
      ),
    );

    expect(find.text('12 کڕیار'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'ئارام');
    expect(search, 'ئارام');

    await tester.tap(find.text('قەرزدار'));
    await tester.pump();
    expect(filter, 'with_debt');

    await tester.tap(find.byTooltip('زیادکردن'));
    expect(addCount, 1);
  });

  testWidgets('directory card renders financial and priority signals',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      host(
        CustomerDirectoryCard(
          customerId: 'c1',
          name: 'ئارام',
          displayName: 'ئارام · 1234',
          phone: '07500001234',
          isEmployee: false,
          approved: true,
          isPinned: true,
          isVip: true,
          unread: true,
          timeLabel: '10:30',
          preview: 'قەرز 10,000 د.ع',
          balance: 10000,
          hasBalance: true,
          balanceUnavailable: false,
          openDebtCount: 2,
          canManage: true,
          onTap: () => opened++,
        ),
      ),
    );

    expect(find.text('ئارام · 1234'), findsOneWidget);
    expect(find.text('VIP'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
    expect(find.text('2 قەرزی کراوە'), findsOneWidget);
    expect(find.text('ماوە: 10,000 د.ع'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('user-card-c1')));
    await tester.pump();
    expect(opened, 1);
  });
}
