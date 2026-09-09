import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/services/pb_service.dart';

class AuthProvider extends ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();

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

  String get adminId {
    if (userRole == 'admin') return userId;
    return _user?.getStringValue('admin_id') ?? '';
  }

  String get marketName => _user?.getStringValue('market_name') ?? '';

  int get subscriptionDaysLeft {
    if (_user == null || userRole != 'admin') return 9999;
    final subEnd = _user!.getStringValue('subscription_end');
    if (subEnd.isEmpty) return 9999;
    final date = DateTime.tryParse(subEnd);
    return date == null ? 9999 : date.difference(DateTime.now()).inDays;
  }

  String get userFullName {
    final parts = [
      _user?.getStringValue('name') ?? '',
      _user?.getStringValue('father_name') ?? '',
      _user?.getStringValue('grandfather_name') ?? '',
    ].where((e) => e.trim().isNotEmpty);
    return parts.join(' ');
  }

  bool get canAddCustomers => userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_add_customers') ?? false));

  bool get canSetDebtLimit => userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_set_debt_limit') ?? false));

  bool get canSetDueDate => userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_set_due_date') ?? false));

  bool get canEditDebts => userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_edit_debts') ?? false));

  bool get canSendNotifications => userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_send_notifications') ?? false));

  double get debtLimit => _user?.getDoubleValue('debt_limit') ?? 0;

  bool wasDeactivated = false;

  void clearDeactivatedFlag() => wasDeactivated = false;

  AuthProvider() {
    _loadSavedUser();
  }

  @override
  void dispose() {
    _disposed = true;
    final current = _user;
    if (current != null) {
      unawaited(PBService.pb.collection('users').unsubscribe(current.id));
    }
    super.dispose();
  }

  void _subscribeToUserChanges() {
    final current = _user;
    if (current == null) return;

    unawaited(
      PBService.pb.collection('users').subscribe(current.id, (event) async {
        if (_disposed || event.record == null) return;
        final updated = event.record!;
        final role = updated.getStringValue('role');
        final active = updated.getBoolValue('active');
        final approved = updated.getBoolValue('approved');

        if (role == 'employee' && (!active || !approved)) {
          wasDeactivated = true;
          await logout();
          return;
        }

        _user = updated;
        await _cacheUser();
        if (!_disposed) notifyListeners();
      }),
    );
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

  Future<void> _validateSubscription() async {
    final current = _user;
    if (current == null) return;

    if (userRole == 'admin') {
      final subEnd = current.getStringValue('subscription_end');
      final date = DateTime.tryParse(subEnd);
      if (date != null && date.isBefore(DateTime.now())) {
        throw 'ماوەی ڕێکەوتنی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بۆ نوێکردنەوە.';
      }
      return;
    }

    if (userRole == 'employee' || userRole == 'customer') {
      final aId = current.getStringValue('admin_id');
      if (aId.isEmpty) return;
      final admin = await PBService.getUser(aId);
      final subEnd = admin.getStringValue('subscription_end');
      final date = DateTime.tryParse(subEnd);
      if (date != null && date.isBefore(DateTime.now())) {
        throw 'ماوەی ڕێکەوتنی بەڕێوەبەرەکەت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەرەکەت.';
      }
    }
  }

  Future<void> _loadSavedUser() async {
    try {
      await PBService.ensureInitialized();
      final authUser = PBService.client.auth.currentUser;
      if (authUser == null) {
        await _clearLocalUser();
        return;
      }

      try {
        _user = await PBService.getUser(authUser.id);
        await _validateSubscription();
        await _cacheUser();
      } catch (_) {
        // Network fallback is allowed only while a real Supabase session exists.
        final cached = await _secureStorage.read(key: 'user_data');
        if (PBService.client.auth.currentSession != null && cached != null) {
          try {
            _user = RecordModel.fromJson(
              Map<String, dynamic>.from(jsonDecode(cached) as Map),
            );
          } catch (_) {
            await _clearLocalUser();
          }
        } else {
          await _clearLocalUser();
        }
      }

      if (userRole == 'employee') _subscribeToUserChanges();
    } finally {
      _isInitializing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> refreshUser() async {
    final current = _user;
    if (current == null) return;
    try {
      _user = await PBService.getUser(current.id);
      await _cacheUser();
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  static const String kFailedAttemptsKey = 'failed_login_attempts';
  static const String kLockoutTimeKey = 'login_lockout_time';

  Future<void> _checkLockout() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(kLockoutTimeKey);
    if (value == null) return;

    final lockout = DateTime.tryParse(value);
    if (lockout != null && DateTime.now().isBefore(lockout)) {
      final diff = lockout.difference(DateTime.now());
      throw 'تکایە ${diff.inMinutes}:${(diff.inSeconds % 60).toString().padLeft(2, '0')} خولەک چاوەڕێ بکە';
    }
    await prefs.remove(kLockoutTimeKey);
    await prefs.remove(kFailedAttemptsKey);
  }

  Future<void> _handleLoginFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(kFailedAttemptsKey) ?? 0) + 1;
    if (attempts >= 3) {
      final lockout = DateTime.now().add(const Duration(minutes: 3));
      await prefs.setString(kLockoutTimeKey, lockout.toIso8601String());
      await prefs.setInt(kFailedAttemptsKey, 0);
      throw '٣ جار وشەی نهێنیت بە هەڵە داخڵ کرد. بۆ ماوەی ٣ خولەک ڕاگیرایت.';
    }
    await prefs.setInt(kFailedAttemptsKey, attempts);
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _checkLockout();
      try {
        _user = await PBService.login(phone, password);
        await _validateSubscription();
      } catch (e) {
        await PBService.logout();
        await _clearLocalUser();
        if (e is String) rethrow;
        await _handleLoginFailure();
        throw 'وشەی نهێنی یان ژمارە مۆبایل هەڵەیە';
      }

      if (userRole == 'employee') _subscribeToUserChanges();
      await _cacheUser();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kLockoutTimeKey);
      await prefs.remove(kFailedAttemptsKey);

      return true;
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> registerAdmin({
    required String marketName,
    required String adminName,
    required String phone,
    required String password,
    required int subscriptionDays,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      await PBService.registerAdmin(
        marketName: marketName,
        adminName: adminName,
        phone: phone,
        password: password,
        subscriptionDays: subscriptionDays,
      );
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> registerCustomer({
    required String name,
    required String phone,
    required String password,
    required String adminId,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      await PBService.registerCustomer(
        name: name,
        phone: phone,
        password: password,
        adminId: adminId,
      );
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> logout() async {
    final current = _user;
    if (current != null) {
      try {
        await PBService.pb.collection('users').unsubscribe(current.id);
      } catch (_) {}
    }
    try {
      await PBService.pb.collection('debts').unsubscribe();
      await PBService.pb.collection('payments').unsubscribe();
      await PBService.pb.collection('notifications').unsubscribe();
    } catch (_) {}

    await PBService.logout();
    await _clearLocalUser();
    if (!_disposed) notifyListeners();
  }
}
