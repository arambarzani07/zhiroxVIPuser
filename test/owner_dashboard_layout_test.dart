import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/screens/auth/owner_dashboard.dart';
import 'package:zhirox/widgets/app_design.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'owner groups remain reachable with large Kurdish text ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppDesign.ownerDarkTheme : AppDesign.ownerLightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
            home: const OwnerDashboard(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('ناوەندی خاوەن'), findsOneWidget);
        final group = find.text('پاراستن و بەردەوامی');
        await tester.scrollUntilVisible(
          group,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(tester.element(group), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(group);
        await tester.pumpAndSettle();
        final security = find.text('ناوەندی پاراستن');
        await tester.scrollUntilVisible(
          security,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(security, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
