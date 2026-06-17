import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:pocketbase/pocketbase.dart';
import 'package:http/http.dart' as http;
import 'package:zhirox/utils/constants.dart';

class PBService {
  static final PocketBase pb = PocketBase(PBConfig.baseUrl);

  /// Sanitize a value before using it in a PocketBase filter string.
  /// Escapes double quotes and backslashes to prevent filter injection.
  static String _sanitize(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }
  /// Resolve the real admin/market owner for any action.
  /// If actor is admin => admin_id = actor id.
  /// If actor is employee/customer => admin_id = actor.admin_id.
  static Future<String> _resolveAdminId(String userId) async {
    if (userId.isEmpty) return '';

    try {
      final user = await pb.collection('users').getOne(userId);
      final role = user.getStringValue('role');

      if (role == 'admin') {
        return userId;
      }

      final adminId = user.getStringValue('admin_id');
      if (adminId.isNotEmpty) {
        return adminId;
      }

      return userId;
    } catch (e) {
      debugPrint('resolveAdminId failed: $e');
      return '';
    }
  }
  // ==================== Auth ====================

  static Future<RecordModel> login(String phone, String password) async {
    final cleanPhone = phone.trim();
    final localEmail = cleanPhone.contains('@')
        ? cleanPhone
        : '$cleanPhone@zhirox.local';

    RecordModel? user;
    bool authenticated = false;

    // 1. Secure login path: login directly with the phone-based local email.
    // This lets PocketBase keep the auth token so protected API Rules work.
    try {
      final auth = await pb.collection('users').authWithPassword(
        localEmail,
        password,
      );
      user = auth.record;
      authenticated = true;
    } catch (_) {
      // Fallback below supports older/manual users whose email is not phone@zhirox.local.
      // For the strongest API Rules, update old users' email to phone@zhirox.local.
    }

    // 2. Legacy fallback: find user by phone, then authenticate with stored email.
    // This fallback may require a temporary List/Search rule on users during migration.
    if (!authenticated) {
      final safePhone = _sanitize(cleanPhone);
      final result = await pb
          .collection('users')
          .getList(filter: 'phone = "$safePhone"', perPage: 1);

      if (result.items.isEmpty) {
        throw Exception('ئەم ژمارەیە تۆمار نەکراوە');
      }

      user = result.items.first;

      try {
        final auth = await pb.collection('users').authWithPassword(
          user.getStringValue('email'),
          password,
        );
        user = auth.record;
        authenticated = true;
      } catch (_) {
        // PocketBase auth failed — try legacy password_text fallback
      }
    }

    // 3. Fallback: check password_text for legacy users who changed password via old system.
    if (!authenticated && user != null) {
      final storedPassword = user.getStringValue('password_text');
      if (storedPassword.isNotEmpty && storedPassword == password) {
        authenticated = true;
        // Migrate: sync PocketBase password and clear password_text.
        // Works only if the current API Rules allow updating this user.
        try {
          await pb.collection('users').update(user.id, body: {
            'password': password,
            'passwordConfirm': password,
            'password_text': '',
          });
        } catch (_) {}
      }
    }

    if (!authenticated || user == null) {
      throw Exception('وشەی نهێنی هەڵەیە');
    }

    final role = user.getStringValue('role');

    // بپشکنە ئەگەر کڕیارە و هێشتا قبوڵ نەکراوە
    if (role == 'customer') {
      final approved = user.getBoolValue('approved');
      if (!approved) {
        throw Exception(AppStrings.notApproved);
      }
    }

    // بپشکنە ئەگەر کارمەندە و ناچالاکە
    if (role == 'employee') {
      final active = user.getBoolValue('active');
      if (!active) {
        throw Exception('ئەم ئەکاونتە لەلایەن ئەدمینەوە ناچالاک کراوە');
      }
    }

    // بپشکنینی ماوەی مۆڵەتی بەڕێوەبەر بۆ کارمەند و کڕیار
    if (role == 'employee' || role == 'customer') {
      final adminId = user.getStringValue('admin_id');
      if (adminId.isNotEmpty) {
        try {
          final admin = await pb.collection('users').getOne(adminId);
          final subEnd = admin.getStringValue('subscription_end');
          if (subEnd.isNotEmpty) {
            final endDate = DateTime.parse(subEnd);
            if (endDate.isBefore(DateTime.now())) {
              throw 'ماوەی ڕێکەوتنی بەڕێوەبەرەکەت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەرەکەت.';
            }
          }
        } catch (e) {
          if (e is String) rethrow;
          throw 'ناتوانرێت ماوەی مۆڵەتی بەڕێوەبەرەکەت بپشکنرێت. تکایە دواتر هەوڵبدەرەوە.';
        }
      }
    }

    return user;
  }

