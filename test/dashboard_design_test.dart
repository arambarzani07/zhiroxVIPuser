import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/widgets/app_design.dart';
import 'package:zhirox/widgets/dashboard_design.dart';
import 'package:zhirox/widgets/zhirox_shell.dart';

void main() {
  for (final width in [320.0, 390.0, 1024.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('RTL dashboard at $width with text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppDesign.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: Scaffold(
              body: DashboardContent(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const DashboardHero(
                      title: 'سوپەرمارکێتی کانی چنار',
                      subtitle: 'کۆتا نوێکردنەوە: 12:20',
                      child: DashboardGrid(
                        maxColumns: 4,
                        children: [
                          DashboardMetric(
                            label: 'کۆی قەرز',
                            value: '217,554,420 د.ع',
                            secondaryValue: '100.00 USD',
                            icon: Icons.receipt_long,
                            onHero: true,
                          ),
                          DashboardMetric(
                            label: 'کڕیارەکان',
                            value: '520',
                            icon: Icons.people,
                            onHero: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    DashboardGrid(
                      maxColumns: 4,
                      minTileWidth: 120,
                      children: [
                        DashboardAction(
                          label: 'مارکێتەکان',
                          icon: Icons.storefront,
                          onTap: () {},
                        ),
                        DashboardAction(
                          label: 'دەسەڵاتەکان',
                          icon: Icons.rule,
                          onTap: () {},
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('217,554,420 د.ع'), findsOneWidget);
        expect(find.text('100.00 USD'), findsOneWidget);
        final first = tester.getTopLeft(find.byType(DashboardMetric).first);
        final second = tester.getTopLeft(find.byType(DashboardMetric).last);
        if (width == 320 || (width == 390 && scale == 2)) {
          expect(second.dy, greaterThan(first.dy));
        } else {
          expect(second.dy, first.dy);
          expect(first.dx, greaterThan(second.dx));
        }
      });
    }
  }

  testWidgets('shared navigation switches pages in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppDesign.darkTheme, home: const _ShellTest()),
    );
    await tester.tap(find.text('کڕیار'));
    await tester.pumpAndSettle();
    expect(find.text('customer page'), findsOneWidget);
    await tester.tap(find.text('سەرەکی'));
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ShellTest extends StatefulWidget {
  const _ShellTest();

  @override
  State<_ShellTest> createState() => _ShellTestState();
}

class _ShellTestState extends State<_ShellTest> {
  int index = 0;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: ZhiroxAppShell(
      index: index,
      pages: const [
        Center(child: Text('home page')),
        Center(child: Text('customer page')),
      ],
      destinations: const [
        ZhiroxDestination(
          label: 'سەرەکی',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
        ),
        ZhiroxDestination(
          label: 'کڕیار',
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
        ),
      ],
      onSelected: (value) => setState(() => index = value),
    ),
  );
}
