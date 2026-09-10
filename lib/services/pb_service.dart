import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/utils/constants.dart';

class PBRealtimeEvent {
  const PBRealtimeEvent({this.record, this.action = 'update'});

  final RecordModel? record;
  final String action;
}

/// Supabase data service for the customer/end-user application only.
///
/// C-Panel mutations (create/edit/delete debt, collect payment, manage users,
/// subscriptions and platform administration) intentionally do not exist in
/// this service. Server-side RLS/RPC authorization remains the final boundary.
class PBService {
  static bool _initialized = false;
  static Future<void>? _initializing;
  static RecordModel? _currentUser;
  static final Map<String, RealtimeChannel> _channels = {};

  static final _CompatRoot pb = _CompatRoot();

  static SupabaseClient get db => Supabase.instance.client;
  static SupabaseClient get client => Supabase.instance.client;
  static RecordModel? get currentUser => _currentUser;
  static String get businessId =>
      _currentUser?.getStringValue('business_id') ?? '';
  static bool get hasSession => _initialized && db.auth.currentSession != null;

  static Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    final existing = _initializing;
    if (existing != null) return existing;

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
      } catch (error, stackTrace) {
        try {
          Supabase.instance.client;
          _initialized = true;
          completer.complete();
        } catch (_) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _initializing = null;
      }
    }();
    return completer.future;
  }

  static String normalizePhone(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00964')) digits = digits.substring(2);
    if (digits.startsWith('0') && digits.length == 11) {
      digits = '964${digits.substring(1)}';
    } else if (digits.startsWith('7') && digits.length == 10) {
      digits = '964$digits';
    }
    return digits;
  }

  static String phoneIdentity(String phone) {
    final normalized = normalizePhone(phone);
    if (!RegExp(r'^9647\d{9}$').hasMatch(normalized)) {
      throw 'ژمارە مۆبایل دروست نییە';
    }
    return '$normalized@zhirox.app';
  }

  static String _friendly(Object error) {
    final raw = error.toString();
    if (raw.contains('PERMISSION_DENIED')) {
      return 'دەسەڵاتی ئەم کردارەت نییە';
    }
    if (raw.contains('SUBSCRIPTION_INACTIVE')) {
      return 'ماوەی بەشداریت تەواو بووە';
    }
    if (raw.contains('PHONE_ALREADY_EXISTS') ||
        raw.toLowerCase().contains('already registered')) {
      return 'ئەم ژمارە مۆبایلە پێشتر بەکارهاتووە';
    }
    if (raw.contains('ACCOUNT_NOT_LINKED') || raw.contains('not approved')) {
      return AppStrings.notApproved;
    }
    return raw.replaceFirst('Exception: ', '');
  }

  static void _requireCustomer() {
    final current = _currentUser;
    if (current == null || !hasSession) {
      throw 'پێویستە دووبارە بچیتە ژوورەوە';
    }
    if (current.getStringValue('role') != 'customer') {
      throw 'ئەم هەژمارە بۆ ئەپی بەکارهێنەر نییە';
    }
  }

  static Future<String> _deviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    var key = prefs.getString('zhirox_device_key');
    if (key != null &&
        RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(key)) {
      return key;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int number) => number.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    key = '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
    await prefs.setString('zhirox_device_key', key);
    return key;
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return 'web';
    }
  }

  static Future<void> _registerDevice() async {
    await db.rpc(
      'register_current_device',
      params: {
        'p_device_key': await _deviceKey(),
        'p_platform': _platformName(),
        'p_app_version': AppConfig.appVersion,
      },
    );
  }

  static RecordModel _fromMap(Map<String, dynamic> map) {
    final data = Map<String, dynamic>.from(map);
    final expand = <String, dynamic>{};

    final customer = data.remove('customer_record');
    final creator = data.remove('creator_record');
    final debt = data.remove('debt_record');
    if (customer is Map) {
      expand['customer'] = [Map<String, dynamic>.from(customer)];
    }
    if (creator is Map) {
      expand['created_by'] = [Map<String, dynamic>.from(creator)];
    }
    if (debt is Map) {
      expand['debt'] = [Map<String, dynamic>.from(debt)];
    }
    if (expand.isNotEmpty) data['expand'] = expand;

    data.putIfAbsent('created', () => data['created_at']?.toString() ?? '');
    data.putIfAbsent(
      'updated',
      () => data['updated_at']?.toString() ?? data['created']?.toString() ?? '',
    );
    return RecordModel.fromJson(data);
  }

  static Future<RecordModel> _context() async {
    final value = await db.rpc('get_my_zhirox_context');
    if (value is! Map) throw 'هەژمارەکە بە سیستەمەوە نەبەستراوەتەوە';
    final record = _fromMap(Map<String, dynamic>.from(value));
    if (record.getStringValue('role') != 'customer') {
      throw 'ئەم هەژمارە بۆ ئەپی بەکارهێنەر نییە';
    }
    _currentUser = record;
    return record;
  }

  static void _validateCustomer(RecordModel user) {
    if (user.getStringValue('role') != 'customer') {
      throw 'ئەم هەژمارە بۆ ئەپی بەکارهێنەر نییە';
    }
    if (!user.getBoolValue('approved')) throw AppStrings.notApproved;
    if (!user.getBoolValue('active')) throw 'ئەم هەژمارە ناچالاکە';
    if (!user.getBoolValue('subscription_active')) {
      throw 'ماوەی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەر.';
    }
  }

  static Future<RecordModel> login(String phone, String password) async {
    await ensureInitialized();
    try {
      final response = await db.auth.signInWithPassword(
        email: phoneIdentity(phone),
        password: password,
      );
      if (response.session == null) throw 'AUTH_FAILED';
      final user = await _context();
      _validateCustomer(user);
      await _registerDevice();
      return user;
    } on AuthException {
      throw 'وشەی نهێنی یان ژمارە مۆبایل هەڵەیە';
    } catch (e) {
      await db.auth.signOut();
      _currentUser = null;
      if (e is String) rethrow;
      throw _friendly(e);
    }
  }

  static Future<RecordModel?> restoreSession() async {
    await ensureInitialized();
    if (db.auth.currentSession == null) return null;
    try {
      await db.auth.refreshSession();
      final user = await _context();
      _validateCustomer(user);
      await _registerDevice();
      return user;
    } catch (_) {
      await db.auth.signOut();
      _currentUser = null;
      return null;
    }
  }

  static Future<RecordModel> refreshCurrentUser() async {
    await ensureInitialized();
    _requireCustomer();
    final user = await _context();
    _validateCustomer(user);
    return user;
  }

  static Future<void> logout() async {
    if (!_initialized) return;
    await unsubscribeAll();
    await db.auth.signOut();
    _currentUser = null;
  }

  static Future<RecordModel> registerCustomer({
    required String name,
    String fatherName = '',
    String grandfatherName = '',
    required String phone,
    required String password,
    required String adminId,
  }) async {
    await ensureInitialized();
    final response = await db.functions.invoke(
      'zhirox-register-customer',
      body: {
        'name': name.trim(),
        'fatherName': fatherName.trim(),
        'grandfatherName': grandfatherName.trim(),
        'phone': normalizePhone(phone),
        'password': password,
        'adminId': adminId,
      },
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw _friendly(data['error']!);
    return _fromMap(Map<String, dynamic>.from(data['user'] as Map));
  }

  static Future<List<RecordModel>> getAdminList() async {
    await ensureInitialized();
    final value = await db.rpc('list_public_markets');
    return ((value as List?) ?? const []).map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      return _fromMap({
        'id': map['id'].toString(),
        'name': map['admin_name'] ?? '',
        'market_name': map['market_name'] ?? '',
        'role': 'admin',
        'approved': true,
        'active': true,
      });
    }).toList();
  }

  /// Customer profile updates are intentionally allow-listed.
  static Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await ensureInitialized();
    _requireCustomer();
    if (id != db.auth.currentUser?.id) throw 'دەسەڵاتی ئەم کردارەت نییە';
    final unexpected = data.keys.where((key) => key != 'name').toList();
    if (unexpected.isNotEmpty) throw 'دەسەڵاتی گۆڕینی ئەم زانیارییەت نییە';

    final name = data['name']?.toString().trim() ?? '';
    if (name.length < 2) throw 'ناوێکی دروست بنووسە';
    final response = await db.functions.invoke(
      'zhirox-update-account',
      body: {
        'userId': id,
        'data': {'name': name},
      },
    );
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['error'] != null) throw _friendly(result['error']!);
    await refreshCurrentUser();
  }

  static Future<void> changePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    await ensureInitialized();
    _requireCustomer();
    if (userId != db.auth.currentUser?.id) throw 'دەسەڵاتی ئەم کردارەت نییە';
    if (newPassword.length < 8) throw 'وشەی نهێنی نوێ لانیکەم ٨ پیت بێت';
    final email = db.auth.currentUser?.email;
    if (email == null || email.isEmpty) throw 'هەژمار نەدۆزرایەوە';

    await db.auth.signInWithPassword(email: email, password: oldPassword);
    await db.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Customers may read only themselves and their linked market/admin summary.
  static Future<RecordModel> getUser(String id) async {
    await ensureInitialized();
    _requireCustomer();
    final me = _currentUser!;
    final adminId = me.getStringValue('admin_id');
    if (id != me.id && id != adminId) throw 'دەسەڵاتی بینینی ئەم زانیارییەت نییە';

    final value = await db.rpc(
      'zhirox_get_user',
      params: {'p_target_user_id': id},
    );
    return _fromMap(Map<String, dynamic>.from(value as Map));
  }

  static void _requireOwnCustomerId(String? customerId) {
    _requireCustomer();
    if (customerId != null &&
        customerId.isNotEmpty &&
        customerId != _currentUser!.id) {
      throw 'دەسەڵاتی بینینی قەرزی ئەم کڕیارەت نییە';
    }
  }

  static Future<List<RecordModel>> getDebts({
    String? customerId,
    String? status,
    String? createdBy,
    String? adminId,
    String? filter,
    int? perPage,
  }) async {
    await ensureInitialized();
    _requireOwnCustomerId(customerId);
    if (createdBy != null || adminId != null) {
      throw 'دەسەڵاتی ئەم گەڕانەت نییە';
    }

    final all = <RecordModel>[];
    var offset = 0;
    final batchSize = (perPage ?? 500).clamp(1, 500);
    while (true) {
      final value = await db.rpc(
        'zhirox_list_debts',
        params: {
          'p_business_id': businessId,
          'p_customer_user_id': _currentUser!.id,
          'p_status': status,
          'p_created_by': null,
          'p_debt_id': null,
          'p_limit': batchSize,
          'p_offset': offset,
        },
      );
      final map = Map<String, dynamic>.from(value as Map);
      final batch = ((map['items'] as List?) ?? const [])
          .map((e) => _fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      all.addAll(batch);
      offset += batch.length;
      final total = (map['totalItems'] as num? ?? 0).toInt();
      if (batch.isEmpty || offset >= total || perPage != null) break;
    }
    return all;
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
    await ensureInitialized();
    _requireOwnCustomerId(customerId);
    if (createdBy != null || adminId != null) {
      throw 'دەسەڵاتی ئەم گەڕانەت نییە';
    }
    final safePage = page < 1 ? 1 : page;
    final safePerPage = perPage.clamp(1, 100);
    final value = await db.rpc(
      'zhirox_list_debts',
      params: {
        'p_business_id': businessId,
        'p_customer_user_id': _currentUser!.id,
        'p_status': status,
        'p_created_by': null,
        'p_debt_id': null,
        'p_limit': safePerPage,
        'p_offset': (safePage - 1) * safePerPage,
      },
    );
    final map = Map<String, dynamic>.from(value as Map);
    final items = ((map['items'] as List?) ?? const [])
        .map((e) => _fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    final total = (map['totalItems'] as num? ?? 0).toInt();
    return {
      'items': items,
      'totalItems': total,
      'totalPages': (total / safePerPage).ceil(),
    };
  }

  static Future<RecordModel> getDebt(String id) async {
    await ensureInitialized();
    _requireCustomer();
    final value = await db.rpc(
      'zhirox_list_debts',
      params: {
        'p_business_id': businessId,
        'p_customer_user_id': _currentUser!.id,
        'p_status': null,
        'p_created_by': null,
        'p_debt_id': id,
        'p_limit': 1,
        'p_offset': 0,
      },
    );
    final items = (Map<String, dynamic>.from(value as Map)['items'] as List?) ??
        const [];
    if (items.isEmpty) throw 'قەرز نەدۆزرایەوە';
    final debt = _fromMap(Map<String, dynamic>.from(items.first as Map));
    if (debt.getStringValue('customer') != _currentUser!.id) {
      throw 'دەسەڵاتی بینینی ئەم قەرزەت نییە';
    }
    return debt;
  }

  static Future<List<RecordModel>> getPayments({
    String? debtId,
    String? createdBy,
    String? customerId,
  }) async {
    await ensureInitialized();
    _requireCustomer();
    if (createdBy != null) throw 'دەسەڵاتی ئەم گەڕانەت نییە';
    if (customerId != null && customerId != _currentUser!.id) {
      throw 'دەسەڵاتی ئەم گەڕانەت نییە';
    }
    if (debtId == null || debtId.isEmpty) {
      throw 'ناسنامەی قەرز پێویستە';
    }

    await getDebt(debtId);
    final all = <RecordModel>[];
    var offset = 0;
    while (true) {
      final value = await db.rpc(
        'zhirox_list_payments',
        params: {
          'p_business_id': businessId,
          'p_debt_id': debtId,
          'p_created_by': null,
          'p_limit': 200,
          'p_offset': offset,
        },
      );
      final map = Map<String, dynamic>.from(value as Map);
      final batch = ((map['items'] as List?) ?? const [])
          .map((e) => _fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
      all.addAll(batch);
      offset += batch.length;
      final total = (map['totalItems'] as num? ?? 0).toInt();
      if (batch.isEmpty || offset >= total) break;
    }
    return all;
  }

  static Future<List<RecordModel>> getNotifications(String customerId) async {
    await ensureInitialized();
    _requireCustomer();
    final uid = db.auth.currentUser?.id;
    if (uid == null || customerId != uid) throw 'دەسەڵاتی ئەم کردارەت نییە';

    final rows = await db
        .from('notifications')
        .select(
          'id,business_id,user_id,type,title,body,entity_type,entity_id,'
          'read_at,created_at,sender_user_id',
        )
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      return _fromMap({
        'id': map['id'],
        'customer': map['user_id'],
        'message': map['body'] ?? '',
        'type': map['type'] ?? 'general',
        'debt': map['entity_type'] == 'DEBT' ? map['entity_id'] : null,
        'sender': map['sender_user_id'],
        'is_read': map['read_at'] != null,
        'created': map['created_at']?.toString() ?? '',
        'updated': map['created_at']?.toString() ?? '',
      });
    }).toList();
  }

  static Future<int> getUnreadNotificationCount(String customerId) async {
    final rows = await getNotifications(customerId);
    return rows.where((row) => !row.getBoolValue('is_read')).length;
  }

  static Future<void> markNotificationRead(String id) async {
    await ensureInitialized();
    _requireCustomer();
    final uid = db.auth.currentUser?.id;
    if (uid == null) throw 'پێویستە دووبارە بچیتە ژوورەوە';
    await db
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .eq('user_id', uid);
  }

  static Future<void> deleteNotification(String id) async {
    await ensureInitialized();
    _requireCustomer();
    final uid = db.auth.currentUser?.id;
    if (uid == null) throw 'پێویستە دووبارە بچیتە ژوورەوە';
    await db.from('notifications').delete().eq('id', id).eq('user_id', uid);
  }

  static Future<String> getReceiptUrl(RecordModel debt) async {
    await ensureInitialized();
    await getDebt(debt.id);
    final path = debt.getStringValue('receipt_image');
    if (path.isEmpty) return '';
    return db.storage.from('zhirox-receipts').createSignedUrl(path, 3600);
  }

  static Future<void> subscribeTable(
    String key,
    String table,
    VoidCallback callback, {
    String? filterColumn,
    Object? filterValue,
  }) async {
    await ensureInitialized();
    _requireCustomer();
    await unsubscribe(key);
    var channel = db.channel(
      'zhirox:$key:${DateTime.now().microsecondsSinceEpoch}',
    );
    if (filterColumn != null && filterValue != null) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: filterColumn,
          value: filterValue,
        ),
        callback: (_) => callback(),
      );
    } else {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => callback(),
      );
    }
    _channels[key] = channel;
    channel.subscribe();
  }

  static Future<void> subscribeCurrentUser(VoidCallback callback) async {
    _requireCustomer();
    await subscribeTable(
      'current-user',
      'customers',
      callback,
      filterColumn: 'auth_user_id',
      filterValue: _currentUser!.id,
    );
    if (businessId.isNotEmpty) {
      await subscribeTable(
        'current-subscription',
        'business_subscriptions',
        callback,
        filterColumn: 'business_id',
        filterValue: businessId,
      );
    }
  }

  static Future<void> unsubscribe(String key) async {
    if (!_initialized) return;
    final channel = _channels.remove(key);
    if (channel != null) await db.removeChannel(channel);
  }

  static Future<void> unsubscribeAll() async {
    if (!_initialized) return;
    await db.removeAllChannels();
    _channels.clear();
  }
}

