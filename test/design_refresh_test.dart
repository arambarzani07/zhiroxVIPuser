import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/widgets/app_design.dart';
import 'package:zhirox/widgets/design_refresh.dart';

void main() {
  for (final size in [
    const Size(320, 800),
    const Size(390, 844),
    const Size(800, 1024),
    const Size(1200, 900),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('RTL navigation at $size dark=$dark and enlarged text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ZhiroxVisual.theme(
              dark ? AppDesign.darkTheme : AppDesign.lightTheme,
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(2)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: StatefulBuilder(
              builder: (context, setState) => ZhiroxNavigationScaffold(
                index: selected,
                onSelected: (value) => setState(() => selected = value),
                pages: const [
                  Center(child: Text('پەڕەی سەرەکی')),
                  Center(child: Text('پەڕەی دووەم')),
                  Center(child: Text('پەڕەی سێیەم')),
                ],
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    label: 'سەرەکی',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    label: 'کڕیار',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune),
                    label: 'ڕێکخستن',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byType(size.width >= 720 ? NavigationRail : NavigationBar),
          findsOneWidget,
        );
        await tester.tap(find.byIcon(Icons.people_outline));
        await tester.pumpAndSettle();
        expect(selected, 1);
        expect(find.text('پەڕەی دووەم'), findsOneWidget);
        expect(find.text('پەڕەی سەرەکی'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('quick actions wrap at large text and remain tappable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ZhiroxActionGrid(
              children: [
                for (var i = 0; i < 4; i++)
                  TextButton(
                    onPressed: () => tapped = true,
                    child: Text('دەسەڵات $i'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('دەسەڵات 2')).dy,
      greaterThan(tester.getTopLeft(find.text('دەسەڵات 0')).dy),
    );
    await tester.tap(find.text('دەسەڵات 2'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide content stays centered with a readable width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ZhiroxPageFrame(
            child: SizedBox(key: ValueKey('content'), height: 200),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('content'))).width, 960);
    expect(tester.getTopLeft(find.byKey(const ValueKey('content'))).dx, 220);
    expect(tester.takeException(), isNull);
  });
}
