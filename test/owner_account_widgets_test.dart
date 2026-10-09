import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/widgets/app_design.dart';
import 'package:zhirox/widgets/owner_account_widgets.dart';

void main() {
  const market = 'مارکێتی ناوی درێژ بۆ پشکنینی خوێندراویی زانیاری';
  const admin = 'بەڕێوەبەری مارکێت بە ناوێکی درێژ';
  const phone = '07501234567';
  const details = 'چوونەژوورەوە: 2026/10/09 12:54 زانیاریی دەقی درێژ';

  for (final dark in [false, true]) {
    testWidgets('Owner account content wraps at large RTL text ($dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSurface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OwnerAccountIdentity(
                          marketName: market,
                          adminName: admin,
                          phone: phone,
                          icon: Icons.storefront_rounded,
                        ),
                        SizedBox(height: 8),
                        OwnerLifecycleBadge('grace'),
                        SizedBox(height: 12),
                        Wrap(
                          children: [
                            OwnerMetadata(Icons.history_rounded, details),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  OwnerMetricCard(
                    label: 'داهاتی پلاتفۆرم / ٣٠ ڕۆژ',
                    value: '123,456,789 د.ع',
                    icon: Icons.payments_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(market), findsOneWidget);
      expect(find.text(admin), findsOneWidget);
      expect(find.text('ماوەی ڕێگەپێدراو'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text &&
              widget.textSpan?.toPlainText(includePlaceholders: false) == details,
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(find.text(phone)).textDirection,
          TextDirection.ltr);
      expect(tester.widget<Text>(find.text(market)).maxLines, isNull);
      final marketRect = tester.getRect(find.text(market));
      final adminRect = tester.getRect(find.text(admin));
      final phoneRect = tester.getRect(find.text(phone));
      final statusRect = tester.getRect(find.text('ماوەی ڕێگەپێدراو'));
      expect(adminRect.top, greaterThanOrEqualTo(marketRect.bottom));
      expect(phoneRect.top, greaterThanOrEqualTo(adminRect.bottom));
      expect(statusRect.top, greaterThan(phoneRect.bottom));
    });

    testWidgets('Owner details and readiness badges wrap ($dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const label = 'کۆتا ڕێکخستنی نوێکردنەوەی سیستەم';
      const value = '2026/10/09 14:52:12';
      const check = 'ماوەی خزمەتگوزاریی پشتیوانی و پشتڕاستکردنەوە';
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
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: AppSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OwnerDetailRow(
                      icon: Icons.schedule_outlined,
                      label: label,
                      value: value,
                      valueDirection: TextDirection.ltr,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OwnerCheckBadge(
                          label: check,
                          ok: false,
                          icon: Icons.support_agent_outlined,
                        ),
                        OwnerCheckBadge(
                          label: 'پاشەکەوت پشتڕاستکراوە',
                          ok: true,
                          icon: Icons.backup_outlined,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final labelFinder = find.byWidgetPredicate(
        (widget) => widget is Text &&
            widget.textSpan?.toPlainText(includePlaceholders: false) == label,
      );
      expect(labelFinder, findsOneWidget);
      expect(find.text(value), findsOneWidget);
      expect(tester.getRect(find.text(value)).top,
          greaterThan(tester.getRect(labelFinder).bottom));
      expect(tester.widget<Text>(find.text(value)).textDirection,
          TextDirection.ltr);
      expect(find.byType(OwnerCheckBadge), findsNWidgets(2));
      final badgeRect = tester.getRect(find.byType(OwnerCheckBadge).first);
      expect(badgeRect.left, greaterThanOrEqualTo(16));
      expect(badgeRect.right, lessThanOrEqualTo(304));
    });
  }

  testWidgets('empty optional contacts do not create empty text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OwnerAccountIdentity(
            marketName: market,
            adminName: '',
            phone: '',
            icon: Icons.storefront_rounded,
          ),
        ),
      ),
    );
    expect(find.text(market), findsOneWidget);
    expect(find.text(''), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
