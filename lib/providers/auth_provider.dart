import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/features/customers/customer_directory_snapshot.dart';
import 'package:zhirox/features/expiry/expiry_reminder_service.dart';
import 'package:zhirox/features/expiry/expiry_catalog_service.dart';

class AuthProvider extends ChangeNotifier {
  RecordModel? _user;
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _disposed = false;
  Timer? _deviceAuthorizationTimer;

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
    if (date == null) return 9999;

    final now = DateTime.now();
    if (!date.isAfter(now)) return 0;
    return date.difference(now).inDays + 1;
  }

  String get userFullName {
    final parts = [
      _user?.getStringValue('name') ?? '',
      _user?.getStringValue('father_name') ?? '',
      _user?.getStringValue('grandfather_name') ?? '',
    ].where((e) => e.trim().isNotEmpty);
    return parts.join(' ');
  }

  bool get canAddCustomers =>
      userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_add_customers') ?? false));

  bool get canSetDebtLimit =>
      userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_set_debt_limit') ?? false));

  bool get canSetDueDate =>
      userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_set_due_date') ?? false));

  bool get canEditDebts =>
      userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_edit_debts') ?? false));

  bool get canSendNotifications =>
      userRole == 'admin' ||
      (userRole == 'employee' &&
          (_user?.getBoolValue('can_send_notifications') ?? false));

  bool _employeePermission(String field) =>
      userRole == 'admin' ||
      (userRole == 'employee' && (_user?.getBoolValue(field) ?? false));

  /// Runtime authorization entrypoint for the complete employee permission
  /// registry. Admins keep full tenant authority, employees are granted only
  /// explicit `can_*` flags, and all other roles/invalid keys are denied.
  bool hasEmployeePermission(String field) {
    if (!RegExp(r'^can_[a-z0-9_]+$').hasMatch(field)) return false;
    return _employeePermission(field);
  }

  bool get canViewCustomers => _employeePermission('can_view_customers');
  bool get canEditCustomers => _employeePermission('can_edit_customers');
  bool get canDeleteCustomers => _employeePermission('can_delete_customers');
  bool get canViewDebts => _employeePermission('can_view_debts');
  bool get canAddDebts => _employeePermission('can_add_debts');
  bool get canDeleteDebts => _employeePermission('can_delete_debts');
  bool get canRecordPayments => _employeePermission('can_record_payments');
  bool get canViewFinancialReports =>
      _employeePermission('can_view_financial_reports');
  bool get canExportData => _employeePermission('can_export_data');
  bool get canImportData => _employeePermission('can_import_data');
  bool get canRefundPayments => _employeePermission('can_refund_payments');
  bool get canRestoreDebts => _employeePermission('can_restore_debts');
  bool get canManageReceipts => _employeePermission('can_manage_receipts');
  bool get canManageNotifications => _employeePermission('can_manage_notifications');
  bool get canApproveCustomers => _employeePermission('can_approve_customers');
  bool get canManageEmployees => _employeePermission('can_manage_employees');
  bool get canViewAuditLog => _employeePermission('can_view_audit_log');
  bool get canManageBackup => _employeePermission('can_manage_backup');
  bool get canManageDaftarSync => _employeePermission('can_manage_daftar_sync');
  bool get canManageSubscription => _employeePermission('can_manage_subscription');
  bool get canViewDashboard => _employeePermission('can_view_dashboard');
  bool get canViewRecentActivity => _employeePermission('can_view_recent_activity');
  bool get canViewTransactions => _employeePermission('can_view_transactions');
  bool get canEditPayments => _employeePermission('can_edit_payments');
  bool get canDeletePayments => _employeePermission('can_delete_payments');
  bool get canCreateStatements => _employeePermission('can_create_statements');
  bool get canManageCustomerLinks => _employeePermission('can_manage_customer_links');
  bool get canPinCustomers => _employeePermission('can_pin_customers');
  bool get canManageVipCustomers => _employeePermission('can_manage_vip_customers');
  bool get canMergeCustomerIdentities =>
      _employeePermission('can_merge_customer_identities');
  bool get canViewMarketRates => _employeePermission('can_view_market_rates');
  bool get canViewIntelligence => _employeePermission('can_view_intelligence');
  bool get canManageCollections => _employeePermission('can_manage_collections');
  bool get canViewExpiry => _employeePermission('can_view_expiry');
  bool get canManageExpiry => _employeePermission('can_manage_expiry');
  bool get canManageSettings => _employeePermission('can_manage_settings');

  double get debtLimit => _user?.getDoubleValue('debt_limit') ?? 0;

  bool wasDeactivated = false;

  void clearDeactivatedFlag() => wasDeactivated = false;

  AuthProvider() {
    _loadSavedUser();
  }

  @override
  void dispose() {
    _disposed = true;
    _deviceAuthorizationTimer?.cancel();
    _deviceAuthorizationTimer = null;
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

        if (!active || (role == 'customer' && !approved)) {
          wasDeactivated = true;
          await logout();
          return;
        }

        _user = updated;
        if (!_disposed) notifyListeners();
      }),
    );
  }

  Future<void> _clearLocalUser() async {
    if (!kIsWeb) {
      try {
        await ExpiryReminderService.clearDeviceSchedules();
      } catch (_) {}
    }
    _user = null;
  }

  Future<void> _refreshExpiryReminders() async {
    if (kIsWeb) return;
    if (userRole != 'admin' && userRole != 'employee') return;
    final tenant = adminId;
    final actor = userId;
    try {
      if (!await ExpiryReminderService.enabled(tenant, actor)) return;
      final arrivals = await ExpiryCatalogService.arrivals(tenant);
      if (userId != actor || adminId != tenant) return;
      await ExpiryReminderService.refresh(
        tenant: tenant,
        user: actor,
        arrivals: arrivals,
      );
    } catch (_) {
      // Reminder failures must never block sign-in or other app features.
    }
  }

  static const String kPlatformDeviceIdKey = 'zhirox_platform_admin_device_id';

  Future<String> _getOrCreatePlatformDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(kPlatformDeviceIdKey)?.trim() ?? '';
    if (existing.length >= 16) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final generated = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(kPlatformDeviceIdKey, generated);
    return generated;
  }

  Future<void> _enforceAdminDeviceAuthorization() async {
    final current = _user;
    if (current == null ||
        userRole != 'admin' ||
        current.getBoolValue('is_system_owner')) {
      return;
    }

    final deviceId = await _getOrCreatePlatformDeviceId();
    final state = await PBService.registerPlatformAdminDevice(deviceId);
    if (state['allowed'] == true) return;

    final status = (state['status'] ?? 'pending').toString();
    if (status == 'revoked') {
      throw 'ئەم ئامێرە لەلایەن خاوەنی سیستەمەوە ڕاگیراوە';
    }
    throw 'ئەم ئامێرە چاوەڕێی پەسەندکردنی خاوەنی سیستەمە';
  }

  void _startDeviceAuthorizationHeartbeat() {
    _deviceAuthorizationTimer?.cancel();
    final current = _user;
    if (current == null ||
        userRole != 'admin' ||
        current.getBoolValue('is_system_owner')) {
      return;
    }

    _deviceAuthorizationTimer = Timer.periodic(const Duration(minutes: 5), (
      _,
    ) async {
      try {
        await _enforceAdminDeviceAuthorization();
      } catch (error) {
        final text = error.toString();
        final blocked =
            text.contains('چاوەڕێی پەسەندکردنی') ||
            text.contains('لەلایەن خاوەنی سیستەمەوە ڕاگیراوە');
        if (!blocked || _disposed) return;
        await logout();
      }
    });
  }

  Future<void> _validateSubscription() async {
    final current = _user;
    if (current == null) return;

    if (!current.getBoolValue('active')) {
      throw 'ئەم هەژمارە ناچالاک کراوە';
    }
    if (userRole == 'customer' && !current.getBoolValue('approved')) {
      throw 'ئەم هەژمارە هێشتا پەسەند نەکراوە';
    }

    if (userRole == 'admin') {
      // Expired admins remain authenticated only so the app can present the
      // restricted subscription-payment screen. Main blocks dashboard access.
      return;
    }

    if (userRole == 'employee' || userRole == 'customer') {
      final aId = current.getStringValue('admin_id');
      if (aId.isEmpty) return;
      final admin = await PBService.getUser(aId);
      final subEnd = admin.getStringValue('subscription_end');
      final date = DateTime.tryParse(subEnd);
      if (date != null && !date.isAfter(DateTime.now())) {
        throw 'ماوەی ڕێکەوتنی بەڕێوەبەرەکەت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەرەکەت.';
      }
    }
  }

  Future<void> refreshCurrentProfile() async {
    final current = _user;
    if (current == null) return;
    _user = await PBService.getUser(current.id);
    if (!_disposed) notifyListeners();
  }

  Future<void> _loadSavedUser() async {
    try {
      await PBService.ensureInitialized();
      final authUser = PBService.client.auth.currentUser;
      final session = PBService.client.auth.currentSession;

      if (authUser == null || session == null) {
        await _clearLocalUser();
        return;
      }

      try {
        _user = await PBService.getUser(authUser.id);
        await _validateSubscription();
        await _enforceAdminDeviceAuthorization();
      } catch (error) {
        if (PBService.isServiceRestrictionError(error)) {
          // Preserve the Supabase session. A 402 is a temporary platform
          // restriction, not an authentication revocation.
          return;
        }
        await PBService.logout();
        await _clearLocalUser();
        return;
      }

      _subscribeToUserChanges();
      _startDeviceAuthorizationHeartbeat();
      unawaited(_refreshExpiryReminders());
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
      await _validateSubscription();
      await _enforceAdminDeviceAuthorization();
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

  bool _isConnectivityError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('connection closed') ||
        text.contains('timed out') ||
        text.contains('timeout') ||
        text.contains('network') ||
        text.contains('offline') ||
        text.contains('no route to host');
  }

  Future<void> login(String phone, String password) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

    try {
      await _checkLockout();
      final user = await PBService.login(phone, password);
      _user = user;
      await _validateSubscription();
      await _enforceAdminDeviceAuthorization();
      _subscribeToUserChanges();
      _startDeviceAuthorizationHeartbeat();
      unawaited(_refreshExpiryReminders());

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kFailedAttemptsKey);
      await prefs.remove(kLockoutTimeKey);
    } catch (error) {
      if (!_isConnectivityError(error) && !PBService.isServiceRestrictionError(error)) {
        await _handleLoginFailure();
      }
      rethrow;
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> logout() async {
    _deviceAuthorizationTimer?.cancel();
    _deviceAuthorizationTimer = null;
    try {
      await PBService.logout();
    } finally {
      await _clearLocalUser();
      if (!_disposed) notifyListeners();
    }
  }
}
