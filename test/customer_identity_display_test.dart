import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/utils/customer_identity_display.dart';

void main() {
  test('legacy technical phone is hidden and exposes Daftar source id', () {
    const raw = 'legacy_d3cc5c6e_14156';
    expect(CustomerIdentityDisplay.isLegacyPlaceholderPhone(raw), isTrue);
    expect(CustomerIdentityDisplay.visiblePhone(raw), isEmpty);
    expect(CustomerIdentityDisplay.legacySourceId(raw), '14156');
    expect(CustomerIdentityDisplay.identityTail(raw), '#14156');
  });

  test('real phone remains visible and uses last four digits as identity tail', () {
    const raw = '07504048383';
    expect(CustomerIdentityDisplay.isLegacyPlaceholderPhone(raw), isFalse);
    expect(CustomerIdentityDisplay.visiblePhone(raw), raw);
    expect(CustomerIdentityDisplay.legacySourceId(raw), isNull);
    expect(CustomerIdentityDisplay.identityTail(raw), '8383');
  });

  test('localized digits normalize for real-phone identity tail', () {
    expect(CustomerIdentityDisplay.identityTail('٠٧٥٠٤٠٤٨٣٨٣'), '8383');
    expect(CustomerIdentityDisplay.identityTail('۰۷۵۰۴۰۴۸۳۸۳'), '8383');
  });
}