  // ==================== Registration ====================

  static Future<RecordModel> registerAdmin({
    required String marketName,
    required String adminName,
    required String phone,
    required String password,
    required int subscriptionDays,
  }) async {
    // بپشکنە ئەو ژمارەیە پێشتر تۆمار نەکرابێت
    final safePhone = _sanitize(phone);
    final existing = await pb
        .collection('users')
        .getList(filter: 'phone = "$safePhone"', perPage: 1);
    if (existing.items.isNotEmpty) {
      throw Exception('ئەم ژمارەیە پێشتر تۆمارکراوە');
    }

    final subscriptionEnd = DateTime.now().add(
      Duration(days: subscriptionDays),
    );

    return await pb
        .collection('users')
        .create(
          body: {
            'name': adminName,
            'email': '$phone@zhirox.local',
            'market_name': marketName,
            'phone': phone,
            'password': password,
            'passwordConfirm': password,
            'password_text': password,
            'role': 'admin',
            'approved': true,
            'subscription_end': subscriptionEnd.toUtc().toIso8601String(),
          },
        );
  }

  // ==================== Admin Subscription Management ====================

  /// Get admins with pagination + employee/customer counts
  static Future<Map<String, dynamic>> getAdminsPage({
    int page = 1,
    int perPage = 15,
  }) async {
    final result = await pb
        .collection('users')
        .getList(
          filter: 'role = "admin"',
          sort: '-created',
          page: page,
          perPage: perPage,
        );

    final admins = <Map<String, dynamic>>[];
    for (final admin in result.items) {
      final safeAdminId = _sanitize(admin.id);
      final employees = await pb
          .collection('users')
          .getList(
            filter: 'admin_id = "$safeAdminId" && role = "employee"',
            perPage: 1,
          );
      final customers = await pb
          .collection('users')
          .getList(
            filter: 'admin_id = "$safeAdminId" && role = "customer"',
            perPage: 1,
          );
      admins.add({
        'admin': admin,
        'employeeCount': employees.totalItems,
        'customerCount': customers.totalItems,
      });
    }
    return {
      'admins': admins,
      'totalItems': result.totalItems,
      'totalPages': result.totalPages,
      'page': result.page,
    };
  }

  /// Renew admin subscription
  static Future<void> renewAdminSubscription(String adminId, int days) async {
    final newEnd = DateTime.now().add(Duration(days: days));
    await pb
        .collection('users')
        .update(
          adminId,
          body: {'subscription_end': newEnd.toUtc().toIso8601String()},
        );
  }

  /// Delete admin and ALL their data (employees, customers, debts, payments, notifications)
  static Future<void> deleteAdminWithData(String adminId) async {
    final safeAdminId = _sanitize(adminId);
    // 1. Get all users under this admin
    final users = await pb
        .collection('users')
        .getFullList(filter: 'admin_id = "$safeAdminId"');

    // 2. Delete debts, payments, and notifications for each user
    for (final user in users) {
      // Delete debts where customer = user.id
      final safeUserId = _sanitize(user.id);
      final debts = await pb
          .collection('debts')
          .getFullList(filter: 'customer = "$safeUserId"');
      for (final debt in debts) {
        // Delete payments for this debt
        try {
          final safeDebtId = _sanitize(debt.id);
          final payments = await pb
              .collection('payments')
              .getFullList(filter: 'debt = "$safeDebtId"');
          for (final payment in payments) {
            try {
              await pb.collection('payments').delete(payment.id);
            } catch (_) {}
          }
        } catch (_) {}
        // Delete the debt
        try {
          await pb.collection('debts').delete(debt.id);
        } catch (_) {}
      }

      // Delete notifications for user
      try {
        final notifs = await pb
            .collection('notifications')
            .getFullList(filter: 'customer = "$safeUserId"');
        for (final notif in notifs) {
          try {
            await pb.collection('notifications').delete(notif.id);
          } catch (_) {}
        }
      } catch (_) {}

      // Delete the user
      try {
        await pb.collection('users').delete(user.id);
      } catch (_) {}
    }

    // 3. Delete debts created by admin (and their payments)
    final adminDebts = await pb
        .collection('debts')
        .getFullList(filter: 'created_by = "$safeAdminId"');
    for (final debt in adminDebts) {
      try {
        final payments = await pb
            .collection('payments')
            .getFullList(filter: 'debt = "${_sanitize(debt.id)}"');
        for (final payment in payments) {
          try {
            await pb.collection('payments').delete(payment.id);
          } catch (_) {}
        }
      } catch (_) {}
      try {
        await pb.collection('debts').delete(debt.id);
      } catch (_) {}
    }

    // 4. Delete admin notifications
    try {
      final adminNotifs = await pb
          .collection('notifications')
          .getFullList(filter: 'customer = "$safeAdminId"');
      for (final notif in adminNotifs) {
        try {
          await pb.collection('notifications').delete(notif.id);
        } catch (_) {}
      }
    } catch (_) {}

    // 5. Delete the admin
    await pb.collection('users').delete(adminId);
  }

