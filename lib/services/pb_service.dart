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

  static bool _isRetryableAuthException(AuthException error) {
    final text = '${error.runtimeType} ${error.message}'.toLowerCase();
    return text.contains('retryable') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('fetch') ||
        text.contains('connection') ||
        text.contains('timeout') ||
        text.contains('temporarily unavailable') ||
        text.contains('bad gateway') ||
        text.contains('service unavailable') ||
        text.contains('gateway timeout') ||
        text.contains('internal server error') ||
        text.contains('too many requests');
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
    } on AuthException catch (e) {
      if (_isRetryableAuthException(e)) {
        throw SocketException('temporary authentication network failure');
      }
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
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage < 1 ? 1 : (perPage > 100 ? 100 : perPage);
    final raw = await client.rpc(
      'get_system_owner_admins_page',
      params: {
        'p_page': safePage,
        'p_per_page': safePerPage,
      },
    );
    if (raw is! Map) throw Exception('invalid admin management page');

    final data = Map<String, dynamic>.from(raw);
    final admins = <Map<String, dynamic>>[];
    final rawAdmins = data['admins'];
    if (rawAdmins is List) {
      for (final item in rawAdmins) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final rawAdmin = row['admin'];
        if (rawAdmin is! Map) continue;
        int asInt(dynamic value) =>
            value is int ? value : int.tryParse('${value ?? 0}') ?? 0;
        admins.add({
          'admin': _profileRecord(Map<String, dynamic>.from(rawAdmin)),
          'employeeCount': asInt(row['employee_count']),
          'customerCount': asInt(row['customer_count']),
        });
      }
    }

    int asInt(dynamic value, int fallback) =>
        value is int ? value : int.tryParse('${value ?? ''}') ?? fallback;
    return {
      'admins': admins,
      'totalItems': asInt(data['total_items'], admins.length),
      'totalPages': asInt(data['total_pages'], 1),
      'page': asInt(data['page'], safePage),
    };
  }

  static Future<void> renewAdminSubscription(String adminId, int days) async {
    if (days < 1 || days > 3650) throw Exception('invalid_input');
    await ensureInitialized();
    await client.rpc(
      'renew_system_owner_admin_subscription',
      params: {
        'p_admin_id': adminId,
        'p_days': days,
      },
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

  static Future<void> resetUserPassword({
    required String userId,
    required String newPassword,
  }) async {
    await ensureInitialized();
    if (newPassword.length < 8) {
      throw Exception('وشەی نهێنی لانیکەم ٨ پیت بێت');
    }
    try {
      final response = await client.functions.invoke(
        'account-admin',
        body: {
          'action': 'reset_password',
          'user_id': userId,
          'new_password': newPassword,
        },
      );
      if (response.data is Map && response.data['error'] != null) {
        throw _functionError(response.data);
      }
    } on FunctionsException catch (e) {
      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);
    }
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
    final debts = await getDebts(customerId: customerId);
    return debts.fold<double>(
      0,
      (sum, debt) => sum + debt.getDoubleValue('remaining'),
    );
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
    String? referenceKind,
    String? referenceId,
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
      'due_date': dueDate.trim().isEmpty ? null : dueDate,
      'status': 'pending',
      'created_by': createdBy,
      'currency': currency,
      'dollar_rate': dollarRate,
      'amount_usd': amountUsd,
      'items': jsonEncode(items ?? const <Map<String, dynamic>>[]),
      if (customCreatedDate != null && customCreatedDate.isNotEmpty)
        'custom_date': customCreatedDate,
      if (receiptPath.isNotEmpty) 'receipt_image': receiptPath,
      if (referenceKind != null &&
          referenceKind.isNotEmpty &&
          referenceId != null &&
          referenceId.isNotEmpty)
        'reference_kind': referenceKind,
      if (referenceKind != null &&
          referenceKind.isNotEmpty &&
          referenceId != null &&
          referenceId.isNotEmpty)
        'reference_id': referenceId,
    };

    RecordModel created;
    try {
      created = await pb.collection('debts').create(body: body);
    } catch (error) {
      if (receiptPath.isNotEmpty) {
        try {
          await client.storage.from('receipts').remove([receiptPath]);
        } catch (_) {}
      }
      rethrow;
    }

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
    final normalized = Map<String, dynamic>.from(data);
    for (final key in const ['due_date', 'custom_date']) {
      final value = normalized[key];
      if (value is String && value.trim().isEmpty) {
        normalized[key] = null;
      }
    }
    await pb.collection('debts').update(id, body: normalized);
  }

  static Future<void> deleteDebt(String id) async {
    final debt = await getDebt(id);
    final receiptPath = debt.getStringValue('receipt_image');

    // payments.debt_id is ON DELETE CASCADE in Postgres, so one debt delete
    // keeps the financial delete atomic instead of deleting payments piecemeal.
    await pb.collection('debts').delete(id);

    if (receiptPath.isNotEmpty) {
      try {
        await client.storage.from('receipts').remove([receiptPath]);
      } catch (_) {
        // Database deletion already succeeded. A storage cleanup failure must
        // not turn a completed financial transaction into an app-level error.
      }
    }
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
    String? referenceKind,
    String? referenceId,
  }) async {
    await ensureInitialized();
  final rpcResult = await client.rpc(
    'record_payment',
    params: {
      'p_debt_id': debtId,
      'p_amount': amount,
      'p_note': note ?? '',
      'p_reference_kind': referenceKind,
      'p_reference_id': referenceId,
    },
  );

  Map<String, dynamic>? paymentRow;
  if (rpcResult is Map) {
    paymentRow = Map<String, dynamic>.from(rpcResult);
  } else if (rpcResult is List && rpcResult.isNotEmpty && rpcResult.first is Map) {
    paymentRow = Map<String, dynamic>.from(rpcResult.first as Map);
  }
  final paymentId = paymentRow?['id']?.toString() ?? '';
  if (paymentId.isEmpty) {
    throw Exception('پارەدانەوە تۆمار نەکرا');
  }

  final payment = await pb.collection('payments').getOne(paymentId);
  final debt = await getDebt(debtId);
  final newRemaining = debt.getDoubleValue('remaining');

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

  static RecordModel _financialEventRecord(Map<String, dynamic> row) {
    final created = row['created_at']?.toString() ?? '';
    return RecordModel.fromJson({
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'financial_events',
      'created': created,
      'updated': created,
    });
  }

  static Future<List<RecordModel>> getFinancialEvents(String customerId) async {
    await ensureInitialized();
    final data = await client
        .from('financial_events')
        .select()
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .limit(500);
    final events = (data as List)
        .map((row) => _financialEventRecord(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
    return events.reversed.toList(growable: false);
  }

  static double _financeDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static RecordModel _debtRecordFromRaw(Map<String, dynamic> row) {
    final items = row['items'];
    final created = row['created_at']?.toString() ?? row['created']?.toString() ?? '';
    final updated = row['updated_at']?.toString() ?? row['updated']?.toString() ?? created;
    return RecordModel.fromJson({
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'debts',
      'customer': row['customer_id']?.toString() ?? row['customer']?.toString() ?? '',
      'receipt_image': row['receipt_image_path']?.toString() ??
          row['receipt_image']?.toString() ??
          '',
      'items': items is String ? items : jsonEncode(items ?? const <dynamic>[]),
      'created': created,
      'updated': updated,
    });
  }

  static RecordModel _paymentRecordFromRaw(
    Map<String, dynamic> row, {
    Map<String, dynamic>? relatedDebt,
  }) {
    final created = row['created_at']?.toString() ?? row['created']?.toString() ?? '';
    final json = <String, dynamic>{
      ...row,
      'id': row['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': 'payments',
      'debt': row['debt_id']?.toString() ?? row['debt']?.toString() ?? '',
      'created': created,
      'updated': row['updated_at']?.toString() ?? created,
    };
    if (relatedDebt != null) {
      json['expand'] = <String, dynamic>{
        'debt': _debtRecordFromRaw(relatedDebt).toJson(),
      };
    }
    return RecordModel.fromJson(json);
  }

  static Future<Map<String, Map<String, dynamic>>> getCustomerInboxRows(
    List<String> customerIds,
  ) async {
    if (customerIds.isEmpty) return const {};
    await ensureInitialized();
    final raw = await client.rpc(
      'get_customer_inbox_rows',
      params: {'p_customer_ids': customerIds},
    );
    if (raw is! List) throw Exception('invalid customer inbox rows');
    final result = <String, Map<String, dynamic>>{};
    for (final item in raw) {
      if (item is! Map) continue;
      final row = Map<String, dynamic>.from(item);
      final customerId = row['customer_id']?.toString() ?? '';
      if (customerId.isNotEmpty) result[customerId] = row;
    }
    return result;
  }

  static Future<void> markFinancialChatRead(
    String customerId, {
    required DateTime readThrough,
  }) async {
    await ensureInitialized();
    await client.rpc(
      'mark_financial_chat_read_through',
      params: {
        'p_customer_id': customerId,
        'p_read_through': readThrough.toUtc().toIso8601String(),
      },
    );
  }

  static Future<Map<String, dynamic>> getCustomerFinanceSnapshot(
    String customerId,
  ) async {
    await ensureInitialized();
    final raw = await client.rpc(
      'get_customer_finance_snapshot',
      params: {'p_customer_id': customerId},
    );
    if (raw is! Map) throw Exception('invalid finance snapshot');
    final data = Map<String, dynamic>.from(raw);
    final openRaw = data['open_debts'];
    final openDebts = <RecordModel>[];
    if (openRaw is List) {
      for (final item in openRaw) {
        if (item is Map) {
          openDebts.add(
            _debtRecordFromRaw(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return {
      'totalDebtIqd': _financeDouble(data['total_debt_iqd']),
      'totalRemainingIqd': _financeDouble(data['total_remaining_iqd']),
      'totalPaidIqd': _financeDouble(data['total_paid_iqd']),
      'openDebtCount': int.tryParse('${data['open_debt_count'] ?? 0}') ?? 0,
      'openDebts': openDebts,
      'complete': data['complete'] == true,
    };
  }

  static Future<Map<String, dynamic>> getCustomerFinancialTimelinePage({
    required String customerId,
    int limit = 50,
    Map<String, dynamic>? cursor,
  }) async {
    await ensureInitialized();
    final params = <String, dynamic>{
      'p_customer_id': customerId,
      'p_limit': limit.clamp(1, 100),
    };
    if (cursor != null) {
      final at = cursor['at']?.toString() ?? '';
      final kind = int.tryParse('${cursor['kind_rank'] ?? ''}');
      final id = cursor['id']?.toString() ?? '';
      if (at.isNotEmpty && kind != null && id.isNotEmpty) {
        params['p_cursor_at'] = at;
        params['p_cursor_kind'] = kind;
        params['p_cursor_id'] = id;
      }
    }

    final raw = await client.rpc(
      'get_customer_financial_timeline_page',
      params: params,
    );
    if (raw is! Map) throw Exception('invalid financial timeline page');
    final data = Map<String, dynamic>.from(raw);
    final debts = <RecordModel>[];
    final payments = <RecordModel>[];
    final financialEvents = <RecordModel>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final kind = item['kind']?.toString() ?? '';
        final recordRaw = item['record'];
        if (recordRaw is! Map) continue;
        final record = Map<String, dynamic>.from(recordRaw);
        if (kind == 'debt') {
          debts.add(_debtRecordFromRaw(record));
        } else if (kind == 'payment') {
          Map<String, dynamic>? related;
          final relatedRaw = item['related_debt'];
          if (relatedRaw is Map) {
            related = Map<String, dynamic>.from(relatedRaw);
          }
          payments.add(
            _paymentRecordFromRaw(record, relatedDebt: related),
          );
        } else if (kind == 'system') {
          financialEvents.add(_financialEventRecord(record));
        }
      }
    }

    final nextRaw = data['next_cursor'];
    return {
      'debts': debts,
      'payments': payments,
      'financialEvents': financialEvents,
      'hasMore': data['has_more'] == true,
      'nextCursor': nextRaw is Map
          ? Map<String, dynamic>.from(nextRaw)
          : null,
      'loadedCount': rawItems is List ? rawItems.length : 0,
    };
  }

  static Future<List<RecordModel>> getAllCustomerDebtsLive(
    String customerId,
  ) async {
    await ensureInitialized();
    const pageSize = 500;
    var offset = 0;
    final records = <RecordModel>[];
    while (true) {
      final data = await client
          .from('debts')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false)
          .range(offset, offset + pageSize - 1);
      final rows = (data as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      records.addAll(rows.map(_debtRecordFromRaw));
      if (rows.length < pageSize) break;
      offset += pageSize;
    }
    return records;
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

    final customers = results[0];
    final debts = results[1];
    final payments = results[2];
    final pending = results[3];
    final recent = results[4];

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
