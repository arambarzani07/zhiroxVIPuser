import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/services/supabase_compat.dart';
import 'package:zhirox/utils/constants.dart';

class PBService {
  static bool _initialized = false;
  static Future<void>? _initializing;

  static final SupabasePBCompat pb = SupabasePBCompat(
    ensureInitialized: ensureInitialized,
  );

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    final pending = _initializing;
    if (pending != null) return pending;

    final completer = Completer<void>();
    _initializing = completer.future;
    () async {
      try {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          publishableKey: SupabaseConfig.publishableKey,
        );
        _initialized = true;
        completer.complete();
      } catch (e, st) {
        // If another caller initialized the singleton first, accept it.
        try {
          Supabase.instance.client;
          _initialized = true;
          completer.complete();
        } catch (_) {
          completer.completeError(e, st);
        }
      } finally {
        _initializing = null;
      }
    }();
    return completer.future;
  }

  static String _sanitize(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  static RecordModel _profileRecord(Map<String, dynamic> row) {
    final phone = row['phone']?.toString() ?? '';
    return RecordModel.fromJson({
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'users',
      'email': phone.isEmpty ? '' : '$phone@zhirox.local',
      'created': row['created_at']?.toString() ?? '',
      'updated': row['updated_at']?.toString() ?? row['created_at']?.toString() ?? '',
    });
  }

  static String _functionError(dynamic data) {
    final code = data is Map ? data['error']?.toString() ?? '' : data?.toString() ?? '';
    switch (code) {
      case 'phone_exists':
        return 'ئەم ژمارەیە پێشتر تۆمارکراوە';
      case 'invalid_admin':
        return 'بەڕێوەبەری هەڵبژێردراو دروست نییە';
      case 'admin_creation_requires_admin':
        return 'دروستکردنی ئەکاونتی بەڕێوەبەر تەنها لەلایەن بەڕێوەبەرێکی چالاکەوە دەکرێت';
      case 'employee_creation_requires_admin':
        return 'تەنها بەڕێوەبەر دەتوانێت کارمەند دروست بکات';
      case 'cross_tenant_forbidden':
      case 'forbidden':
        return 'دەسەڵاتی ئەم کردارەت نییە';
      case 'missing_permission':
        return 'مۆڵەتی ئەم کردارەت نییە';
      case 'invalid_input':
        return 'زانیارییەکان تەواو یان دروست نین';
      default:
        return code.isEmpty ? 'هەڵەیەک لە سێرڤەر ڕوویدا' : code;
    }
  }

  static Future<RecordModel> _invokeCreateAccount(Map<String, dynamic> body) async {
    await ensureInitialized();
    try {
      final response = await client.functions.invoke(
        'account-admin',
        body: {'action': 'create_user', ...body},
      );
      final data = response.data;
      if (data is! Map || data['user'] is! Map) {
        throw _functionError(data);
      }
      return _profileRecord(Map<String, dynamic>.from(data['user'] as Map));
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
  }

  // ==================== Auth ====================

  static Future<RecordModel> login(String phone, String password) async {
    await ensureInitialized();
    final cleanPhone = phone.trim();
    final email = cleanPhone.contains('@')
        ? cleanPhone
        : '$cleanPhone@zhirox.local';

    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final authUser = response.user;
      if (authUser == null) throw Exception('invalid login');

      final user = await getUser(authUser.id);
      final role = user.getStringValue('role');

      if (role == 'customer' && !user.getBoolValue('approved')) {
        await client.auth.signOut();
        throw AppStrings.notApproved;
      }
      if (role == 'employee' && !user.getBoolValue('active')) {
        await client.auth.signOut();
        throw 'ئەم ئەکاونتە لەلایەن ئەدمینەوە ناچالاک کراوە';
      }

      if (role == 'employee' || role == 'customer') {
        final adminId = user.getStringValue('admin_id');
        if (adminId.isNotEmpty) {
          final admin = await pb.collection('users').getOne(adminId);
          final subEnd = admin.getStringValue('subscription_end');
          if (subEnd.isNotEmpty && DateTime.parse(subEnd).isBefore(DateTime.now())) {
            await client.auth.signOut();
            throw 'ماوەی ڕێکەوتنی بەڕێوەبەرەکەت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەرەکەت.';
          }
        }
      }
      return user;
    } on AuthException catch (_) {
      throw Exception('وشەی نهێنی هەڵەیە');
    }
  }

  static Future<void> logout() async {
    await ensureInitialized();
    try {
      await client.removeAllChannels();
    } catch (_) {}
    try {
      await client.auth.signOut();
    } catch (_) {}
  }

  // ==================== Registration ====================

  static Future<RecordModel> registerAdmin({
    required String marketName,
    required String adminName,
    required String phone,
    required String password,
    required int subscriptionDays,
  }) {
    return _invokeCreateAccount({
      'role': 'admin',
      'market_name': marketName,
      'name': adminName,
      'phone': phone.trim(),
      'password': password,
      'subscription_days': subscriptionDays,
    });
  }

  static Future<RecordModel> registerCustomer({
    required String name,
    String fatherName = '',
    String grandfatherName = '',
    required String phone,
    required String password,
    required String adminId,
  }) {
    return _invokeCreateAccount({
      'role': 'customer',
      'name': name,
      'father_name': fatherName,
      'grandfather_name': grandfatherName,
      'phone': phone.trim(),
      'password': password,
      'admin_id': adminId,
    });
  }

  // ==================== Admin Subscription Management ====================

  static Future<Map<String, dynamic>> getAdminsPage({
    int page = 1,
    int perPage = 15,
  }) async {
    await ensureInitialized();
    final result = await pb.collection('users').getList(
      filter: 'role = "admin"',
      sort: '-created',
      page: page,
      perPage: perPage,
    );
    final admins = <Map<String, dynamic>>[];
    for (final admin in result.items) {
      final adminId = _sanitize(admin.id);
      final employees = await pb.collection('users').getList(
        filter: 'admin_id = "$adminId" && role = "employee"',
        perPage: 1,
      );
      final customers = await pb.collection('users').getList(
        filter: 'admin_id = "$adminId" && role = "customer"',
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

  static Future<void> renewAdminSubscription(String adminId, int days) async {
    final newEnd = DateTime.now().add(Duration(days: days));
    await pb.collection('users').update(
      adminId,
      body: {'subscription_end': newEnd.toUtc().toIso8601String()},
    );
  }

  static Future<void> deleteAdminWithData(String adminId) async {
    await ensureInitialized();
    try {
      final response = await client.functions.invoke(
        'account-admin',
        body: {'action': 'delete_user', 'user_id': adminId},
      );
      if (response.data is Map && response.data['error'] != null) {
        throw _functionError(response.data);
      }
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
  }

  static Future<int> checkSubscriptionDaysLeft(String adminId) async {
    final admin = await pb.collection('users').getOne(adminId);
    final subEnd = admin.getStringValue('subscription_end');
    if (subEnd.isEmpty) return 9999;
    return DateTime.parse(subEnd).difference(DateTime.now()).inDays;
  }

  // ==================== Admin Approval ====================

  static Future<List<RecordModel>> getAdminList() async {
    await ensureInitialized();
    final data = await client.rpc('list_active_markets');
    final rows = (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return rows
        .map((row) => _profileRecord({
              ...row,
              'role': 'admin',
              'approved': true,
              'active': true,
              'created_at': '',
              'updated_at': '',
            }))
        .toList();
  }

  static Future<List<RecordModel>> getPendingCustomers(String adminId) {
    return getUsers(role: 'customer', adminId: adminId, approved: false);
  }

  static Future<void> approveCustomer(String id, int debtDuration) {
    return updateUser(id, {'approved': true, 'debt_duration': debtDuration});
  }

  static Future<void> rejectCustomer(String id) => deleteUser(id);

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
  }) {
    return _invokeCreateAccount({
      'name': name,
      'father_name': fatherName,
      'grandfather_name': grandfatherName,
      'phone': phone.trim(),
      'password': password,
      'role': role,
      'created_by': createdBy,
      'admin_id': adminId ?? createdBy,
      'can_add_customers': canAddCustomers,
      'can_set_debt_limit': canSetDebtLimit,
      'can_set_due_date': canSetDueDate,
      'can_edit_debts': canEditDebts,
      'can_send_notifications': canSendNotifications,
      'debt_limit': debtLimit,
    });
  }

  static Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await ensureInitialized();
    final mutable = Map<String, dynamic>.from(data);
    final botToken = mutable.remove('telegram_bot_token');
    final chatId = mutable.remove('telegram_chat_id');

    if ((botToken != null || chatId != null) && client.auth.currentUser?.id == id) {
      String resolvedToken = botToken?.toString() ?? '';
      String resolvedChat = chatId?.toString() ?? '';
      if (botToken == null || chatId == null) {
        try {
          final current = await client.rpc('get_my_telegram_credentials');
          if (current is List && current.isNotEmpty) {
            final row = Map<String, dynamic>.from(current.first as Map);
            if (botToken == null) resolvedToken = row['bot_token']?.toString() ?? '';
            if (chatId == null) resolvedChat = row['chat_id']?.toString() ?? '';
          }
        } catch (_) {}
      }
      await client.rpc(
        'set_my_telegram_credentials',
        params: {'p_bot_token': resolvedToken, 'p_chat_id': resolvedChat},
      );
    }

    if (mutable.isEmpty) return;
    try {
      final response = await client.functions.invoke(
        'update-account',
        body: {'user_id': id, 'data': mutable},
      );
      if (response.data is Map && response.data['error'] != null) {
        throw _functionError(response.data);
      }
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
  }

  static Future<void> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    await ensureInitialized();
    if (client.auth.currentUser?.id != userId) {
      throw Exception('دەسەڵاتی گۆڕینی ئەم وشەی نهێنییەت نییە');
    }
    final profile = await getUser(userId);
    final phone = profile.getStringValue('phone');
    try {
      await client.auth.signInWithPassword(
        email: '$phone@zhirox.local',
        password: oldPassword,
      );
    } on AuthException catch (_) {
      throw Exception('وشەی نهێنیی کۆن هەڵەیە');
    }
    await client.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> deleteUser(String id) async {
    await ensureInitialized();
    try {
      final response = await client.functions.invoke(
        'account-admin',
        body: {'action': 'delete_user', 'user_id': id},
      );
      if (response.data is Map && response.data['error'] != null) {
        throw _functionError(response.data);
      }
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
  }

  static Future<List<RecordModel>> getUsers({
    String? role,
    String? search,
    String? adminId,
    bool? approved,
  }) async {
    final filters = <String>[];
    if (role != null) filters.add('role = "${_sanitize(role)}"');
    if (adminId != null) filters.add('admin_id = "${_sanitize(adminId)}"');
    if (approved != null) filters.add('approved = $approved');
    if (search != null && search.isNotEmpty) {
      final q = _sanitize(search);
      filters.add('(name ~ "$q" || father_name ~ "$q" || phone ~ "$q")');
    }
    final result = await pb.collection('users').getList(
      filter: filters.join(' && '),
      sort: '-created',
      perPage: 500,
    );
    return result.items;
  }

  static Future<RecordModel> getUser(String id) async {
    var user = await pb.collection('users').getOne(id);
    await ensureInitialized();
    if (client.auth.currentUser?.id == id) {
      try {
        final data = await client.rpc('get_my_telegram_credentials');
        if (data is List && data.isNotEmpty) {
          final creds = Map<String, dynamic>.from(data.first as Map);
          final json = user.toJson();
          json['telegram_bot_token'] = creds['bot_token']?.toString() ?? '';
          json['telegram_chat_id'] = creds['chat_id']?.toString() ?? '';
          user = RecordModel.fromJson(json);
        }
      } catch (_) {}
    }
    return user;
  }

  // ==================== Debts ====================

  static Future<double> getCustomerBalance(String customerId) async {
    try {
      final debts = await getDebts(customerId: customerId);
      return debts.fold<double>(
        0,
        (sum, debt) => sum + debt.getDoubleValue('remaining'),
      );
    } catch (_) {
      return 0;
    }
  }

  static String _mimeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  static Future<String> _uploadReceipt(String sourcePath, String createdBy) async {
    await ensureInitialized();
    final creator = await getUser(createdBy);
    final tenantId = creator.getStringValue('role') == 'admin'
        ? creator.id
        : creator.getStringValue('admin_id');
    if (tenantId.isEmpty) throw Exception('tenant not found');
    final ext = sourcePath.contains('.') ? sourcePath.substring(sourcePath.lastIndexOf('.')) : '.jpg';
    final storagePath = '$tenantId/${DateTime.now().microsecondsSinceEpoch}$ext';
    final bytes = await File(sourcePath).readAsBytes();
    await client.storage.from('receipts').uploadBinary(
      storagePath,
      bytes,
      fileOptions: FileOptions(contentType: _mimeForPath(sourcePath), upsert: false),
    );
    return storagePath;
  }

  static Future<RecordModel> createDebt({
    required String customerId,
    required String description,
    required double amount,
    required String dueDate,
    required String createdBy,
    String currency = 'IQD',
    double dollarRate = 0,
    double amountUsd = 0,
    List<Map<String, dynamic>>? items,
    String? createdByName,
    String? marketName,
    String? customCreatedDate,
    String? receiptImagePath,
  }) async {
    String receiptPath = '';
    if (receiptImagePath != null && receiptImagePath.isNotEmpty) {
      receiptPath = await _uploadReceipt(receiptImagePath, createdBy);
    }

    final body = <String, dynamic>{
      'customer': customerId,
      'description': description,
      'amount': amount,
      'remaining': amount,
      'due_date': dueDate,
      'status': 'pending',
      'created_by': createdBy,
      'currency': currency,
      'dollar_rate': dollarRate,
      'amount_usd': amountUsd,
      'items': jsonEncode(items ?? const <Map<String, dynamic>>[]),
      if (customCreatedDate != null && customCreatedDate.isNotEmpty)
        'custom_date': customCreatedDate,
      if (receiptPath.isNotEmpty) 'receipt_image': receiptPath,
    };

    final created = await pb.collection('debts').create(body: body);

    try {
      final formattedAmount =
          '${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} د.ع';
      String senderName = createdByName ?? 'کارمەند';
      String resolvedMarketName = marketName ?? '';
      try {
        final creator = await getUser(createdBy);
        if (creator.getStringValue('role') == 'admin') {
          senderName = creator.getStringValue('name');
          if (resolvedMarketName.isEmpty) {
            resolvedMarketName = creator.getStringValue('market_name');
          }
        } else {
          final adminId = creator.getStringValue('admin_id');
          if (adminId.isNotEmpty) {
            final admin = await getUser(adminId);
            senderName = admin.getStringValue('name');
            if (resolvedMarketName.isEmpty) {
              resolvedMarketName = admin.getStringValue('market_name');
            }
          }
        }
      } catch (_) {}
      final marketLine = resolvedMarketName.isEmpty ? '' : '$resolvedMarketName\n';
      final dueLine = dueDate.isEmpty ? '' : '\nبەرواری دانەوە: ${dueDate.replaceAll('-', '/')}';
      await createNotification(
        customerId: customerId,
        message: '$marketLineقەرزی $formattedAmount لەلایەن $senderName زیادکرا.$dueLine',
        senderId: createdBy,
        type: 'debt_created',
      );
    } catch (_) {}

    return await getDebt(created.id);
  }

  static Future<void> updateDebt(String id, Map<String, dynamic> data) async {
    await pb.collection('debts').update(id, body: data);
  }

  static Future<void> deleteDebt(String id) async {
    final payments = await pb.collection('payments').getList(
      filter: 'debt = "${_sanitize(id)}"',
      perPage: 500,
    );
    for (final payment in payments.items) {
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
    int perPage = 500,
    String? filter,
  }) async {
    final filters = <String>[];
    if (customerId != null) filters.add('customer = "${_sanitize(customerId)}"');
    if (status != null) filters.add('status = "${_sanitize(status)}"');
    if (createdBy != null) filters.add('created_by = "${_sanitize(createdBy)}"');
    if (adminId != null) filters.add('customer.admin_id = "${_sanitize(adminId)}"');
    if (filter != null && filter.isNotEmpty) filters.add(filter);
    final result = await pb.collection('debts').getList(
      page: page,
      perPage: perPage,
      filter: filters.join(' && '),
      sort: '-created',
      expand: 'customer,created_by',
    );
    return result.items;
  }

  static Future<Map<String, dynamic>> getDebtsPaginated({
    String? customerId,
    String? status,
    String? createdBy,
    String? adminId,
    int page = 1,
    int perPage = 20,
    String? filter,
  }) async {
    final filters = <String>[];
    if (customerId != null) filters.add('customer = "${_sanitize(customerId)}"');
    if (status != null) filters.add('status = "${_sanitize(status)}"');
    if (createdBy != null) filters.add('created_by = "${_sanitize(createdBy)}"');
    if (adminId != null) filters.add('customer.admin_id = "${_sanitize(adminId)}"');
    if (filter != null && filter.isNotEmpty) filters.add(filter);
    final result = await pb.collection('debts').getList(
      page: page,
      perPage: perPage,
      filter: filters.join(' && '),
      sort: '-created',
      expand: 'customer,created_by',
    );
    return {
      'items': result.items,
      'totalItems': result.totalItems,
      'totalPages': result.totalPages,
    };
  }

  static Future<RecordModel> getDebt(String id) {
    return pb.collection('debts').getOne(id, expand: 'customer,created_by');
  }

  // ==================== Payments ====================

  static Future<RecordModel> createPayment({
    required String debtId,
    required double amount,
    String? note,
    required String createdBy,
    String? createdByName,
  }) async {
    final payment = await pb.collection('payments').create(
      body: {
        'debt': debtId,
        'amount': amount,
        'note': note ?? '',
        'created_by': createdBy,
      },
    );

    final debt = await getDebt(debtId);
    final remaining = debt.getDoubleValue('remaining') - amount;
    final newRemaining = remaining <= 0 ? 0.0 : remaining;
    final newStatus = remaining <= 0 ? 'paid' : 'partial';
    await pb.collection('debts').update(
      debtId,
      body: {'remaining': newRemaining, 'status': newStatus},
    );

    try {
      final customerId = debt.getStringValue('customer');
      if (customerId.isNotEmpty) {
        String senderName = createdByName ?? '';
        if (senderName.isEmpty) {
          try {
            final creator = await getUser(createdBy);
            if (creator.getStringValue('role') == 'admin') {
              senderName = creator.getStringValue('name');
            } else {
              final adminId = creator.getStringValue('admin_id');
              senderName = adminId.isEmpty
                  ? creator.getStringValue('name')
                  : (await getUser(adminId)).getStringValue('name');
            }
          } catch (_) {
            senderName = 'بەڕێوەبەر';
          }
        }
        final formattedAmount =
            '${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} د.ع';
        final formattedRemaining =
            '${newRemaining.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} د.ع';
        final message = newRemaining <= 0
            ? '✅ قەرزەکەت بە تەواوی دراوەتەوە!\nبڕی دراو: $formattedAmount لەلایەن $senderName 🎉'
            : '💰 پارەدانەوەی $formattedAmount تۆمارکرا.\nلەلایەن $senderName\nماوە: $formattedRemaining';
        await createNotification(
          customerId: customerId,
          message: message,
          senderId: createdBy,
          type: 'payment',
        );
      }
    } catch (_) {}

    return payment;
  }

  static Future<List<RecordModel>> getPayments({
    String? debtId,
    String? createdBy,
    String? customerId,
  }) async {
    final filters = <String>[];
    if (debtId != null) filters.add('debt = "${_sanitize(debtId)}"');
    if (createdBy != null) filters.add('created_by = "${_sanitize(createdBy)}"');
    if (customerId != null) {
      filters.add('debt.customer = "${_sanitize(customerId)}"');
    }
    final result = await pb.collection('payments').getList(
      filter: filters.join(' && '),
      sort: '-created',
      expand: 'debt,created_by,debt.customer',
      perPage: 500,
    );
    return result.items;
  }

  static Future<Map<String, double>> getEmployeeStats(String employeeId) async {
    final debts = await getDebts(createdBy: employeeId);
    final payments = await getPayments(createdBy: employeeId);
    return {
      'totalDebtsCreated': debts.fold<double>(0, (s, d) => s + d.getDoubleValue('amount')),
      'totalPaymentsCollected': payments.fold<double>(0, (s, p) => s + p.getDoubleValue('amount')),
    };
  }

  static Future<Map<String, int>> getDebtCounts({required String adminId}) async {
    final safeAdminId = _sanitize(adminId);
    final pending = await pb.collection('debts').getList(
      filter: 'customer.admin_id = "$safeAdminId" && status = "pending"',
      perPage: 1,
    );
    final partial = await pb.collection('debts').getList(
      filter: 'customer.admin_id = "$safeAdminId" && status = "partial"',
      perPage: 1,
    );
    final paid = await pb.collection('debts').getList(
      filter: 'customer.admin_id = "$safeAdminId" && status = "paid"',
      perPage: 1,
    );
    return {
      'pending': pending.totalItems,
      'partial': partial.totalItems,
      'paid': paid.totalItems,
    };
  }

  // ==================== Stats ====================

  static Future<Map<String, dynamic>> getDashboardStats({String? adminId}) async {
    final safeAdminId = adminId != null ? _sanitize(adminId) : null;
    var customerFilter = 'role = "customer"';
    if (safeAdminId != null) customerFilter += ' && admin_id = "$safeAdminId"';
    var debtFilter = '';
    if (safeAdminId != null) debtFilter = 'customer.admin_id = "$safeAdminId"';
    var paymentFilter = '';
    if (safeAdminId != null) paymentFilter = 'debt.customer.admin_id = "$safeAdminId"';
    var pendingFilter = 'role = "customer" && approved = false';
    if (safeAdminId != null) pendingFilter += ' && admin_id = "$safeAdminId"';

    final results = await Future.wait([
      pb.collection('users').getList(filter: '$customerFilter && approved = true', perPage: 1),
      pb.collection('debts').getList(filter: debtFilter, perPage: 500),
      pb.collection('payments').getList(filter: paymentFilter, perPage: 500),
      pb.collection('users').getList(filter: pendingFilter, perPage: 1),
      pb.collection('debts').getList(
        filter: debtFilter,
        sort: '-created',
        perPage: 5,
        expand: 'customer,created_by',
      ),
    ]);

    final customers = results[0] as PBListResult;
    final debts = results[1] as PBListResult;
    final payments = results[2] as PBListResult;
    final pending = results[3] as PBListResult;
    final recent = results[4] as PBListResult;

    double totalDebt = 0;
    double totalRemaining = 0;
    int pendingCount = 0;
    for (final debt in debts.items) {
      totalDebt += debt.getDoubleValue('amount');
      totalRemaining += debt.getDoubleValue('remaining');
      if (debt.getStringValue('status') != 'paid') pendingCount++;
    }
    double totalPayments = 0;
    for (final payment in payments.items) {
      totalPayments += payment.getDoubleValue('amount');
    }

    return {
      'totalCustomers': customers.totalItems,
      'totalDebt': totalDebt,
      'totalRemaining': totalRemaining,
      'totalPayments': totalPayments,
      'pendingDebts': pendingCount,
      'pendingRequests': pending.totalItems,
      'recentActivity': recent.items,
    };
  }

  // ==================== Notifications ====================

  static Future<void> createNotification({
    required String customerId,
    required String message,
    required String senderId,
    String type = 'general',
  }) async {
    await pb.collection('notifications').create(
      body: {
        'customer': customerId,
        'message': message,
        'sender': senderId,
        'is_read': false,
        'type': type,
      },
    );

    try {
      await ensureInitialized();
      await client.functions.invoke(
        'send-telegram',
        body: {'customer_id': customerId, 'message': message},
      );
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
    } catch (_) {
      return false;
    }
  }

  static Future<List<RecordModel>> getNotifications(String customerId) async {
    final result = await pb.collection('notifications').getList(
      filter: 'customer = "${_sanitize(customerId)}"',
      sort: '-created',
      perPage: 50,
      expand: 'sender',
    );
    return result.items;
  }

  static Future<int> getUnreadNotificationCount(String customerId) async {
    final result = await pb.collection('notifications').getList(
      filter: 'customer = "${_sanitize(customerId)}" && is_read = false',
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

  static Future<int> checkNewNotifications(String customerId) {
    return getUnreadNotificationCount(customerId);
  }

  static Future<void> checkAndNotifyOverdueDebts() async {
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final overdue = await pb.collection('debts').getList(
        filter: 'due_date < "$today" && status != "paid" && remaining > 0',
        perPage: 500,
        expand: 'customer',
      );

      for (final debt in overdue.items) {
        final customerId = debt.getStringValue('customer');
        final debtId = debt.id;
        final existing = await pb.collection('notifications').getList(
          filter:
              'customer = "${_sanitize(customerId)}" && type = "debt_overdue" && message ~ "${_sanitize(debtId)}" && created >= "$today 00:00:00"',
          perPage: 1,
        );
        if (existing.items.isNotEmpty) continue;

        final remaining = debt.getDoubleValue('remaining');
        final dueDate = debt.getStringValue('due_date');
        final formattedAmount =
            '${remaining.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} د.ع';
        await createNotification(
          customerId: customerId,
          message:
              '⚠️ قەرزی $formattedAmount دواکەوتووە!\nبەرواری دانەوە: ${dueDate.replaceAll('-', '/')} بووە.\nتکایە هەرچی زووتر بیگەڕێنەوە.\n[#$debtId]',
          senderId: customerId,
          type: 'debt_overdue',
        );
      }
    } catch (_) {}
  }
}