  /// Check subscription expiry for an admin, returns days remaining (negative = expired)
  static Future<int> checkSubscriptionDaysLeft(String adminId) async {
    final admin = await pb.collection('users').getOne(adminId);
    final subEnd = admin.getStringValue('subscription_end');
    if (subEnd.isEmpty) return 9999; // No expiry set
    final endDate = DateTime.parse(subEnd);
    return endDate.difference(DateTime.now()).inDays;
  }

  static Future<RecordModel> registerCustomer({
    required String name,
    String fatherName = '',
    String grandfatherName = '',
    required String phone,
    required String password,
    required String adminId,
  }) async {
    // بپشکنە ئەو ژمارەیە پێشتر تۆمار نەکرابێت
    final safePhone = _sanitize(phone);
    final existing = await pb
        .collection('users')
        .getList(filter: 'phone = "$safePhone"', perPage: 1);
    if (existing.items.isNotEmpty) {
      throw Exception('ئەم ژمارەیە پێشتر تۆمارکراوە');
    }

    return await pb
        .collection('users')
        .create(
          body: {
            'name': name,
            'email': '$phone@zhirox.local',
            'father_name': fatherName,
            'grandfather_name': grandfatherName,
            'phone': phone,
            'password': password,
            'passwordConfirm': password,
            'password_text': password,
            'role': 'customer',
            'admin_id': adminId,
            'approved': false,
          },
        );
  }

  // ==================== Admin Approval ====================

  static Future<List<RecordModel>> getAdminList() async {
    final result = await pb
        .collection('users')
        .getList(filter: 'role = "admin"', sort: '-created', perPage: 500);
    return result.items;
  }

  static Future<List<RecordModel>> getPendingCustomers(String adminId) async {
    final safeAdminId = _sanitize(adminId);
    final result = await pb
        .collection('users')
        .getList(
          filter:
              'role = "customer" && admin_id = "$safeAdminId" && approved = false',
          sort: '-created',
          perPage: 500,
        );
    return result.items;
  }

  static Future<void> approveCustomer(String id, int debtDuration) async {
    await pb
        .collection('users')
        .update(id, body: {'approved': true, 'debt_duration': debtDuration});
  }

  static Future<void> rejectCustomer(String id) async {
    await pb.collection('users').delete(id);
  }

  // ==================== Users ====================

  static Future<RecordModel> createUser({
    required String name,
    String fatherName = '',
    String grandfatherName = '',
    required String phone,
    required String password,
    required String role,
    required String createdBy,
    String? adminId,
    bool canAddCustomers = false,
    bool canSetDebtLimit = false,
    bool canSetDueDate = false,
    bool canEditDebts = false,
    bool canSendNotifications = false,
    double debtLimit = 0,
  }) async {
    // Check if phone already exists
    final safePhone = _sanitize(phone);
    final existing = await pb
        .collection('users')
        .getList(filter: 'phone = "$safePhone"', perPage: 1);
    if (existing.items.isNotEmpty) {
      throw Exception('ئەم ژمارەیە پێشتر تۆمارکراوە');
    }

    final body = {
      'name': name,
      'email': '$phone@zhirox.local',
      'father_name': fatherName,
      'grandfather_name': grandfatherName,
      'phone': phone,
      'password': password,
      'passwordConfirm': password,
      'password_text': password,
      'role': role,
      'created_by': createdBy,
      'admin_id': adminId ?? createdBy,
      'approved': true,
      'active': true,
    };

    if (role == 'employee') {
      body['can_add_customers'] = canAddCustomers;
      body['can_set_debt_limit'] = canSetDebtLimit;
      body['can_set_due_date'] = canSetDueDate;
      body['can_edit_debts'] = canEditDebts;
      body['can_send_notifications'] = canSendNotifications;
    }

    if (role == 'customer') {
      body['debt_limit'] = debtLimit;
    }

    return await pb.collection('users').create(body: body);
  }

