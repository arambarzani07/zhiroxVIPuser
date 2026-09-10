import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Lightweight connectivity monitor for the online-only ZHIROX app.
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _statusController =
      StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  bool _isOnline = true;
  bool _initialized = false;

  bool get isOnline => _isOnline;
  Stream<bool> get statusStream => _statusController.stream;

  Future<void> init() async {
    if (_initialized) {
      await checkNow();
      return;
    }
    _initialized = true;

    try {
      final results = await _connectivity.checkConnectivity();
      _setOnline(
        results.any((r) => r != ConnectivityResult.none),
        forceNotify: true,
      );

      _connectivitySub = _connectivity.onConnectivityChanged.listen(
        (results) {
          _setOnline(results.any((r) => r != ConnectivityResult.none));
        },
        onError: (_) => _setOnline(false),
      );
    } catch (_) {
      _initialized = false;
      _setOnline(false, forceNotify: true);
      rethrow;
    }
  }

  void _setOnline(bool online, {bool forceNotify = false}) {
    final changed = _isOnline != online;
    _isOnline = online;
    if ((changed || forceNotify) && !_statusController.isClosed) {
      _statusController.add(online);
    }
  }

  Future<bool> checkNow() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _setOnline(results.any((r) => r != ConnectivityResult.none));
    } catch (_) {
      _setOnline(false);
    }
    return _isOnline;
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    if (!_statusController.isClosed) {
      await _statusController.close();
    }
  }
}
