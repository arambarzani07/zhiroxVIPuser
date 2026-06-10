import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Lightweight connectivity monitor.
/// Uses only system network state (WiFi / mobile data).
/// Does NOT ping the server - avoids false offline on slow mobile.
/// When connectivity returns, notifies listeners so screens auto-reload.
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
    if (_initialized) return;
    _initialized = true;

    // Initial check
    final results = await _connectivity.checkConnectivity();
    _isOnline = results.any((r) => r != ConnectivityResult.none);

    // Listen for changes
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (_isOnline != online) {
        _isOnline = online;
        _statusController.add(online);
      }
    });
  }

  /// Force a connectivity check right now
  Future<bool> checkNow() async {
    final results = await _connectivity.checkConnectivity();
    final online = results.any((r) => r != ConnectivityResult.none);
    if (_isOnline != online) {
      _isOnline = online;
      _statusController.add(online);
    }
    return _isOnline;
  }

  void dispose() {
    _connectivitySub?.cancel();
    _statusController.close();
  }
}
