import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('admin settings exposes a clearly labeled notifications section', () {
    final source = File('lib/screens/admin/admin_settings_screen.dart')
        .readAsStringSync();

    const heading = "title: 'ئاگادارکردنەوەکان'";
    const card = 'const ManualPushBroadcastCard()';

    expect(source, contains(heading));
    expect(source, contains(card));
    expect(source.indexOf(heading), lessThan(source.indexOf(card)));
  });
}
