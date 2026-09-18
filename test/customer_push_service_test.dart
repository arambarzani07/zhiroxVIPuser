import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/customer_push_service.dart';

void main() {
  test('push status parses active link count', () {
    final status = CustomerPushStatus.fromJson({
      'active': true,
      'device_count': 2,
      'active_link_count': 3,
      'latest_status': 'sent',
      'latest_at': '2026-09-17T00:00:00Z',
    });

    expect(status.active, isTrue);
    expect(status.deviceCount, 2);
    expect(status.activeLinkCount, 3);
    expect(status.hasActiveLink, isTrue);
    expect(status.latestStatus, 'sent');
    expect(status.latestAt, DateTime.parse('2026-09-17T00:00:00Z'));
  });

  test('push status rejects malformed success payloads', () {
    expect(
      () => CustomerPushStatus.fromJson({
        'active': 'yes',
        'device_count': 2,
        'active_link_count': 1,
        'latest_status': null,
        'latest_at': null,
      }),
      throwsFormatException,
    );
    expect(
      () => CustomerPushStatus.fromJson({
        'active': false,
        'device_count': 0,
        'active_link_count': -1,
        'latest_status': null,
        'latest_at': null,
      }),
      throwsFormatException,
    );
  });

  test('push link accepts a permanent onboarding URL with null expiry', () {
    final link = CustomerPushLink.fromJson({
      'url': 'https://push.zhirox.com/?token=${'a' * 64}',
      'expires_at': null,
    });

    expect(link.url.isAbsolute, isTrue);
    expect(link.url.queryParameters['token'], 'a' * 64);
    expect(link.expiresAt, isNull);
  });

  test('manual send result parses campaign and audience counts', () {
    final result = CustomerPushSendResult.fromJson({
      'campaign_id': '00000000-0000-0000-0000-000000000999',
      'queued_customers': 18,
      'target_devices': 23,
      'market_name': 'کانی چنار',
    });

    expect(result.campaignId, '00000000-0000-0000-0000-000000000999');
    expect(result.queuedCustomers, 18);
    expect(result.targetDevices, 23);
    expect(result.marketName, 'کانی چنار');
  });

  test('service sends exact admin actions and parses permanent replies', () async {
    final calls = <Map<String, dynamic>>[];
    final service = CustomerPushService(
      invoker: (body) async {
        calls.add(Map<String, dynamic>.from(body));
        switch (body['action']) {
          case 'overview':
            return {
              'items': [
                {
                  'customer_id': '00000000-0000-0000-0000-000000000123',
                  'name': 'سادار',
                  'phone': '07501234567',
                  'active': true,
                  'device_count': 2,
                  'active_link_count': 1,
                  'latest_status': 'sent',
                  'latest_at': '2026-09-18T08:00:00Z',
                },
              ],
              'total_count': 1,
              'offset': 0,
              'limit': 60,
              'has_more': false,
              'filter': 'active',
              'summary': {
                'all': 3,
                'active': 1,
                'inactive': 2,
                'failed': 0,
                'pending': 0,
              },
            };
          case 'status':
            return {
              'active': true,
              'device_count': 3,
              'active_link_count': 2,
              'latest_status': 'sent',
              'latest_at': '2026-09-17T00:00:00Z',
            };
          case 'create_link':
            return {
              'url': 'https://push.zhirox.com/?token=${'b' * 64}',
              'expires_at': null,
            };
          case 'revoke_all':
            return {'revoked_count': 3};
          case 'send_manual':
          case 'broadcast_manual':
            return {
              'campaign_id': '00000000-0000-0000-0000-000000000999',
              'queued_customers': body['action'] == 'send_manual' ? 1 : 18,
              'target_devices': body['action'] == 'send_manual' ? 2 : 23,
              'market_name': 'کانی چنار',
            };
        }
        throw StateError('unexpected action');
      },
    );

    final overview = await service.loadOverview(
      search: 'سادار',
      filter: 'active',
    );
    final status = await service.loadStatus('customer-1');
    final link = await service.createLink('customer-1');
    final revoked = await service.revokeAll('customer-1');
    final single = await service.sendManual(
      'customer-1',
      '  کاڵای نوێ گەیشت.  ',
    );
    final broadcast = await service.broadcastManual(
      '  ئەمڕۆ تا کاتژمێر 11 کراوەین.  ',
    );

    expect(overview.items.single.name, 'سادار');
    expect(overview.filter, 'active');
    expect(overview.summary.all, 3);
    expect(overview.summary.active, 1);
    expect(status.deviceCount, 3);
    expect(status.activeLinkCount, 2);
    expect(link.url.queryParameters['token'], 'b' * 64);
    expect(link.expiresAt, isNull);
    expect(revoked, 3);
    expect(single.queuedCustomers, 1);
    expect(single.targetDevices, 2);
    expect(single.marketName, 'کانی چنار');
    expect(broadcast.queuedCustomers, 18);
    expect(broadcast.targetDevices, 23);
    expect(calls, [
      {
        'action': 'overview',
        'search': 'سادار',
        'filter': 'active',
        'limit': 60,
        'offset': 0,
      },
      {'action': 'status', 'customer_id': 'customer-1'},
      {'action': 'create_link', 'customer_id': 'customer-1'},
      {'action': 'revoke_all', 'customer_id': 'customer-1'},
      {
        'action': 'send_manual',
        'customer_id': 'customer-1',
        'message': 'کاڵای نوێ گەیشت.',
      },
      {
        'action': 'broadcast_manual',
        'message': 'ئەمڕۆ تا کاتژمێر 11 کراوەین.',
      },
    ]);
  });

  test('service validates manual messages before invoking backend', () async {
    var calls = 0;
    final service = CustomerPushService(
      invoker: (_) async {
        calls++;
        return {};
      },
    );

    await expectLater(
      service.sendManual('customer-1', '   '),
      throwsArgumentError,
    );
    await expectLater(
      service.broadcastManual('x' * 241),
      throwsArgumentError,
    );
    expect(calls, 0);
  });

  test('service rejects malformed admin success payloads', () async {
    final service = CustomerPushService(
      invoker: (_) async => {'revoked_count': 'three'},
    );

    await expectLater(service.revokeAll('customer-1'), throwsFormatException);
  });
}
