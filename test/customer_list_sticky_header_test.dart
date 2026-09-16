import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/services/user_list_layout.dart';

void main() {
  group('customer list sticky header', () {
    test('customer header stays pinned while the directory scrolls', () {
      expect(shouldPinUserListHeader('customer'), isTrue);
    });

    test('employee list keeps the existing scrolling header behavior', () {
      expect(shouldPinUserListHeader('employee'), isFalse);
    });
  });
}
