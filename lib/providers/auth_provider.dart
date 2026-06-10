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

  /// Days left on admin subscription (for display in dashboard)
  int get subscriptionDaysLeft {
    if (_user == null) return 9999;
    final role = userRole;
    String subEnd = '';
    if (role == 'admin') {
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
    return '$name $father $grandfather';
  }

  // Permissions for Employees
  bool get canAddCustomers {
    if (userRole == 'admin') return true;
    if (userRole == 'employee') {
      // Allow if 'can_add_customers' is true
      return _user?.getBoolValue('can_add_customers') ?? false;
    }
    return false;
  }

  bool get canSetDebtLimit {
    if (userRole == 'admin') return true;
    if (userRole == 'employee') {
      return _user?.getBoolValue('can_set_debt_limit') ?? false;
    }
    return false;
  }

  bool get canSetDueDate {
    if (userRole == 'admin') return true;
    if (userRole == 'employee') {
      return _user?.getBoolValue('can_set_due_date') ?? false;
    }
    return false;
  }

  bool get canEditDebts {
    if (userRole == 'admin') return true;
    if (userRole == 'employee') {
      return _user?.getBoolValue('can_edit_debts') ?? false;
    }
    return false;
  }

  bool get canSendNotifications {
    if (userRole == 'admin') return true;
    if (userRole == 'employee') {
      return _user?.getBoolValue('can_send_notifications') ?? false;
    }
    return false;
  }

  // Debt Limit for Customers (if logged in as customer, though usually checked on record)
  double get debtLimit => _user?.getDoubleValue('debt_limit') ?? 0;

  // Track if this provider is still alive
  bool _disposed = false;

  /// Set to true when admin deactivates this employee remotely.
  /// The UI reads this to show a "ناچالاک کرایت" message before redirecting.
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
    // Unsubscribe from user-specific realtime updates
    if (_user != null) {
      try {
        PBService.pb.collection('users').unsubscribe(_user!.id);
      } catch (_) {}
    }
    super.dispose();
  }

  /// Subscribe to real-time changes on the logged-in user's record.
  /// This ensures permissions update instantly when admin changes them.
  /// Also auto-logs out the employee if admin deactivates them.
  void _subscribeToUserChanges() {
    if (_user == null) return;
    final uid = _user!.id;
    try {
      PBService.pb.collection('users').subscribe(uid, (event) async {
        if (event.record == null || _disposed) return;

        // Check if the employee was deactivated by admin
        final isActive = event.record!.getBoolValue('active');
        final isApproved = event.record!.getBoolValue('approved');
        if ((!isActive || !isApproved) && userRole == 'employee') {
          wasDeactivated = true;
          await logout();
          return;
        }

        _user = event.record;
        notifyListeners();
      });
    } catch (_) {}
  }

  Future<void> _loadSavedUser() async {
    final userId = await _secureStorage.read(key: 'user_id');
    if (userId != null) {
      try {
        _user = await PBService.getUser(userId);

        // Cache user data in secure storage
        await _secureStorage.write(key: 'user_data', value: jsonEncode(_user!.toJson()));

        // Check subscription for employees/customers on app restart
        if (userRole == 'employee' || userRole == 'customer') {
          final aId = _user!.getStringValue('admin_id');
          if (aId.isNotEmpty) {
            try {
              final admin = await PBService.pb.collection('users').getOne(aId);
              final subEnd = admin.getStringValue('subscription_end');
              if (subEnd.isNotEmpty) {
                final endDate = DateTime.parse(subEnd);
                if (endDate.isBefore(DateTime.now())) {
                  _user = null;
                  await _secureStorage.delete(key: 'user_id');
                  await _secureStorage.delete(key: 'user_data');
                  _isInitializing = false;
                  notifyListeners();
                  return;
                }
              }
            } catch (_) {
              // Can't verify admin subscription (network issue) — allow access
              // The subscription check will run again next time
            }
          }
        }

        // Check subscription for admin on app restart
        if (userRole == 'admin') {
          final subEnd = _user!.getStringValue('subscription_end');
          if (subEnd.isNotEmpty) {
            final endDate = DateTime.parse(subEnd);
            if (endDate.isBefore(DateTime.now())) {
              _user = null;
              await _secureStorage.delete(key: 'user_id');
              await _secureStorage.delete(key: 'user_data');
              _isInitializing = false;
              notifyListeners();
              return;
            }
          }
        }

        // Subscribe to real-time permission updates for employees
        if (userRole == 'employee') {
          _subscribeToUserChanges();
        }
      } catch (_) {
        // Network failure? Try to load from cache
        final userDataString = await _secureStorage.read(key: 'user_data');
        if (userDataString != null) {
          try {
            final userData = jsonDecode(userDataString);
            _user = RecordModel.fromJson(userData);
          } catch (_) {}
        }

        if (_user == null) {
          // No cache or corrupt -> Logout
          await _secureStorage.delete(key: 'user_id');
          await _secureStorage.delete(key: 'user_data');
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
      } else {
        // Lockout expired
        await prefs.remove(kLockoutTimeKey);
        await prefs.remove(kFailedAttemptsKey);
      }
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
    } else {
      await prefs.setInt(kFailedAttemptsKey, attempts);
    }
  }

  Future<bool> login(String phone, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _checkLockout();

      try {
        _user = await PBService.login(phone, password);
      } catch (e) {
        if (e is String) rethrow; // Subscription expiry etc.
        await _handleLoginFailure();
        throw 'وشەی نهێنی یان ژمارە مۆبایل هەڵەیە';
      }

      // Check subscription expiry for admin
      if (userRole == 'admin') {
        final subEnd = _user!.getStringValue('subscription_end');
        if (subEnd.isNotEmpty) {
          final endDate = DateTime.parse(subEnd);
          if (endDate.isBefore(DateTime.now())) {
            _user = null;
            throw 'ماوەی ڕێکەوتنی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بۆ نوێکردنەوە.';
          }
        }
      }

      // Check subscription for employees/customers (via their admin)
      if (userRole == 'employee' || userRole == 'customer') {
        final adminId = _user!.getStringValue('admin_id');
        if (adminId.isNotEmpty) {
          try {
            final admin = await PBService.pb
                .collection('users')
                .getOne(adminId);
            final subEnd = admin.getStringValue('subscription_end');
            if (subEnd.isNotEmpty) {
              final endDate = DateTime.parse(subEnd);
              if (endDate.isBefore(DateTime.now())) {
                _user = null;
                throw 'ماوەی ڕێکەوتنی بەڕێوەبەرەکەت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەرەکەت.';
              }
            }
          } catch (e) {
            if (e is String) rethrow;
          }
        }
      }

      // Subscribe to real-time permission updates for employees
      if (userRole == 'employee') {
        _subscribeToUserChanges();
      }

      await _secureStorage.write(key: 'user_id', value: _user!.id);
      await _secureStorage.write(key: 'user_data', value: jsonEncode(_user!.toJson()));

      // Reset lockout on success
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kLockoutTimeKey);
      await prefs.remove(kFailedAttemptsKey);

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
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
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
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
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> logout() async {
    // Unsubscribe from user-specific realtime channel
    if (_user != null) {
      try {
        await PBService.pb.collection('users').unsubscribe(_user!.id);
      } catch (_) {}
    }

    // Unsubscribe from all PocketBase realtime collections
    // MUST await so callbacks stop before widget tree changes
    try {
      await PBService.pb.collection('debts').unsubscribe();
      await PBService.pb.collection('payments').unsubscribe();
      await PBService.pb.collection('notifications').unsubscribe();
    } catch (_) {}

    _user = null;
    await _secureStorage.delete(key: 'user_id');
    await _secureStorage.delete(key: 'user_data');
    notifyListeners();
  }
}