/// Temporary API shape used by the existing customer UI for realtime only.
/// It intentionally exposes no list/update/delete collection operations.
class _CompatRoot {
  _CompatCollection collection(String name) => _CompatCollection(name);
}

class _CompatCollection {
  _CompatCollection(this.name);

  final String name;

  Future<void> subscribe(
    String topic,
    void Function(PBRealtimeEvent) callback,
  ) async {
    if (name == 'users') {
      await PBService.subscribeCurrentUser(() async {
        try {
          final current = PBService.currentUser;
          if (current == null) return;
          final updated = await PBService.refreshCurrentUser();
          callback(PBRealtimeEvent(record: updated));
        } catch (_) {
          callback(const PBRealtimeEvent());
        }
      });
      return;
    }

    if (name == 'debts') {
      await PBService.subscribeTable(
        'compat:debts:$topic',
        'debts',
        () => callback(const PBRealtimeEvent(action: 'update')),
        filterColumn: 'customer_user_id',
        filterValue: PBService.currentUser?.id,
      );
      return;
    }

    if (name == 'notifications') {
      await PBService.subscribeTable(
        'compat:notifications:$topic',
        'notifications',
        () => callback(const PBRealtimeEvent(action: 'update')),
        filterColumn: 'user_id',
        filterValue: PBService.currentUser?.id,
      );
      return;
    }

    throw 'Unsupported customer realtime collection: $name';
  }

  Future<void> unsubscribe([String? topic]) async {
    if (name == 'users') {
      await PBService.unsubscribe('current-user');
      await PBService.unsubscribe('current-subscription');
      return;
    }
    if (name == 'debts') {
      await PBService.unsubscribe('compat:debts:${topic ?? '*'}');
      return;
    }
    if (name == 'notifications') {
      await PBService.unsubscribe('compat:notifications:${topic ?? '*'}');
    }
  }
}
