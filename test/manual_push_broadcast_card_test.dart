import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/customer_push_service.dart';
import 'package:zhirox/widgets/manual_push_broadcast_card.dart';

class BroadcastGateway implements CustomerPushGateway {
  int broadcastCalls = 0;
  String? lastMessage;

  @override
  Future<CustomerPushSendResult> broadcastManual(String message) async {
    broadcastCalls++;
    lastMessage = message;
    return const CustomerPushSendResult(
      campaignId: '00000000-0000-0000-0000-000000000999',
      queuedCustomers: 18,
      targetDevices: 23,
      marketName: 'کانی چنار',
    );
  }

  @override
  Future<CustomerPushLink> createLink(String customerId) =>
      throw UnimplementedError();

  @override
  Future<CustomerPushOverviewPage> loadOverview({
    String search = '',
    int limit = 60,
    int offset = 0,
  }) =>
      throw UnimplementedError();

  @override
  Future<CustomerPushStatus> loadStatus(String customerId) =>
      throw UnimplementedError();

  @override
  Future<List<CustomerPushHistoryItem>> loadHistory(
    String customerId, {
    int limit = 20,
  }) =>
      throw UnimplementedError();

  @override
  Future<CustomerPushRetryResult> retryNotification(
    String customerId,
    String outboxId,
  ) =>
      throw UnimplementedError();

  @override
  Future<int> revokeAll(String customerId) => throw UnimplementedError();

  @override
  Future<CustomerPushSendResult> sendManual(String customerId, String message) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('manager can confirm and broadcast a market-branded notification',
      (tester) async {
    final gateway = BroadcastGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManualPushBroadcastCard(gateway: gateway),
        ),
      ),
    );

    expect(find.text('ئاگاداری گشتی'), findsOneWidget);
    await tester.tap(find.text('نووسینی ئاگاداری'));
    await tester.pumpAndSettle();

    expect(
      find.text('ناوی ئاگادارکردنەوە خۆکارانە ناوی سوپەرمارکێتەکەیە.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('broadcast-manual-push-message')),
      'ئەمڕۆ تا کاتژمێر 11 کراوەین.',
    );
    await tester.tap(find.text('بەردەوام بە'));
    await tester.pumpAndSettle();

    expect(
      find.text('ئەم پەیامە بۆ هەموو کڕیارە پەیوەستکراوەکان دەنێردرێت. دڵنیایت؟'),
      findsOneWidget,
    );
    await tester.tap(find.text('بەڵێ، بۆ هەمووان بنێرە'));
    await tester.pumpAndSettle();

    expect(gateway.broadcastCalls, 1);
    expect(gateway.lastMessage, 'ئەمڕۆ تا کاتژمێر 11 کراوەین.');
    expect(
      find.text('ئاگاداری بە ناوی کانی چنار بۆ 18 کڕیار / 23 ئامێر ڕیزکرا'),
      findsOneWidget,
    );
  });
}
