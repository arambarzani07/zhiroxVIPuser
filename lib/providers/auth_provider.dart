import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/market_ui_policy.dart';

class AuthProvider extends ChangeNotifier {
  static const _secureStorage = FlutterSecureStorage();
  RecordModel? _user;
  bool _isLoading = false;
  bool _isInitializing = true;

  RecordModel? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;
  String get userRole => _user?.getStringValue('role') ?? '';
  String get userId => _user?.id ?? '';
  String get userName => _user?.getStringValue('name') ?? '';

  bool get isManager => userRole == ZhiroxRoles.manager;
  bool get isEmployee => userRole == ZhiroxRoles.employee;
  bool get isCustomer => userRole == ZhiroxRoles.customer;
  bool get hasVisibleMarketRole => ZhiroxRoles.isVisibleRole(userRole);

  String get roleDisplayName => ZhiroxRoles.label(userRole);

  String get adminId {
    if (isManager) return userId;
    return _user?.getStringValue('admin_id') ?? '';
  }

  String get marketName => _user?.getStringValue('market_name') ?? '';

  int get subscriptionDaysLeft {
    if (_user == null) return 9999;
    String subEnd = '';
    if (isManager) {
      subEnd = _user!.getStringValue('subscription_end');
    }
    if (subEnd.isEmpty) return 9999;
    final endDate = DateTime.parse(subEnd);
    return endDate.difference(DateTime.now()).inDays;
  }

  String get userFullName {
    final name = _user?.getStringValue('name') ?? '';
    final father = _user?.getStringValue('father_name') ?? '';
    final grandfather = _user?.getStringValue('grandfather_name') ?? '';
    return '$name $father $grandfather'.trim();
  }

  bool get canAddCustomers {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_add_customers') ?? false;
    return false;
  }

  bool get canGiveDebt {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_add_debts') ?? true;
    return false;
  }

  bool get canReceivePayment {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_receive_payments') ?? true;
    return false;
  }

  bool get canCreateStatement {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_create_statements') ?? true;
    return isCustomer;
  }

  bool get canViewReports {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_view_reports') ?? false;
    return false;
  }

  bool get canApproveSensitiveActions => isManager;

  bool get canSetDebtLimit {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_set_debt_limit') ?? false;
    return false;
  }

  bool get canSetDueDate {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_set_due_date') ?? false;
    return false;
  }

  bool get canEditDebts {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_edit_debts') ?? false;
    return false;
  }

  bool get canSendNotifications {
    if (isManager) return true;
    if (isEmployee) return _user?.getBoolValue('can_send_notifications') ?? false;
    return false;
  }

  double get debtLimit => _user?.getDoubleValue('debt_limit') ?? 0;

  bool _disposed = false;
  bool wasDeactivated = false;

  void clearDeactivatedFlag() {
    wasDeactivated = false;
  }

  AuthProvider() {
    _loadSavedUser();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_user != null) {
      try {
        PBService.pb.collection('users').unsubscribe(_user!.id);
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _clearSavedUser() async {
    _user = null;
    await _secureStorage.delete(key: 'user_id');
    await _secureStorage.delete(key: 'user_data');
  }

  bool _acceptOnlyVisibleMarketRole() {
    if (_user == null) return false;
    return ZhiroxRoles.isVisibleRole(userRole);
  }

  void _subscribeToUserChanges() {
    if (_user == null || !isEmployee) return;
    final uid = _user!.id;
    try {
      PBService.pb.collection('users').subscribe(uid, (event) async {
        if (event.record == null || _disposed) return;
        final isActive = event.record!.getBoolValue('active');
        final isApproved = event.record!.getBoolValue('approved');
        if ((!isActive || !isApproved) && isEmployee) {
          wasDeactivated = true;
          await logout();
          return;
        }
        _user = event.record;
        if (!_acceptOnlyVisibleMarketRole()) {
          await _clearSavedUser();
        }
        notifyListeners();
      });
    } catch (_) {}
  }

  Future<void> _loadSavedUser() async {
    final userId = await _secureStorage.read(key: 'user_id');
    if (userId != null) {
      try {
        _user = await PBService.getUser(userId);
        if (!_acceptOnlyVisibleMarketRole()) {
          await _clearSavedUser();
        } else {
          await _secureStorage.write(key: 'user_data', value: jsonEncode(_user!.toJson()));
          if (isEmployee) _subscribeToUserChanges();
        }
      } catch (_) {
        final userDataString = await _secureStorage.read(key: 'user_data');
        if (userDataString != null) {
          try {
            _user = RecordModel.fromJson(jsonDecode(userDataString));
            if (!_acceptOnlyVisibleMarketRole()) {
              await _clearSavedUser();
            }
          } catch (_) {}
        }
        if (_user == null) {
          await _clearSavedUser();
        }
      }
    }
    _isInitializing = false;
    notifyListeners();
  }

  Future<void> refreshUser() async {
    if (_user == null) return;
    try {
      _user = await PBService.getUser(_user!.id);
      if (!_acceptOnlyVisibleMarketRole()) {
        await _clearSavedUser();
      }
      notifyListeners();
    } catch (_) {}
  }

  static const String kFailedAttemptsKey = 'failed_login_attempts';
  static const String kLockoutTimeKey = 'login_lockout_time';

  Future<void> _checkLockout() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutTimeStr = prefs.getString(kLockoutTimeKey);
    if (lockoutTimeStr != null) {
      final lockoutTime = DateTime.parse(lockoutTimeStr);
      if (DateTime.now().isBefore(lockoutTime)) {
        final diff = lockoutTime.difference(DateTime.now());
        final minutes = diff.inMinutes;
        final seconds = diff.inSeconds % 60;
        throw 'تکایە $minutes:$seconds خولەک چاوەڕێ بکە';
      }
      await prefs.remove(kLockoutTimeKey);
      await prefs.remove(kFailedAttemptsKey);
    }
  }

  Future<void> _handleLoginFailure() async {
    final prefs = await SharedPreferences.getInstance();
    int attempts = (prefs.getInt(kFailedAttemptsKey) ?? 0) + 1;
    if (attempts >= 3) {
      final lockoutTime = DateTime.now().add(const Duration(minutes: 3));
      await prefs.setString(kLockoutTimeKey, lockoutTime.toIso8601String());
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
      } catch (e) {
        if (e is String) rethrow;
        await _handleLoginFailure();
        throw 'وشەی نهێنی یان ژمارە مۆبایل هەڵەیە';
      }

      if (!_acceptOnlyVisibleMarketRole()) {
        await _clearSavedUser();
        throw 'ئەم هەژمارە بۆ ئەم سیستەمە چالاک نییە';
      }

      if (isEmployee) _subscribeToUserChanges();
      await _secureStorage.write(key: 'user_id', value: _user!.id);
      await _secureStorage.write(key: 'user_data', value: jsonEncode(_user!.toJson()));
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kLockoutTimeKey);
      await prefs.remove(kFailedAttemptsKey);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (_) {
      _isLoading = false;
      notifyListeners();
      rethrow;
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
      notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> logout() async {
    if (_user != null) {
      try {
        await PBService.pb.collection('users').unsubscribe(_user!.id);
      } catch (_) {}
    }
    try {
      await PBService.pb.collection('debts').unsubscribe();
      await PBService.pb.collection('payments').unsubscribe();
      await PBService.pb.collection('notifications').unsubscribe();
    } catch (_) {}
    await _clearSavedUser();
    notifyListeners();
  }
}
