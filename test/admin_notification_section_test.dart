import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin settings exposes a clearly labeled notification center', () {
    final settings = File('lib/screens/admin/admin_settings_screen.dart')
        .readAsStringSync();
    final center = File('lib/screens/admin/admin_notifications_screen.dart')
        .readAsStringSync();

    const heading = "title: 'ئاگادارکردنەوەکان'";
    const entry = "title: 'ناوەندی ئاگادارکردنەوەکان'";

    expect(settings, contains(heading));
    expect(settings, contains(entry));
    expect(settings, contains('AdminNotificationsScreen'));
    expect(settings.indexOf(heading), lessThan(settings.indexOf(entry)));

    expect(center, contains('ManualPushBroadcastCard'));
    expect(center, contains('loadOverview'));
    expect(center, contains('ئاگادارکردنەوەکان'));
  });
}
