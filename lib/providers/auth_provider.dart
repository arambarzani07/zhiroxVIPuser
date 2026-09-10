import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/services/pb_service.dart';

/// Authentication state for the end-user/customer application only.
///
/// Admin/employee/platform roles are C-Panel concerns and are intentionally not
/// represented as privileged states in this provider.
class AuthProvider extends ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();
  static const String kFailedAttemptsKey = 'failed_login_attempts';
  static const String kLockoutTimeKey = 'login_lockout_time';

  RecordModel? _user;
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _disposed = false;

  RecordModel? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String get userRole => _user?.getStringValue('role') ?? '';
  String get userId => _user?.id ?? '';
  String get userName => _user?.getStringValue('name') ?? '';
  String get adminId => _user?.getStringValue('admin_id') ?? '';
  String get marketName => _user?.getStringValue('market_name') ?? '';
  double get debtLimit => _user?.getDoubleValue('debt_limit') ?? 0;

  String get userFullName {
    return [
      _user?.getStringValue('name') ?? '',
      _user?.getStringValue('father_name') ?? '',
      _user?.getStringValue('grandfather_name') ?? '',
    ].where((part) => part.trim().isNotEmpty).join(' ');
  }

  AuthProvider() {
    _restore();
  }

  @override
  void dispose() {
    _disposed = true;
    final current = _user;
    if (current != null) {
      PBService.pb.collection('users').unsubscribe(current.id);
    }
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _assertCustomer(RecordModel user) {
    if (user.getStringValue('role') != 'customer') {
      throw 'ئەم هەژمارە تایبەت بە ئەپی بەکارهێنەر نییە';
    }
    if (!user.getBoolValue('approved')) {
      throw 'هێشتا داواکاریت قبوڵ نەکراوە';
    }
    if (!user.getBoolValue('active')) {
      throw 'ئەم هەژمارە ناچالاکە';
    }
    if (!user.getBoolValue('subscription_active')) {
      throw 'ماوەی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەر.';
    }
  }

  Future<void> _cacheUser() async {
    final current = _user;
    if (current == null) return;
    await _secureStorage.write(key: 'user_id', value: current.id);
    await _secureStorage.write(
      key: 'user_data',
      value: jsonEncode(current.toJson()),
    );
  }

  Future<void> _clearLocalUser() async {
    _user = null;
    await _secureStorage.delete(key: 'user_id');
    await _secureStorage.delete(key: 'user_data');
  }

  Future<void> _restore() async {
    try {
      final restored = await PBService.restoreSession();
      if (restored == null) {
        await _clearLocalUser();
        return;
      }
      _assertCustomer(restored);
      _user = restored;
      await _cacheUser();
      _subscribeToSelf();
    } catch (_) {
      await PBService.logout();
      await _clearLocalUser();
    } finally {
      _isInitializing = false;
      _notify();
    }
  }

  void _subscribeToSelf() {
    final current = _user;
    if (current == null) return;

    PBService.pb.collection('users').subscribe(current.id, (event) async {
      if (_disposed || event.record == null) return;
      final updated = event.record!;
      try {
        _assertCustomer(updated);
      } catch (_) {
        await logout();
        return;
      }
      _user = updated;
      await _cacheUser();
      _notify();
    });
  }

  Future<void> refreshUser() async {
    final current = _user;
    if (current == null) return;
    try {
      final refreshed = await PBService.refreshCurrentUser();
      _assertCustomer(refreshed);
      _user = refreshed;
      await _cacheUser();
      _notify();
    } catch (_) {
      await logout();
    }
  }

  Future<void> _checkLockout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kLockoutTimeKey);
    if (raw == null) return;

    final until = DateTime.tryParse(raw);
    if (until != null && DateTime.now().isBefore(until)) {
      final diff = until.difference(DateTime.now());
      throw 'تکایە ${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')} خولەک چاوەڕێ بکە';
    }
    await prefs.remove(kLockoutTimeKey);
    await prefs.remove(kFailedAttemptsKey);
  }

  Future<void> _recordFailedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(kFailedAttemptsKey) ?? 0) + 1;
    if (attempts >= 3) {
      await prefs.setInt(kFailedAttemptsKey, 0);
      await prefs.setString(
        kLockoutTimeKey,
        DateTime.now().add(const Duration(minutes: 3)).toIso8601String(),
      );
      throw '٣ جار زانیاریی چوونەژوورەوەت هەڵە بوو. بۆ ٣ خولەک ڕاگیرایت.';
    }
    await prefs.setInt(kFailedAttemptsKey, attempts);
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    _notify();

    try {
      await _checkLockout();
      try {
        final authenticated = await PBService.login(phone, password);
        _assertCustomer(authenticated);
        _user = authenticated;
      } catch (e) {
        await PBService.logout();
        await _clearLocalUser();
        try {
          await _recordFailedLogin();
        } catch (lockout) {
          if (lockout is String) throw lockout;
          rethrow;
        }
        if (e is String) throw e;
        throw 'ژمارە مۆبایل یان وشەی نهێنی هەڵەیە';
      }

      await _cacheUser();
      _subscribeToSelf();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kLockoutTimeKey);
      await prefs.remove(kFailedAttemptsKey);
      return true;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> registerCustomer({
    required String name,
    required String phone,
    required String password,
    required String adminId,
  }) async {
    _isLoading = true;
    _notify();
    try {
      await PBService.registerCustomer(
        name: name,
        phone: phone,
        password: password,
        adminId: adminId,
      );
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> logout() async {
    final current = _user;
    if (current != null) {
      await PBService.pb.collection('users').unsubscribe(current.id);
    }
    await PBService.pb.collection('debts').unsubscribe();
    await PBService.pb.collection('payments').unsubscribe();
    await PBService.pb.collection('notifications').unsubscribe();
    await PBService.logout();
    await _clearLocalUser();
    _notify();
  }
}