  static Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await pb.collection('users').update(id, body: data);
  }

  /// Change password for a user. Handles both PocketBase auth and legacy password_text.
  /// Verifies oldPassword, then stores password encrypted via PocketBase hashing.
  static Future<void> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = await pb.collection('users').getOne(userId);
    final email = user.getStringValue('email');
    final storedPasswordText = user.getStringValue('password_text');

    bool pbAuthOk = false;

    // 1. Try PocketBase auth to verify old password
    try {
      await pb.collection('users').authWithPassword(email, oldPassword);
      pbAuthOk = true;
    } catch (_) {}

    // 2. If PB auth failed, verify against password_text (legacy)
    if (!pbAuthOk) {
      if (storedPasswordText.isEmpty || storedPasswordText != oldPassword) {
        pb.authStore.clear();
        throw Exception('\u0648\u0634\u06d5\u06cc \u0646\u0647\u06ce\u0646\u06cc\u06cc \u06a9\u06c6\u0646 \u0647\u06d5\u06b5\u06d5\u06cc\u06d5');
      }
    }

    // 3. Update PocketBase password (encrypted/hashed by PocketBase)
    if (pbAuthOk) {
      // PB auth succeeded → auth token is active, update PB password with oldPassword
      try {
        await pb.collection('users').update(userId, body: {
          'oldPassword': oldPassword,
          'password': newPassword,
          'passwordConfirm': newPassword,
          'password_text': '', // Clear plaintext since PB now has the hashed version
        });
      } catch (_) {
        // If PB update fails, fallback to password_text
        await pb.collection('users').update(userId, body: {
          'password_text': newPassword,
        });
      }
    } else {
      // Legacy user: PB password is out of sync, can't provide valid oldPassword.
      // Try setting PB password without oldPassword (works if PB rules allow it)
      try {
        await pb.collection('users').update(userId, body: {
          'password': newPassword,
          'passwordConfirm': newPassword,
          'password_text': '', // Clear plaintext
        });
      } catch (_) {
        // PB password sync failed → keep password_text as fallback for login
        await pb.collection('users').update(userId, body: {
          'password_text': newPassword,
        });
      }
    }

    pb.authStore.clear();
  }

  static Future<void> deleteUser(String id) async {
    await pb.collection('users').delete(id);
  }

  static Future<List<RecordModel>> getUsers({
    String? role,
    String? search,
    String? adminId,
    bool? approved,
  }) async {
    String filter = '';
    List<String> filters = [];

    if (role != null) filters.add('role = "${_sanitize(role)}"');
    if (adminId != null) filters.add('admin_id = "${_sanitize(adminId)}"');
    if (approved != null) filters.add('approved = $approved');
    if (search != null && search.isNotEmpty) {
      final safeSearch = _sanitize(search);
      filters.add(
        '(name ~ "$safeSearch" || father_name ~ "$safeSearch" || phone ~ "$safeSearch")',
      );
    }

    if (filters.isNotEmpty) filter = filters.join(' && ');

    final result = await pb
        .collection('users')
        .getList(filter: filter, sort: '-created', perPage: 500);

    return result.items;
  }

  static Future<RecordModel> getUser(String id) async {
    return await pb.collection('users').getOne(id);
  }

  // ==================== Debts ====================

  static Future<double> getCustomerBalance(String customerId) async {
    // This is a simplified balance calculation.
    // Ideally this should be done on backend or with optimized queries.
    // For now: Sum of (Debt Amount - Paid Amount) for all debts.
    try {
      final debts = await getDebts(customerId: customerId);
      double totalRemaining = 0;

      for (var debt in debts) {
        totalRemaining += debt.getDoubleValue('remaining');
      }
      return totalRemaining;
    } catch (e) {
      return 0;
    }
  }

  static Future<RecordModel> createDebt({
    required String customerId,
    required String description,
    required double amount,
    required String dueDate,
    required String createdBy,
    String? adminId,
    String currency = 'IQD',
    double dollarRate = 0,
    double amountUsd = 0,
    List<Map<String, dynamic>>? items,
    String? createdByName,
    String? marketName,
    String? customCreatedDate,
    String? receiptImagePath,
  }) async {
  final resolvedAdminId = (adminId != null && adminId.isNotEmpty)
      ? adminId
      : await _resolveAdminId(createdBy);

  final body = <String, dynamic>{
    'customer': customerId,
    'description': description,
    'amount': amount,
    'remaining': amount,
    'due_date': dueDate,
    'status': 'pending',
    'created_by': createdBy,
    if (resolvedAdminId.isNotEmpty) 'admin_id': resolvedAdminId,
    'currency': currency,
      'dollar_rate': dollarRate,
      'amount_usd': amountUsd,
      'items': items != null ? jsonEncode(items) : '[]',
    };

    // If custom date provided, store it in custom_date field
    if (customCreatedDate != null && customCreatedDate.isNotEmpty) {
      body['custom_date'] = customCreatedDate;
    }

    // Prepare file list for receipt image
    final List<http.MultipartFile> files = [];
    if (receiptImagePath != null && receiptImagePath.isNotEmpty) {
      files.add(
        await http.MultipartFile.fromPath('receipt_image', receiptImagePath),
      );
    }

    final record = await pb
        .collection('debts')
        .create(body: body, files: files);

    // Auto-send notification
    try {
      final formattedAmount =
          '${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} د.ع';

      // Always resolve admin name for notification (not employee name)
      String senderName = createdByName ?? 'کارمەند';

      // If market name not provided, try to get it from the user/admin
      String resolvedMarketName = marketName ?? '';
      try {
        final creator = await pb.collection('users').getOne(createdBy);
        final role = creator.getStringValue('role');
        if (role == 'admin') {
          if (resolvedMarketName.isEmpty) {
            resolvedMarketName = creator.getStringValue('market_name');
          }
          senderName = creator.getStringValue('name');
        } else {
          final adminId = creator.getStringValue('admin_id');
          if (adminId.isNotEmpty) {
            final admin = await pb.collection('users').getOne(adminId);
            if (resolvedMarketName.isEmpty) {
              resolvedMarketName = admin.getStringValue('market_name');
            }
            senderName = admin.getStringValue('name');
          }
        }
      } catch (_) {}

      final marketLine = resolvedMarketName.isNotEmpty
          ? '$resolvedMarketName\n'
          : '';

      final dueDateLine = dueDate.isNotEmpty
          ? '\nبەرواری دانەوە: ${dueDate.replaceAll('-', '/')}'
          : '';

      await createNotification(
        customerId: customerId,
        message:
            '$marketLineقەرزی $formattedAmount لەلایەن $senderName زیادکرا.$dueDateLine',
        senderId: createdBy,
        type: 'debt_created',
        adminId: resolvedAdminId, 
      );
    } catch (_) {
      // Ignore notification failures
    }

    return record;
  }

  static Future<void> updateDebt(String id, Map<String, dynamic> data) async {
    await pb.collection('debts').update(id, body: data);
  }

  static Future<void> deleteDebt(String id) async {
    // سەرەتا پارەدانەوەکانی ئەم قەرزە بسڕەوە
    final safeId = _sanitize(id);
    final payments = await pb
        .collection('payments')
        .getList(filter: 'debt = "$safeId"', perPage: 500);
    for (var payment in payments.items) {
      await pb.collection('payments').delete(payment.id);
    }
    await pb.collection('debts').delete(id);
  }

  static Future<List<RecordModel>> getDebts({
    String? customerId,
    String? status,
    String? createdBy,
    String? adminId,
    int page = 1,
    int perPage =
        500, // Default high to support legacy calls, DebtListScreen will pass 20
    String? filter,
  }) async {
    List<String> filters = [];

    if (customerId != null) filters.add('customer = "${_sanitize(customerId)}"');
    if (status != null) filters.add('status = "${_sanitize(status)}"');
    if (createdBy != null) filters.add('created_by = "${_sanitize(createdBy)}"');
    if (adminId != null) filters.add('customer.admin_id = "${_sanitize(adminId)}"');
    if (filter != null && filter.isNotEmpty) filters.add(filter);

    final filterString = filters.isNotEmpty ? filters.join(' && ') : '';

    final result = await pb
        .collection('debts')
        .getList(
          page: page,
          perPage: perPage,
          filter: filterString,
          sort: '-created',
          expand: 'customer,created_by',
        );

    return result.items;
  }

  /// Paginated version that also returns totalItems for scroll pagination
  static Future<Map<String, dynamic>> getDebtsPaginated({
    String? customerId,
    String? status,
    String? createdBy,
    String? adminId,
    int page = 1,
    int perPage = 20,
    String? filter,
  }) async {
    List<String> filters = [];

    if (customerId != null) filters.add('customer = "${_sanitize(customerId)}"');
    if (status != null) filters.add('status = "${_sanitize(status)}"');
    if (createdBy != null) filters.add('created_by = "${_sanitize(createdBy)}"');
    if (adminId != null) filters.add('customer.admin_id = "${_sanitize(adminId)}"');
    if (filter != null && filter.isNotEmpty) filters.add(filter);

    final filterString = filters.isNotEmpty ? filters.join(' && ') : '';

    final result = await pb
        .collection('debts')
        .getList(
          page: page,
          perPage: perPage,
          filter: filterString,
          sort: '-created',
          expand: 'customer,created_by',
        );

    return {
      'items': result.items,
      'totalItems': result.totalItems,
      'totalPages': result.totalPages,
    };
  }

  static Future<RecordModel> getDebt(String id) async {
    return await pb
        .collection('debts')
        .getOne(id, expand: 'customer,created_by');
  }

  // ==================== Payments ====================

  static Future<RecordModel> createPayment({
    required String debtId,
    required double amount,
    String? note,
    required String createdBy,
    String? createdByName,
    String? adminId,
  }) async {
  final resolvedAdminId = (adminId != null && adminId.isNotEmpty)
      ? adminId
      : await _resolveAdminId(createdBy);

  // پارەدانەوە دروست بکە
 final payment = await pb
    .collection('payments')
    .create(
      body: {
        'debt': debtId,
        'amount': amount,
        'note': note ?? '',
        'created_by': createdBy,
        if (resolvedAdminId.isNotEmpty) 'admin_id': resolvedAdminId,
      },
    );

    // قەرزەکە ئەپدەیت بکە
    final debt = await pb
        .collection('debts')
        .getOne(debtId, expand: 'customer');
    final remaining = debt.getDoubleValue('remaining') - amount;
    final newRemaining = remaining <= 0 ? 0.0 : remaining;
    final newStatus = remaining <= 0 ? 'paid' : 'partial';

    await pb.collection('debts').update(
  debtId,
  body: {
    'remaining': newRemaining,
    'status': newStatus,
    if (resolvedAdminId.isNotEmpty) 'admin_id': resolvedAdminId,
  },
);
    // ئاگادارکردنەوەی پارەدانەوە بنێرە بۆ کڕیار (ناو ئاپ + تێلیگرام)
    try {
      final customerId = debt.getStringValue('customer');
      if (customerId.isNotEmpty) {
        // ناوی ناردنکار بدۆزەرەوە
        String senderName = createdByName ?? '';
        if (senderName.isEmpty) {
          try {
            final creator = await pb.collection('users').getOne(createdBy);
            final role = creator.getStringValue('role');
            if (role == 'admin') {
              senderName = creator.getStringValue('name');
            } else {
              final adminId = creator.getStringValue('admin_id');
              if (adminId.isNotEmpty) {
                final admin = await pb.collection('users').getOne(adminId);
                senderName = admin.getStringValue('name');
              } else {
                senderName = creator.getStringValue('name');
              }
            }
          } catch (_) {
            senderName = 'بەڕێوەبەر';
          }
        }

        // فۆرماتی بڕ
        final formattedAmount =
            '${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} د.ع';
        final formattedRemaining =
            '${newRemaining.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} د.ع';

        final isFullyPaid = newRemaining <= 0;

        final message = isFullyPaid
            ? '✅ قەرزەکەت بە تەواوی دراوەتەوە!\n'
                  'بڕی دراو: $formattedAmount لەلایەن $senderName 🎉'
            : '💰 پارەدانەوەی $formattedAmount تۆمارکرا.\n'
                  'لەلایەن $senderName\n'
                  'ماوە: $formattedRemaining';

        await createNotification(
          customerId: customerId,
          message: message,
          senderId: createdBy,
          type: 'payment',
          adminId: resolvedAdminId,
        );
      }
    } catch (_) {
      // ئاگادارکردنەوە نەتوانرا بنێردرێت — بەردەوام بە
    }

    return payment;
  }

  static Future<List<RecordModel>> getPayments({
    String? debtId,
    String? createdBy,
    String? customerId,
  }) async {
    List<String> filters = [];

    if (debtId != null) filters.add('debt = "${_sanitize(debtId)}"');
    if (createdBy != null) filters.add('created_by = "${_sanitize(createdBy)}"');
    if (customerId != null) {
      // Supports Customer Profile chat timeline by loading all payments
      // that belong to the selected customer through the related debt.
      filters.add('debt.customer = "${_sanitize(customerId)}"');
    }

    final filter = filters.isNotEmpty ? filters.join(' && ') : '';

    final result = await pb
        .collection('payments')
        .getList(
          filter: filter,
          sort: '-created',
          expand: 'debt,created_by,debt.customer',
          perPage: 500,
        );

    return result.items;
  }

  static Future<Map<String, double>> getEmployeeStats(String employeeId) async {
    // 1. Get total debts created by this employee
    final debts = await getDebts(
      createdBy: employeeId,
    ); // adminId param actually filters created_by
    double totalDebtsCreated = 0;
    for (var debt in debts) {
      totalDebtsCreated += debt.getDoubleValue('amount');
    }

    // 2. Get total payments collected by this employee
    final payments = await getPayments(createdBy: employeeId);
    double totalPaymentsCollected = 0;
    for (var payment in payments) {
      totalPaymentsCollected += payment.getDoubleValue('amount');
    }

    return {
      'totalDebtsCreated': totalDebtsCreated,
      'totalPaymentsCollected': totalPaymentsCollected,
    };
  }

  static Future<Map<String, int>> getDebtCounts({
    required String adminId,
  }) async {
    final safeAdminId = _sanitize(adminId);

    final pendingResult = await pb
        .collection('debts')
        .getList(
          filter: 'customer.admin_id = "$safeAdminId" && status = "pending"',
          perPage: 1,
        );

    final partialResult = await pb
        .collection('debts')
        .getList(
          filter: 'customer.admin_id = "$safeAdminId" && status = "partial"',
          perPage: 1,
        );

    final paidResult = await pb
        .collection('debts')
        .getList(
          filter: 'customer.admin_id = "$safeAdminId" && status = "paid"',
          perPage: 1,
        );

    return {
      'pending': pendingResult.totalItems,
      'partial': partialResult.totalItems,
      'paid': paidResult.totalItems,
    };
  }

  // ==================== Stats ====================

  static Future<Map<String, dynamic>> getDashboardStats({
    String? adminId,
  }) async {
    // Filters
    final safeAdminId = adminId != null ? _sanitize(adminId) : null;
    String customerFilter = 'role = "customer"';
    if (safeAdminId != null) customerFilter += ' && admin_id = "$safeAdminId"';

    String debtFilter = '';
    if (safeAdminId != null) debtFilter = 'customer.admin_id = "$safeAdminId"';

    String paymentFilter = '';
    if (safeAdminId != null) paymentFilter = 'debt.customer.admin_id = "$safeAdminId"';

    String pendingFilter = 'role = "customer" && approved = false';
    if (safeAdminId != null) pendingFilter += ' && admin_id = "$safeAdminId"';

    // Execute all requests in parallel
    final results = await Future.wait([
      // 0. Total Customers Count
      pb
          .collection('users')
          .getList(filter: '$customerFilter && approved = true', perPage: 1),

      // 1. All Debts (for sums - max 500)
      pb.collection('debts').getList(filter: debtFilter, perPage: 500),

      // 2. All Payments (for sums - max 500)
      pb.collection('payments').getList(filter: paymentFilter, perPage: 500),

      // 3. Pending Requests Count
      pb.collection('users').getList(filter: pendingFilter, perPage: 1),

      // 4. Recent Activity (Latest 5 items)
      pb
          .collection('debts')
          .getList(
            filter: debtFilter,
            sort: '-created',
            perPage: 5,
            expand: 'customer,created_by',
          ),
    ]);

    // Process Customers
    final customersResult = results[0];

    // Process Debts
    final debts = results[1];
    double totalDebt = 0;
    double totalRemaining = 0;
    int pendingCount = 0;
    for (var debt in debts.items) {
      totalDebt += debt.getDoubleValue('amount');
      totalRemaining += debt.getDoubleValue('remaining');
      if (debt.getStringValue('status') != 'paid') pendingCount++;
    }

    // Process Payments
    final payments = results[2];
    double totalPayments = 0;
    for (var payment in payments.items) {
      totalPayments += payment.getDoubleValue('amount');
    }

    // Process Pending
    final pending = results[3];

    // Process Recent Activity
    final recentDebts = results[4];

    return {
      'totalCustomers': customersResult.totalItems,
      'totalDebt': totalDebt,
      'totalRemaining': totalRemaining,
      'totalPayments': totalPayments,
      'pendingDebts': pendingCount,
      'pendingRequests': pending.totalItems,
      'recentActivity': recentDebts.items,
    };
  }

  // ───── Notification Methods ─────

  static Future<void> createNotification({
  required String customerId,
  required String message,
  required String senderId,
  String type = 'general',
  String? adminId,
}) async {
  // ١. لە PocketBase تۆمار بکە
  final body = <String, dynamic>{
    'customer': customerId,
    'message': message,
    'sender': senderId,
    'is_read': false,
    'type': type,
    if (adminId != null && adminId.isNotEmpty) 'admin_id': adminId,
  };

  await pb.collection('notifications').create(body: body);

  // Telegram Notification
    try {
      RecordModel? user;
      try {
        user = await getUser(customerId);
      } catch (e) {
        debugPrint('getUser failed: $e');
        final safeCustomerId = _sanitize(customerId);
        final list = await pb
            .collection('users')
            .getList(filter: 'id = "$safeCustomerId"', perPage: 1);
        if (list.items.isNotEmpty) {
          user = list.items.first;
        }
      }

      if (user != null) {
        final botToken = user.getStringValue('telegram_bot_token');
        final chatId = user.getStringValue('telegram_chat_id');

        if (botToken.isNotEmpty && chatId.isNotEmpty) {
          await sendTelegramMessage(botToken, chatId, message);
        }
      }
    } catch (e) {
      debugPrint('Telegram notification error: $e');
    }
  }

  static Future<bool> sendTelegramMessage(
    String botToken,
    String chatId,
    String text,
  ) async {
    final url = 'https://api.telegram.org/bot$botToken/sendMessage';
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chat_id': chatId, 'text': text}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Telegram send error: $e');
      return false;
    }
  }

  static Future<List<RecordModel>> getNotifications(String customerId) async {
    final safeCustomerId = _sanitize(customerId);
    final result = await pb
        .collection('notifications')
        .getList(
          filter: 'customer = "$safeCustomerId"',
          sort: '-created',
          perPage: 50,
          expand: 'sender',
        );
    return result.items;
  }

  static Future<int> getUnreadNotificationCount(String customerId) async {
    final safeCustomerId = _sanitize(customerId);
    final result = await pb
        .collection('notifications')
        .getList(
          filter: 'customer = "$safeCustomerId" && is_read = false',
          perPage: 1,
        );
    return result.totalItems;
  }

  static Future<void> markNotificationRead(String id) async {
    await pb.collection('notifications').update(id, body: {'is_read': true});
  }

  static Future<void> deleteNotification(String id) async {
    await pb.collection('notifications').delete(id);
  }

  /// بپشکنە بۆ ئاگادارکردنەوەی نوێ (بەکاردەهێنرێت لە background)
  static Future<int> checkNewNotifications(String customerId) async {
    return await getUnreadNotificationCount(customerId);
  }

  /// پشکنینی قەرزە دواکەوتووەکان و ناردنی ئاگادارکردنەوە
  static Future<void> checkAndNotifyOverdueDebts() async {
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // هەموو قەرزە دواکەوتووەکان بدۆزەرەوە
      final overdueDebts = await pb
          .collection('debts')
          .getList(
            filter: 'due_date < "$today" && status != "paid" && remaining > 0',
            perPage: 500,
            expand: 'customer',
          );

      for (var debt in overdueDebts.items) {
        final customerId = debt.getStringValue('customer');
        final debtId = debt.id;

        // بپشکنە ئایا ئەمڕۆ ئاگادارکردنەوەی دواکەوتوو نێردراوە بۆ ئەم قەرزە
        final todayStart = '$today 00:00:00';
        final safeCustomerId = _sanitize(customerId);
        final safeDebtId = _sanitize(debtId);
        final existingNotifications = await pb
            .collection('notifications')
            .getList(
              filter:
                  'customer = "$safeCustomerId" && type = "debt_overdue" && message ~ "$safeDebtId" && created >= "$todayStart"',
              perPage: 1,
            );

        if (existingNotifications.items.isNotEmpty) continue; // ئەمڕۆ نێردراوە

        // پەیامی ئاگادارکردنەوە ئامادە بکە
        final remaining = debt.getDoubleValue('remaining');
        final dueDate = debt.getStringValue('due_date');

        final formattedAmount =
            '${remaining.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} د.ع';

        final message =
            '⚠️ قەرزی $formattedAmount دواکەوتووە!\n'
            'بەرواری دانەوە: ${dueDate.replaceAll('-', '/')} بووە.\n'
            'تکایە هەرچی زووتر بیگەڕێنەوە.\n'
            '[#$debtId]';

        // ئاگادارکردنەوە بنێرە (ناو ئاپ + تێلیگرام)
        await createNotification(
          customerId: customerId,
          message: message,
          senderId: customerId, // سیستەم خۆی ناردووە
          type: 'debt_overdue',
        );
      }
    } catch (_) {}
  }
}
