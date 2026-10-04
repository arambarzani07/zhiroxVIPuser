import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/hikvision_admin_service.dart';

void main() {
  test('server state controls gateway status independently of phone time', () {
    final health = GatewayHealth.fromMap({
      'status': 'offline',
      'alerts_enabled': true,
      'last_seen_at': '2099-01-01T00:00:00Z',
      'events': [
        {'state': 'offline', 'id': 'event-1'},
      ],
    });
    expect(health.status, 'offline');
    expect(health.label, contains('پچڕاوە'));
    expect(health.alertsEnabled, isTrue);
    expect(health.events.single['id'], 'event-1');
    expect(
      GatewayHealth.fromMap({'status': 'online'}).label,
      contains('چالاکە'),
    );
    expect(GatewayHealth.fromMap({}).status, 'unknown');
    expect(GatewayHealth.fromMap({}).alertsEnabled, isFalse);
  });
}
