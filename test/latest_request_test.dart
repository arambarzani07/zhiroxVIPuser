import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zhirox/utils/latest_request.dart';

void main() {
  test('late market response cannot replace the newer market', () async {
    final requests = LatestRequest();
    final first = Completer<String>();
    final second = Completer<String>();
    String? visibleMarket;

    Future<void> load(Future<String> response) async {
      final request = requests.begin();
      final market = await response;
      if (requests.isCurrent(request)) visibleMarket = market;
    }

    final firstLoad = load(first.future);
    final secondLoad = load(second.future);
    second.complete('market-b');
    await secondLoad;
    first.complete('market-a');
    await firstLoad;
    expect(visibleMarket, 'market-b');
  });

  test('search edits invalidate responses before the debounce completes', () {
    final requests = LatestRequest();
    final previousSearch = requests.begin();
    requests.invalidate();
    expect(requests.isCurrent(previousSearch), isFalse);
    final nextSearch = requests.begin();
    expect(requests.isCurrent(nextSearch), isTrue);
    expect(requests.isCurrent(previousSearch), isFalse);
  });

  test('stale failure and cleanup cannot clear a newer loading state', () async {
    final requests = LatestRequest();
    final oldResponse = Completer<void>();
    final oldRequest = requests.begin();
    String? error;
    var loading = true;
    final oldLoad = (() async {
      try {
        await oldResponse.future;
      } catch (_) {
        if (requests.isCurrent(oldRequest)) error = 'old failure';
      } finally {
        if (requests.isCurrent(oldRequest)) loading = false;
      }
    })();
    final newRequest = requests.begin();
    oldResponse.completeError(StateError('network failure'));
    await oldLoad;
    expect(error, isNull);
    expect(loading, isTrue);
    expect(requests.isCurrent(newRequest), isTrue);
  });
}
