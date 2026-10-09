import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/screens/auth/admin_management_screen.dart';
import 'package:zhirox/widgets/app_design.dart';

void main() {
  const marketName = 'مارکێتی ناوی درێژ بۆ تاقیکردنەوەی خوێندنەوە';
  final admin = RecordModel.fromJson({
    'id': 'test-market-admin',
    'market_name': marketName,
    'name': 'بەڕێوەبەری مارکێت',
    'phone': '07501234567',
    'subscription_plan': 'monthly',
    'subscription_end': '2030-01-01T00:00:00Z',
  });

  for (final dark in [false, true]) {
    testWidgets('market card wraps large Sorani text ($dark)', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? renewedAdmin;
      String? renewedPlan;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppDesign.ownerDarkTheme : AppDesign.ownerLightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: OwnerMarketCard(
                data: {'admin': admin},
                isDark: dark,
                onRenew: (id, plan) {
                  renewedAdmin = id;
                  renewedPlan = plan;
                },
                onResetPassword: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(marketName), findsOneWidget);
      expect(tester.widget<Text>(find.text(marketName)).maxLines, isNull);
      expect(find.text('بەڕێوەبەری مارکێت'), findsOneWidget);
      expect(find.text('07501234567'), findsOneWidget);
      await tester.tap(find.byTooltip('کردارەکان'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('نوێکردنەوەی بەشداری'));
      await tester.pumpAndSettle();
      expect(renewedAdmin, admin.id);
      expect(renewedPlan, 'monthly');
      expect(tester.takeException(), isNull);
    });
  }
}
