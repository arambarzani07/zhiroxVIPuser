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
      case 'system_owner_required':
        return 'تەنها خاوەنی سیستەم دەتوانێت ئەم کردارە ئەنجام بدات';
      case 'cannot_delete_system_owner':
        return 'هەژماری خاوەنی سیستەم ناتوانرێت بسڕدرێتەوە';
      case 'admin_not_found':
        return 'هەژماری بەڕێوەبەر نەدۆزرایەوە';
      case 'owner_market_delete_disabled':
        return 'خاوەنی سیستەم ناتوانێت ناوەڕۆکی مارکێت بسڕێتەوە؛ لەبری ئەوە هەژمارەکە Suspend یان Archive بکە.';
      case 'invalid_lifecycle_status':
        return 'دۆخی هەژمار دروست نییە';
      case 'tenant_member_delete_failed':
        return 'سڕینەوەی هەندێک هەژماری ناو مارکێت سەرکەوتوو نەبوو؛ دووبارە هەوڵ بدەرەوە';
      case 'admin_delete_failed':
        return 'سڕینەوەی هەژماری بەڕێوەبەر سەرکەوتوو نەبوو';
      case 'invalid_input':
        return 'زانیارییەکان تەواو یان دروست نین';
      case 'fib_not_configured':
        return 'پارەدانی FIB هێشتا لەلایەن خاوەنی سیستەمەوە چالاک نەکراوە';
      case 'fib_auth_failed':
      case 'payment_create_failed':
      case 'payment_failed':
        return 'دروستکردنی پارەدانی FIB سەرکەوتوو نەبوو';
      case 'payment_not_found':
        return 'پارەدانەکە نەدۆزرایەوە';
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

      if (!user.getBoolValue('active')) {
        await client.auth.signOut();
        throw 'ئەم هەژمارە ناچالاک کراوە';
      }
      if (role == 'customer' && !user.getBoolValue('approved')) {
        await client.auth.signOut();
        throw AppStrings.notApproved;
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
    required String subscriptionPlan,
    required int subscriptionDays,
  }) {
    return _invokeCreateAccount({
      'role': 'admin',
      'market_name': marketName,
      'name': adminName,
      'phone': phone.trim(),
      'password': password,
      'subscription_plan': subscriptionPlan,
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
    final response = await client.functions.invoke(
      'account-admin',
      body: {
        'action': 'list_admins',
        'page': safePage,
        'per_page': safePerPage,
      },
    );
    if (response.data is Map && response.data['error'] != null) {
      throw _functionError(response.data);
    }
    final raw = response.data;
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

  static Future<Map<String, dynamic>> getOwnerPlatformOverview() async {
    await ensureInitialized();
    final raw = await client.rpc('get_system_owner_platform_overview');
    if (raw is! Map) throw Exception('invalid_owner_platform_overview');
    return Map<String, dynamic>.from(raw);
  }

  static Future<Map<String, dynamic>> getOwnerTenantsPage({
    int page = 1,
    int perPage = 20,
  }) async {
    await ensureInitialized();
    final raw = await client.rpc(
      'get_system_owner_tenants_page',
      params: {
        'p_page': page < 1 ? 1 : page,
        'p_per_page': perPage < 1 ? 1 : (perPage > 100 ? 100 : perPage),
      },
    );
    if (raw is! Map) throw Exception('invalid_owner_tenants_page');
    return Map<String, dynamic>.from(raw);
  }

  static Future<void> setOwnerTenantLifecycle({
    required String adminId,
    required String status,
    String reason = '',
  }) async {
    await ensureInitialized();
    await client.rpc(
      'set_system_owner_tenant_lifecycle',
      params: {
        'p_admin_id': adminId,
        'p_status': status,
        'p_reason': reason,
      },
    );
  }

  static Future<void> setOwnerTenantLimits({
    required String adminId,
    required int deviceLimit,
    required int staffLimit,
    required String supportTier,
  }) async {
    await ensureInitialized();
    await client.rpc(
      'set_system_owner_tenant_limits',
      params: {
        'p_admin_id': adminId,
        'p_device_limit': deviceLimit,
        'p_staff_limit': staffLimit,
        'p_support_tier': supportTier,
      },
    );
  }

  static Future<void> renewAdminSubscription(
    String adminId,
    String subscriptionPlan,
    int days,
  ) async {
    if (days < 1 || days > 3650) throw Exception('invalid_input');
    await ensureInitialized();
    final response = await client.functions.invoke(
      'account-admin',
      body: {
        'action': 'renew_subscription',
        'admin_id': adminId,
        'subscription_plan': subscriptionPlan,
        'days': days,
      },
    );
    if (response.data is Map && response.data['error'] != null) {
      throw _functionError(response.data);
    }
  }

  static Future<void> deleteAdminWithData(String adminId) async {
    await ensureInitialized();
    try {
      final response = await client.functions.invoke(
        'delete-account',
        body: {'user_id': adminId},
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

  static Future<Map<String, dynamic>> createFibSubscriptionPayment(
    String plan,
  ) async {
    await ensureInitialized();
    final response = await client.functions.invoke(
      'fib-subscription-payment',
      body: {'action': 'create', 'plan': plan},
    );
    if (response.data is Map && response.data['error'] != null) {
      throw _functionError(response.data);
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  static Future<String> checkFibSubscriptionPayment(String localPaymentId) async {
    await ensureInitialized();
    final response = await client.functions.invoke(
      'fib-subscription-payment',
      body: {'action': 'status', 'local_payment_id': localPaymentId},
    );
    if (response.data is Map && response.data['error'] != null) {
      throw _functionError(response.data);
    }
    return (response.data as Map)['status']?.toString() ?? 'pending';
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
    if (search != null && search.isNotEmpty) {
      await ensureInitialized();
      const pageSize = 100;
      var offset = 0;
      final users = <RecordModel>[];
      while (true) {
        final raw = await client.rpc('search_profiles_page', params: {
          'p_search': search,
          'p_role': role,
          'p_admin_id': adminId,
          'p_approved': approved,
          'p_limit': pageSize,
          'p_offset': offset,
        });
        if (raw is! List) throw const FormatException('invalid profile search');
        for (final item in raw) {
          if (item is Map) {
            users.add(_profileRecord(Map<String, dynamic>.from(item)));
          }
        }
        if (raw.length < pageSize) break;
        offset += pageSize;
      }
      return users;
    }
    await ensureInitialized();
    const pageSize = 500;
    var offset = 0;
    final users = <RecordModel>[];
    while (true) {
      dynamic query = client.from('profiles').select();
      if (role != null) query = query.eq('role', role);
      if (adminId != null) query = query.eq('admin_id', adminId);
      if (approved != null) query = query.eq('approved', approved);
      final raw = await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      final page = (raw as List)
          .map((row) => _profileRecord(Map<String, dynamic>.from(row as Map)))
          .toList(growable: false);
      users.addAll(page);
      if (page.length < pageSize) break;
      offset += pageSize;
    }
    return users;
  }

  static Future<List<RecordModel>> getAllApprovedCustomers({required String adminId}) {
    return getUsers(role: 'customer', approved: true, adminId: adminId);
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
    await ensureInitialized();
    const pageSize = 500;
    var offset = 0;
    var total = 0.0;
    while (true) {
      final raw = await client
          .from('debts')
          .select('remaining')
          .eq('customer_id', customerId)
          .isFilter('deleted_at', null)
          .order('id')
          .range(offset, offset + pageSize - 1);
      for (final row in raw) {
        total += _financeDouble(row['remaining']);
      }
      if (raw.length < pageSize) return total;
      offset += pageSize;
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
    double? subtotal,
    double discountPercent = 0,
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
      'subtotal': subtotal ?? amount,
      'discount_percent': discountPercent,
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

  /// Loads the complete debt history for an admin instead of silently
  /// truncating account statements at Supabase/PocketBase's page boundary.
  static Future<List<RecordModel>> getAllAdminDebts({
    required String adminId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    await ensureInitialized();
    const pageSize = 500;
    final records = <RecordModel>[];

    // Resolve only this admin's customers, then query debts for those customer
    // ids in bounded chunks so reports never scan or download other tenants.
    final profiles = <String, Map<String, dynamic>>{};
    var profileOffset = 0;
    while (true) {
      final profileData = await client
          .from('profiles')
          .select()
          .eq('admin_id', adminId)
          .order('id')
          .range(profileOffset, profileOffset + pageSize - 1);
      final profilePage = profileData
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
      for (final row in profilePage) {
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty) profiles[id] = row;
      }
      if (profilePage.length < pageSize) break;
      profileOffset += pageSize;
    }

    final customerIds = profiles.keys.toList(growable: false);
    const customerChunkSize = 50;
    for (var chunkStart = 0;
        chunkStart < customerIds.length;
        chunkStart += customerChunkSize) {
      final proposedEnd = chunkStart + customerChunkSize;
      final chunkEnd = proposedEnd < customerIds.length
          ? proposedEnd
          : customerIds.length;
      final chunk = customerIds.sublist(chunkStart, chunkEnd);
      var debtOffset = 0;
      while (true) {
        dynamic query = client
            .from('debts')
            .select()
            .inFilter('customer_id', chunk)
            .isFilter('deleted_at', null);
        if (fromDate != null) {
          query = query.gte(
            'created_at',
            fromDate.toUtc().toIso8601String(),
          );
        }
        if (toDate != null) {
          query = query.lt(
            'created_at',
            toDate.toUtc().toIso8601String(),
          );
        }
        final data = await query
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(debtOffset, debtOffset + pageSize - 1);
        final rows = (data as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        for (final row in rows) {
          final profile = profiles['${row['customer_id']}'];
          if (profile == null) continue;
          final json = _debtRecordFromRaw(row).toJson();
          json['expand'] = <String, dynamic>{
            'customer': _profileRecord(profile).toJson(),
          };
          records.add(RecordModel.fromJson(json));
        }
        if (rows.length < pageSize) break;
        debtOffset += pageSize;
      }
    }

    records.sort((a, b) {
      final aCreated = DateTime.tryParse(a.getStringValue('created'));
      final bCreated = DateTime.tryParse(b.getStringValue('created'));
      if (aCreated == null && bCreated == null) return 0;
      if (aCreated == null) return 1;
      if (bCreated == null) return -1;
      return bCreated.compareTo(aCreated);
    });
    return records;
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
    if (customerId != null &&
        createdBy == null &&
        adminId == null &&
        (filter == null || filter.isEmpty)) {
      await ensureInitialized();
      final raw = await client.rpc(
        'get_customer_debts_page',
        params: {
          'p_customer_id': customerId,
          'p_status': status,
          'p_page': page,
          'p_limit': perPage,
        },
      );
      if (raw is! Map) throw Exception('invalid customer debt page');
      final data = Map<String, dynamic>.from(raw);
      final items = <RecordModel>[];
      final rawItems = data['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            items.add(_debtRecordFromRaw(Map<String, dynamic>.from(item)));
          }
        }
      }
      final totalItems = int.tryParse('${data['total_count'] ?? 0}') ?? 0;
      return {
        'items': items,
        'totalItems': totalItems,
        'totalPages': totalItems == 0 ? 0 : (totalItems / perPage).ceil(),
      };
    }

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
  final response = await client.functions.invoke(
    'record-payment',
    body: {
      'debt_id': debtId,
      'amount': amount,
      'note': note ?? '',
      'reference_kind': referenceKind,
      'reference_id': referenceId,
    },
  );
  if (response.data is Map && response.data['error'] != null) {
    throw _functionError(response.data);
  }
  final rpcResult = response.data;

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
  if (debtId != null && customerId == null) {
    await ensureInitialized();
    const pageSize = 500;
    var offset = 0;
    final payments = <RecordModel>[];
    while (true) {
      dynamic query = client.from('payments').select('''
        *,
        debt_expand:debts!payments_debt_id_fkey(
          *,
          customer_expand:profiles!debts_customer_id_fkey(*),
          debt_creator_expand:profiles!debts_created_by_fkey(*)
        ),
        creator_expand:profiles!payments_created_by_fkey(*)
      ''').eq('debt_id', debtId);
      if (createdBy != null) {
        query = query.eq('created_by', createdBy);
      }
      final raw = await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);

      for (final item in raw) {
        final row = Map<String, dynamic>.from(item);
        final debtRaw = row.remove('debt_expand');
        final paymentCreatorRaw = row.remove('creator_expand');
        final paymentJson = _paymentRecordFromRaw(row).toJson();
        final paymentExpand = <String, dynamic>{};

        if (debtRaw is Map) {
          final debtRow = Map<String, dynamic>.from(debtRaw);
          final customerRaw = debtRow.remove('customer_expand');
          final debtCreatorRaw = debtRow.remove('debt_creator_expand');
          final debtJson = _debtRecordFromRaw(debtRow).toJson();
          final debtExpand = <String, dynamic>{};
          if (customerRaw is Map) {
            debtExpand['customer'] = _profileRecord(
              Map<String, dynamic>.from(customerRaw),
            ).toJson();
          }
          if (debtCreatorRaw is Map) {
            debtExpand['created_by'] = _profileRecord(
              Map<String, dynamic>.from(debtCreatorRaw),
            ).toJson();
          }
          if (debtExpand.isNotEmpty) debtJson['expand'] = debtExpand;
          paymentExpand['debt'] = debtJson;
        }
        if (paymentCreatorRaw is Map) {
          paymentExpand['created_by'] = _profileRecord(
            Map<String, dynamic>.from(paymentCreatorRaw),
          ).toJson();
        }
        if (paymentExpand.isNotEmpty) {
          paymentJson['expand'] = paymentExpand;
        }
        payments.add(RecordModel.fromJson(paymentJson));
      }

      if (raw.length < pageSize) break;
      offset += pageSize;
    }
    return payments;
  }

  if (customerId != null && debtId == null) {
    await ensureInitialized();
    const pageSize = 500;
    const debtChunkSize = 50;
    final debtIds = <String>[];
    var debtOffset = 0;
    while (true) {
      final debtRows = await client.from('debts').select('id')
          .eq('customer_id', customerId)
          .order('id')
          .range(debtOffset, debtOffset + pageSize - 1);
      for (final row in debtRows) {
        final id = row['id']?.toString() ?? '';
        if (id.isNotEmpty) debtIds.add(id);
      }
      if (debtRows.length < pageSize) break;
      debtOffset += pageSize;
    }
    if (debtIds.isEmpty) return <RecordModel>[];

    final payments = <RecordModel>[];
    for (var chunkStart = 0;
        chunkStart < debtIds.length;
        chunkStart += debtChunkSize) {
      final proposedEnd = chunkStart + debtChunkSize;
      final chunkEnd = proposedEnd < debtIds.length
          ? proposedEnd
          : debtIds.length;
      final chunk = debtIds.sublist(chunkStart, chunkEnd);
      var paymentOffset = 0;
      while (true) {
        dynamic query = client.from('payments').select('''
          *,
          debt_expand:debts!payments_debt_id_fkey(
            *,
            customer_expand:profiles!debts_customer_id_fkey(*),
            debt_creator_expand:profiles!debts_created_by_fkey(*)
          ),
          creator_expand:profiles!payments_created_by_fkey(*)
        ''').inFilter('debt_id', chunk);
        if (createdBy != null) {
          query = query.eq('created_by', createdBy);
        }
        final raw = await query
            .order('created_at', ascending: false)
            .order('id', ascending: false)
            .range(paymentOffset, paymentOffset + pageSize - 1);

        for (final item in raw) {
          final row = Map<String, dynamic>.from(item);
          final debtRaw = row.remove('debt_expand');
          final paymentCreatorRaw = row.remove('creator_expand');
          final paymentJson = _paymentRecordFromRaw(row).toJson();
          final paymentExpand = <String, dynamic>{};
          if (debtRaw is Map) {
            final debtRow = Map<String, dynamic>.from(debtRaw);
            final customerRaw = debtRow.remove('customer_expand');
            final debtCreatorRaw = debtRow.remove('debt_creator_expand');
            final debtJson = _debtRecordFromRaw(debtRow).toJson();
            final debtExpand = <String, dynamic>{};
            if (customerRaw is Map) {
              debtExpand['customer'] = _profileRecord(
                Map<String, dynamic>.from(customerRaw),
              ).toJson();
            }
            if (debtCreatorRaw is Map) {
              debtExpand['created_by'] = _profileRecord(
                Map<String, dynamic>.from(debtCreatorRaw),
              ).toJson();
            }
            if (debtExpand.isNotEmpty) debtJson['expand'] = debtExpand;
            paymentExpand['debt'] = debtJson;
          }
          if (paymentCreatorRaw is Map) {
            paymentExpand['created_by'] = _profileRecord(
              Map<String, dynamic>.from(paymentCreatorRaw),
            ).toJson();
          }
          if (paymentExpand.isNotEmpty) {
            paymentJson['expand'] = paymentExpand;
          }
          payments.add(RecordModel.fromJson(paymentJson));
        }

        if (raw.length < pageSize) break;
        paymentOffset += pageSize;
      }
    }
    payments.sort((a, b) {
      final byCreated = b.getStringValue('created').compareTo(
        a.getStringValue('created'),
      );
      if (byCreated != 0) return byCreated;
      return b.id.compareTo(a.id);
    });
    return payments;
  }
  final filters = <String>[];
  if (debtId != null) filters.add('debt = "${_sanitize(debtId)}"');
  if (createdBy != null) {
    filters.add('created_by = "${_sanitize(createdBy)}"');
  }
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
    await ensureInitialized();
    final debtTotal = await _sumPagedAmounts(
      table: 'debts',
      createdBy: employeeId,
      excludeDeletedDebts: true,
    );
    final paymentTotal = await _sumPagedAmounts(
      table: 'payments',
      createdBy: employeeId,
    );
    return {
      'totalDebtsCreated': debtTotal,
      'totalPaymentsCollected': paymentTotal,
    };
  }

  static Future<double> _sumPagedAmounts({
    required String table,
    required String createdBy,
    bool excludeDeletedDebts = false,
  }) async {
    const pageSize = 500;
    var offset = 0;
    var total = 0.0;
    while (true) {
      dynamic query = client
          .from(table)
          .select('amount')
          .eq('created_by', createdBy);
      if (excludeDeletedDebts) {
        query = query.isFilter('deleted_at', null);
      }
      final raw = await query.order('id').range(offset, offset + pageSize - 1);
      if (raw is! List) throw FormatException('invalid $table statistics');
      for (final item in raw) {
        if (item is Map) total += _financeDouble(item['amount']);
      }
      if (raw.length < pageSize) return total;
      offset += pageSize;
    }
  }

  static Future<Map<String, int>> getDebtCounts({required String adminId}) async {
    await ensureInitialized();
    final raw = await client.rpc(
      'get_admin_debt_counts',
      params: {'p_admin_id': adminId},
    );
    if (raw is! Map) throw const FormatException('invalid debt counts');
    final data = Map<String, dynamic>.from(raw);
    return {
      'pending': int.tryParse('${data['pending'] ?? 0}') ?? 0,
      'partial': int.tryParse('${data['partial'] ?? 0}') ?? 0,
      'paid': int.tryParse('${data['paid'] ?? 0}') ?? 0,
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
    const pageSize = 500;
    var offset = 0;
    final events = <RecordModel>[];
    while (true) {
      final data = await client
          .from('financial_events')
          .select()
          .eq('customer_id', customerId)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + pageSize - 1);
      for (final row in data) {
        events.add(
          _financialEventRecord(Map<String, dynamic>.from(row)),
        );
      }
      if (data.length < pageSize) break;
      offset += pageSize;
    }
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

  static RecordModel _dashboardDebtRecord(Map<String, dynamic> row) {
    final customer = row.remove('customer');
    final createdBy = row.remove('created_by');
    final json = _debtRecordFromRaw(row).toJson();
    json['expand'] = <String, dynamic>{
      if (customer is Map)
        'customer': _profileRecord(Map<String, dynamic>.from(customer)).toJson(),
      if (createdBy is Map)
        'created_by': _profileRecord(Map<String, dynamic>.from(createdBy)).toJson(),
    };
    return RecordModel.fromJson(json);
  }

  static Future<Map<String, dynamic>> getDashboardStats({String? adminId}) async {
    await ensureInitialized();
    final raw = await client.rpc('get_admin_dashboard_snapshot');
    if (raw is! Map) throw const FormatException('invalid dashboard snapshot');
    final data = Map<String, dynamic>.from(raw);
    final recent = <RecordModel>[];
    if (data['recent_activity'] is List) {
      for (final item in data['recent_activity'] as List) {
        if (item is Map) {
          recent.add(_dashboardDebtRecord(Map<String, dynamic>.from(item)));
        }
      }
    }

    double number(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    int integer(dynamic value) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? 0;

    return {
      'totalCustomers': integer(data['total_customers']),
      'totalDebt': number(data['total_debt']),
      'totalRemaining': number(data['total_remaining']),
      'totalPayments': number(data['total_payments']),
      'pendingDebts': integer(data['pending_debts']),
      'pendingRequests': integer(data['pending_requests']),
      'recentActivity': recent,
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
      await ensureInitialized();
      final senderId = client.auth.currentUser?.id;
      if (senderId == null || senderId.isEmpty) return;
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      const pageSize = 500;
      var offset = 0;
      while (true) {
        final raw = await client
            .from('debts')
            .select('id, customer_id, remaining, due_date')
            .lt('due_date', today)
            .neq('status', 'paid')
            .gt('remaining', 0)
            .isFilter('deleted_at', null)
            .order('due_date')
            .order('id')
            .range(offset, offset + pageSize - 1);
        for (final item in raw) {
          final debt = Map<String, dynamic>.from(item);
          final customerId = debt['customer_id']?.toString() ?? '';
          final debtId = debt['id']?.toString() ?? '';
          if (customerId.isEmpty || debtId.isEmpty) continue;
          final existing = await client
              .from('notifications')
              .select('id')
              .eq('customer_id', customerId)
              .eq('type', 'debt_overdue')
              .ilike('message', '%[#$debtId]%')
              .gte('created_at', DateTime(now.year, now.month, now.day)
                  .toUtc().toIso8601String())
              .limit(1);
          if (existing.isNotEmpty) continue;

          final remaining = _financeDouble(debt['remaining']);
          final dueDate = debt['due_date']?.toString() ?? '';
          final formattedAmount =
              '${remaining.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} د.ع';
          await createNotification(
            customerId: customerId,
            message:
                '⚠️ قەرزی $formattedAmount دواکەوتووە!\nبەرواری دانەوە: ${dueDate.replaceAll('-', '/')} بووە.\nتکایە هەرچی زووتر بیگەڕێنەوە.\n[#$debtId]',
            senderId: senderId,
            type: 'debt_overdue',
          );
        }
        if (raw.length < pageSize) break;
        offset += pageSize;
      }
    } catch (_) {}
  }

}
