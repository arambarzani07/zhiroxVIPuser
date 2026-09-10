import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/utils/constants.dart';

class PBListResult {
  PBListResult({required this.items, required this.totalItems, required this.totalPages, required this.page, required this.perPage});
  final List<RecordModel> items;
  final int totalItems;
  final int totalPages;
  final int page;
  final int perPage;
}

class PBRealtimeEvent {
  PBRealtimeEvent({this.record, this.action = 'update'});
  final RecordModel? record;
  final String action;
}

class PBService {
  static bool _initialized = false;
  static Future<void>? _initializing;
  static RecordModel? _currentUser;
  static final Map<String, RealtimeChannel> _channels = {};
  static final _CompatRoot pb = _CompatRoot();

  static SupabaseClient get db => Supabase.instance.client;
  static SupabaseClient get client => Supabase.instance.client;
  static RecordModel? get currentUser => _currentUser;
  static String get businessId => _currentUser?.getStringValue('business_id') ?? '';
  static bool get hasSession => _initialized && db.auth.currentSession != null;

  static Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    final existing = _initializing;
    if (existing != null) return existing;
    final completer = Completer<void>();
    _initializing = completer.future;
    () async {
      try {
        await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
        _initialized = true;
        completer.complete();
      } catch (e, st) {
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
    if (!RegExp(r'^9647\d{9}$').hasMatch(normalized)) throw Exception('ژمارە مۆبایل دروست نییە');
    return '$normalized@zhirox.app';
  }

  static String _friendly(Object error) {
    final raw = error.toString();
    if (raw.contains('PERMISSION_DENIED')) return 'دەسەڵاتی ئەم کردارەت نییە';
    if (raw.contains('SUBSCRIPTION_INACTIVE')) return 'ماوەی بەشداریت تەواو بووە';
    if (raw.contains('CUSTOMER_HAS_BALANCE')) return 'کڕیار هێشتا قەرزی ماوەی هەیە';
    if (raw.contains('CREDIT_LIMIT')) return 'سنوری قەرز ڕێگە بەو بڕە نادات';
    if (raw.contains('PAYMENT_EXCEEDS')) return 'بڕی پارەدانەوە زیاترە لە قەرزی ماوە';
    if (raw.contains('DEPENDENT_PAYMENTS_EXIST')) return 'قەرزەکە پارەدانەوەی پەیوەست پێوەیە';
    if (raw.contains('PHONE_ALREADY_EXISTS') || raw.toLowerCase().contains('already registered')) return 'ئەم ژمارە مۆبایلە پێشتر بەکارهاتووە';
    if (raw.contains('MARKET_ALREADY_EXISTS')) return 'ئەم ناوەی مارکێتە پێشتر بەکارهاتووە';
    if (raw.contains('ACCOUNT_NOT_LINKED') || raw.contains('not approved')) return AppStrings.notApproved;
    return raw.replaceFirst('Exception: ', '');
  }

  static void _requireRole(Set<String> roles) {
    if (_currentUser == null || !hasSession) throw Exception('پێویستە دووبارە بچیتە ژوورەوە');
    if (!roles.contains(_currentUser!.getStringValue('role'))) throw Exception('دەسەڵاتی ئەم کردارەت نییە');
  }

  static Future<String> _deviceKey() async {
    final prefs = await SharedPreferences.getInstance();
    var key = prefs.getString('zhirox_device_key');
    if (key != null && RegExp(r'^[0-9a-f-]{36}$', caseSensitive: false).hasMatch(key)) return key;
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int n) => n.toRadixString(16).padLeft(2, '0');
    final s = b.map(h).join();
    key = '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
    await prefs.setString('zhirox_device_key', key);
    return key;
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return 'android';
      case TargetPlatform.iOS: return 'ios';
      case TargetPlatform.windows: return 'windows';
      case TargetPlatform.macOS: return 'macos';
      case TargetPlatform.linux: return 'linux';
      default: return 'web';
    }
  }

  static Future<void> _registerDevice() async {
    await db.rpc('register_current_device', params: {
      'p_device_key': await _deviceKey(),
      'p_platform': _platformName(),
      'p_app_version': AppConfig.appVersion,
    });
  }

  static RecordModel _fromMap(Map<String, dynamic> map) {
    final data = Map<String, dynamic>.from(map);
    final expand = <String, dynamic>{};
    final customer = data.remove('customer_record');
    final creator = data.remove('creator_record');
    final debt = data.remove('debt_record');
    if (customer is Map) expand['customer'] = [Map<String, dynamic>.from(customer)];
    if (creator is Map) expand['created_by'] = [Map<String, dynamic>.from(creator)];
    if (debt is Map) expand['debt'] = [Map<String, dynamic>.from(debt)];
    if (expand.isNotEmpty) data['expand'] = expand;
    data.putIfAbsent('created', () => data['created_at']?.toString() ?? '');
    data.putIfAbsent('updated', () => data['updated_at']?.toString() ?? data['created']?.toString() ?? '');
    return RecordModel.fromJson(data);
  }

  static Future<RecordModel> _context() async {
    final value = await db.rpc('get_my_zhirox_context');
    if (value is! Map) throw Exception('ACCOUNT_NOT_LINKED');
    final record = _fromMap(Map<String, dynamic>.from(value));
    _currentUser = record;
    return record;
  }

  static Future<RecordModel> login(String phone, String password) async {
    await ensureInitialized();
    try {
      final response = await db.auth.signInWithPassword(email: phoneIdentity(phone), password: password);
      if (response.session == null) throw Exception('AUTH_FAILED');
      final user = await _context();
      if (user.getStringValue('role') == 'owner') {
        await db.auth.signOut(); _currentUser = null; throw 'ئەم هەژمارە تایبەتە بە C-Panel';
      }
      if (user.getStringValue('role') == 'customer' && !user.getBoolValue('approved')) {
        await db.auth.signOut(); _currentUser = null; throw AppStrings.notApproved;
      }
      if (!user.getBoolValue('active')) {
        await db.auth.signOut(); _currentUser = null; throw 'ئەم هەژمارە ناچالاکە';
      }
      if (!user.getBoolValue('subscription_active')) {
        await db.auth.signOut(); _currentUser = null; throw 'ماوەی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بە بەڕێوەبەر.';
      }
      await _registerDevice();
      return user;
    } on AuthException {
      throw 'وشەی نهێنی یان ژمارە مۆبایل هەڵەیە';
    } catch (e) {
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
      if (user.getStringValue('role') == 'owner') throw Exception('wrong app');
      if (user.getStringValue('role') == 'customer' && !user.getBoolValue('approved')) throw Exception('not approved');
      if (!user.getBoolValue('active') || !user.getBoolValue('subscription_active')) throw Exception('inactive');
      await _registerDevice();
      return user;
    } catch (_) {
      await db.auth.signOut(); _currentUser = null; return null;
    }
  }

  static Future<RecordModel> refreshCurrentUser() async {
    await ensureInitialized();
    if (!hasSession) throw Exception('پێویستە دووبارە بچیتە ژوورەوە');
    return _context();
  }

  static Future<void> logout() async {
    await ensureInitialized();
    await unsubscribeAll();
    await db.auth.signOut();
    _currentUser = null;
  }

  static Future<RecordModel> registerAdmin({required String marketName, required String adminName, required String phone, required String password, required int subscriptionDays}) async {
    await ensureInitialized();
    _requireRole({'owner'});
    final res = await db.functions.invoke('zhirox-create-account', body: {'kind': 'admin', 'marketName': marketName, 'name': adminName, 'phone': normalizePhone(phone), 'password': password, 'subscriptionDays': subscriptionDays});
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw _friendly(data['error']!);
    return _fromMap(Map<String, dynamic>.from(data['user'] as Map));
  }

  static Future<Map<String, dynamic>> getAdminsPage({int page = 1, int perPage = 15}) async {
    await ensureInitialized();
    final value = await db.rpc('zhirox_platform_list_admins', params: {'p_page': page, 'p_per_page': perPage});
    final raw = Map<String, dynamic>.from(value as Map);
    final admins = ((raw['admins'] as List?) ?? const []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return {'admin': _fromMap(Map<String, dynamic>.from(m['admin'] as Map)), 'employeeCount': m['employeeCount'] ?? 0, 'customerCount': m['customerCount'] ?? 0};
    }).toList();
    return {...raw, 'admins': admins};
  }

  static Future<void> renewAdminSubscription(String adminId, int days) async {
    await ensureInitialized();
    await db.rpc('zhirox_platform_renew_admin', params: {'p_admin_user_id': adminId, 'p_days': days});
  }

  static Future<void> deleteAdminWithData(String adminId) async {
    await ensureInitialized();
    final res = await db.functions.invoke('zhirox-delete-admin', body: {'adminId': adminId});
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw _friendly(data['error']!);
  }

  static Future<int> checkSubscriptionDaysLeft(String adminId) async {
    final admin = await getUser(adminId);
    final end = DateTime.tryParse(admin.getStringValue('subscription_end'));
    return end == null ? 9999 : end.difference(DateTime.now()).inDays;
  }

  static Future<RecordModel> registerCustomer({required String name, String fatherName = '', String grandfatherName = '', required String phone, required String password, required String adminId}) async {
    await ensureInitialized();
    final res = await db.functions.invoke('zhirox-register-customer', body: {'name': name, 'fatherName': fatherName, 'grandfatherName': grandfatherName, 'phone': normalizePhone(phone), 'password': password, 'adminId': adminId});
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw _friendly(data['error']!);
    return _fromMap(Map<String, dynamic>.from(data['user'] as Map));
  }

  static Future<List<RecordModel>> getAdminList() async {
    await ensureInitialized();
    final value = await db.rpc('list_public_markets');
    return ((value as List?) ?? const []).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return _fromMap({'id': m['id'].toString(), 'name': m['admin_name'] ?? '', 'market_name': m['market_name'] ?? '', 'role': 'admin', 'approved': true, 'active': true});
    }).toList();
  }

  static Future<List<RecordModel>> getPendingCustomers(String adminId) => getUsers(role: 'customer', approved: false);
  static Future<void> approveCustomer(String id, int debtDuration) => updateUser(id, {'approved': true, 'debt_duration': debtDuration});
  static Future<void> rejectCustomer(String id) => deleteUser(id);

  static Future<RecordModel> createUser({required String name, String fatherName = '', String grandfatherName = '', required String phone, required String password, required String role, required String createdBy, String? adminId, bool canAddCustomers = false, bool canSetDebtLimit = false, bool canSetDueDate = false, bool canEditDebts = false, bool canSendNotifications = false, double debtLimit = 0}) async {
    await ensureInitialized();
    final res = await db.functions.invoke('zhirox-create-account', body: {'kind': role, 'name': name, 'fatherName': fatherName, 'grandfatherName': grandfatherName, 'phone': normalizePhone(phone), 'password': password, 'debtLimit': debtLimit.round(), 'canAddCustomers': canAddCustomers, 'canSetDebtLimit': canSetDebtLimit, 'canSetDueDate': canSetDueDate, 'canEditDebts': canEditDebts, 'canSendNotifications': canSendNotifications});
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['error'] != null) throw _friendly(data['error']!);
    return _fromMap(Map<String, dynamic>.from(data['user'] as Map));
  }

  static Future<void> updateUser(String id, Map<String, dynamic> data) async {
    await ensureInitialized();
    final res = await db.functions.invoke('zhirox-update-account', body: {'userId': id, 'data': Map<String, dynamic>.from(data)});
    final result = Map<String, dynamic>.from(res.data as Map);
    if (result['error'] != null) throw _friendly(result['error']!);
    if (id == db.auth.currentUser?.id) await refreshCurrentUser();
  }

  static Future<void> changePassword({required String userId, required String oldPassword, required String newPassword}) async {
    await ensureInitialized();
    if (userId != db.auth.currentUser?.id) throw Exception('دەسەڵاتی ئەم کردارەت نییە');
    final email = db.auth.currentUser?.email;
    if (email == null) throw Exception('هەژمار نەدۆزرایەوە');
    await db.auth.signInWithPassword(email: email, password: oldPassword);
    await db.auth.updateUser(UserAttributes(password: newPassword));
  }

  static Future<void> deleteUser(String id) async {
    await ensureInitialized();
    final res = await db.functions.invoke('zhirox-delete-account', body: {'userId': id});
    final result = Map<String, dynamic>.from(res.data as Map);
    if (result['error'] != null) throw _friendly(result['error']!);
  }

  static Future<List<RecordModel>> getUsers({String? role, String? search, String? adminId, bool? approved}) async {
    await ensureInitialized();
    final value = await db.rpc('zhirox_list_users', params: {'p_business_id': businessId, 'p_role': role, 'p_approved': approved, 'p_search': search});
    return ((value as List?) ?? const []).map((e) => _fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<RecordModel> getUser(String id) async {
    await ensureInitialized();
    final value = await db.rpc('zhirox_get_user', params: {'p_target_user_id': id});
    return _fromMap(Map<String, dynamic>.from(value as Map));
  }

  static Future<double> getCustomerBalance(String customerId) async {
    final debts = await getDebts(customerId: customerId);
    return debts.fold<double>(0, (s, d) => s + d.getDoubleValue('remaining'));
  }

  static String _uuid() {
    final r = Random.secure();
    String h(int n) => n.toRadixString(16).padLeft(2, '0');
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80;
    final s = b.map(h).join();
    return '${s.substring(0,8)}-${s.substring(8,12)}-${s.substring(12,16)}-${s.substring(16,20)}-${s.substring(20)}';
  }

  static Future<RecordModel> createDebt({required String customerId, required String description, required double amount, required String dueDate, required String createdBy, String currency = 'IQD', double dollarRate = 0, double amountUsd = 0, List<Map<String, dynamic>>? items, String? createdByName, String? marketName, String? customCreatedDate, String? receiptImagePath}) async {
    await ensureInitialized();
    String? receiptPath;
    if (receiptImagePath != null && receiptImagePath.isNotEmpty) {
      final bytes = await XFile(receiptImagePath).readAsBytes();
      final ext = receiptImagePath.split('.').last.toLowerCase();
      receiptPath = '$businessId/$customerId/${_uuid()}.$ext';
      await db.storage.from('zhirox-receipts').uploadBinary(receiptPath, bytes, fileOptions: const FileOptions(upsert: false));
    }
    final id = await db.rpc('zhirox_create_debt', params: {'p_business_id': businessId, 'p_customer_user_id': customerId, 'p_amount': amount.round(), 'p_due_date': dueDate.substring(0, 10), 'p_description': description, 'p_currency': currency, 'p_dollar_rate': dollarRate, 'p_amount_usd': amountUsd, 'p_items': items ?? const [], 'p_custom_date': customCreatedDate == null || customCreatedDate.isEmpty ? null : customCreatedDate.substring(0, 10), 'p_receipt_path': receiptPath, 'p_idempotency_key': _uuid()});
    return getDebt(id.toString());
  }

  static Future<void> updateDebt(String id, Map<String, dynamic> data) async {
    final old = await getDebt(id);
    dynamic rawItems = data['items'];
    if (rawItems is String) { try { rawItems = jsonDecode(rawItems); } catch (_) { rawItems = const []; } }
    final oldDue = old.getStringValue('due_date');
    final due = data['due_date']?.toString() ?? oldDue;
    await db.rpc('zhirox_update_debt', params: {'p_business_id': businessId, 'p_debt_id': id, 'p_description': data['description']?.toString() ?? old.getStringValue('description'), 'p_due_date': due.length >= 10 ? due.substring(0, 10) : due, 'p_currency': data['currency']?.toString() ?? old.getStringValue('currency'), 'p_dollar_rate': (data['dollar_rate'] as num?)?.toDouble() ?? old.getDoubleValue('dollar_rate'), 'p_amount_usd': (data['amount_usd'] as num?)?.toDouble() ?? old.getDoubleValue('amount_usd'), 'p_items': rawItems ?? _decodeItems(old.getStringValue('items'))});
  }

  static List<dynamic> _decodeItems(String value) { try { final x = jsonDecode(value); return x is List ? x : const []; } catch (_) { return const []; } }

  static Future<void> deleteDebt(String id) async {
    await db.rpc('zhirox_reverse_debt', params: {'p_business_id': businessId, 'p_debt_id': id, 'p_reason': 'USER_DELETE'});
  }

  static Future<List<RecordModel>> getDebts({String? customerId, String? status, String? createdBy, String? adminId, String? filter, int? perPage}) async {
    await ensureInitialized();
    final all = <RecordModel>[];
    var offset = 0;
    final batchSize = (perPage ?? 500).clamp(1, 500);
    while (true) {
      final value = await db.rpc('zhirox_list_debts', params: {'p_business_id': businessId, 'p_customer_user_id': customerId, 'p_status': status, 'p_created_by': createdBy, 'p_debt_id': null, 'p_limit': batchSize, 'p_offset': offset});
      final map = Map<String, dynamic>.from(value as Map);
      final batch = ((map['items'] as List?) ?? const []).map((e) => _fromMap(Map<String, dynamic>.from(e as Map))).toList();
      all.addAll(batch); offset += batch.length;
      if (batch.isEmpty || offset >= (map['totalItems'] as num? ?? 0).toInt() || perPage != null) break;
    }
    return all;
  }

  static Future<Map<String, dynamic>> getDebtsPaginated({String? customerId, String? status, String? createdBy, String? adminId, int page = 1, int perPage = 20, String? filter}) async {
    await ensureInitialized();
    final value = await db.rpc('zhirox_list_debts', params: {'p_business_id': businessId, 'p_customer_user_id': customerId, 'p_status': status, 'p_created_by': createdBy, 'p_debt_id': null, 'p_limit': perPage, 'p_offset': (page - 1) * perPage});
    final map = Map<String, dynamic>.from(value as Map);
    final items = ((map['items'] as List?) ?? const []).map((e) => _fromMap(Map<String, dynamic>.from(e as Map))).toList();
    final total = (map['totalItems'] as num? ?? 0).toInt();
    return {'items': items, 'totalItems': total, 'totalPages': (total / perPage).ceil()};
  }

  static Future<RecordModel> getDebt(String id) async {
    await ensureInitialized();
    final value = await db.rpc('zhirox_list_debts', params: {'p_business_id': businessId, 'p_customer_user_id': null, 'p_status': null, 'p_created_by': null, 'p_debt_id': id, 'p_limit': 1, 'p_offset': 0});
    final items = (Map<String, dynamic>.from(value as Map)['items'] as List?) ?? const [];
    if (items.isEmpty) throw Exception('قەرز نەدۆزرایەوە');
    return _fromMap(Map<String, dynamic>.from(items.first as Map));
  }

  static Future<RecordModel> createPayment({required String debtId, required double amount, String? note, required String createdBy, String? createdByName}) async {
    await ensureInitialized();
    if (amount <= 0) throw Exception('بڕی پارەدانەوە دەبێت گەورەتر لە سفر بێت');
    final paymentId = await db.rpc('zhirox_create_payment_for_debt', params: {'p_business_id': businessId, 'p_debt_id': debtId, 'p_amount': amount.round(), 'p_note': note ?? '', 'p_idempotency_key': _uuid()});
    final payments = await getPayments(debtId: debtId);
    return payments.firstWhere((p) => p.id == paymentId.toString(), orElse: () => _fromMap({'id': paymentId.toString(), 'debt': debtId, 'amount': amount, 'note': note ?? '', 'created': DateTime.now().toUtc().toIso8601String()}));
  }

  static Future<List<RecordModel>> getPayments({String? debtId, String? createdBy, String? customerId}) async {
    await ensureInitialized();
    final all = <RecordModel>[];
    var offset = 0;
    while (true) {
      final value = await db.rpc('zhirox_list_payments', params: {'p_business_id': businessId, 'p_debt_id': debtId, 'p_created_by': createdBy, 'p_limit': 500, 'p_offset': offset});
      final map = Map<String, dynamic>.from(value as Map);
      final batch = ((map['items'] as List?) ?? const []).map((e) => _fromMap(Map<String, dynamic>.from(e as Map))).toList();
      all.addAll(batch); offset += batch.length;
      if (batch.isEmpty || offset >= (map['totalItems'] as num? ?? 0).toInt()) break;
    }
    if (customerId == null || customerId.isEmpty) return all;
    return all.where((p) => p.getStringValue('customer') == customerId).toList();
  }

  static Future<Map<String, double>> getEmployeeStats(String employeeId) async {
    final debts = await getDebts(createdBy: employeeId);
    final payments = await getPayments(createdBy: employeeId);
    return {'totalDebtsCreated': debts.fold<double>(0, (s, d) => s + d.getDoubleValue('amount')), 'totalPaymentsCollected': payments.fold<double>(0, (s, p) => s + p.getDoubleValue('amount'))};
  }

  static Future<Map<String, int>> getDebtCounts({required String adminId}) async {
    final debts = await getDebts();
    return {'pending': debts.where((d) => d.getStringValue('status') == 'pending').length, 'partial': debts.where((d) => d.getStringValue('status') == 'partial').length, 'paid': debts.where((d) => d.getStringValue('status') == 'paid').length};
  }

  static Future<Map<String, dynamic>> getDashboardStats({String? adminId}) async {
    await ensureInitialized();
    final value = await db.rpc('zhirox_dashboard_stats', params: {'p_business_id': businessId});
    final map = Map<String, dynamic>.from(value as Map);
    final recent = ((map['recentActivity'] as List?) ?? const []).map((e) => _fromMap(Map<String, dynamic>.from(e as Map))).toList();
    return {...map, 'recentActivity': recent};
  }

  static Future<void> createNotification({required String customerId, required String message, required String senderId, String type = 'general', String? debtId}) async {
    await ensureInitialized();
    await db.rpc('zhirox_create_notification', params: {'p_business_id': businessId, 'p_customer_user_id': customerId, 'p_message': message, 'p_type': type, 'p_debt_id': debtId});
  }

  static Future<bool> testTelegramConnection(String chatId) async => false;
  static Future<bool> sendTelegramMessage(String botToken, String chatId, String message) async => false;

  static Future<List<RecordModel>> getNotifications(String customerId) async {
    await ensureInitialized();
    final uid = db.auth.currentUser?.id;
    if (uid == null) return const [];
    final rows = await db.from('notifications').select('id,business_id,user_id,type,title,body,entity_type,entity_id,read_at,created_at,sender_user_id').eq('user_id', uid).order('created_at', ascending: false).limit(100);
    return (rows as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return _fromMap({'id': m['id'], 'customer': m['user_id'], 'message': m['body'] ?? '', 'type': m['type'] ?? 'general', 'debt': m['entity_type'] == 'DEBT' ? m['entity_id'] : null, 'sender': m['sender_user_id'], 'is_read': m['read_at'] != null, 'created': m['created_at']?.toString() ?? '', 'updated': m['created_at']?.toString() ?? ''});
    }).toList();
  }

  static Future<int> getUnreadNotificationCount(String customerId) async {
    final rows = await getNotifications(customerId);
    return rows.where((r) => !r.getBoolValue('is_read')).length;
  }

  static Future<void> markNotificationRead(String id) async { await db.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id); }
  static Future<void> deleteNotification(String id) async { await db.from('notifications').delete().eq('id', id); }
  static Future<int> checkNewNotifications(String customerId) => getUnreadNotificationCount(customerId);
  static Future<void> checkAndNotifyOverdueDebts() async {}

  static Future<String> getReceiptUrl(RecordModel debt) async {
    final path = debt.getStringValue('receipt_image');
    if (path.isEmpty) return '';
    return db.storage.from('zhirox-receipts').createSignedUrl(path, 3600);
  }

  static Future<void> subscribeTable(String key, String table, VoidCallback callback, {String? filterColumn, Object? filterValue}) async {
    await ensureInitialized();
    await unsubscribe(key);
    var channel = db.channel('zhirox:$key:${DateTime.now().microsecondsSinceEpoch}');
    if (filterColumn != null && filterValue != null) {
      channel = channel.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: table, filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: filterColumn, value: filterValue), callback: (_) => callback());
    } else {
      channel = channel.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: table, callback: (_) => callback());
    }
    _channels[key] = channel;
    channel.subscribe();
  }

  static Future<void> subscribeCurrentUser(VoidCallback callback) async {
    if (_currentUser == null) return;
    final role = _currentUser!.getStringValue('role');
    if (role == 'customer') {
      await subscribeTable('current-user', 'customers', callback, filterColumn: 'auth_user_id', filterValue: _currentUser!.id);
    } else if (role == 'admin' || role == 'employee') {
      await subscribeTable('current-user', 'business_members', callback, filterColumn: 'user_id', filterValue: _currentUser!.id);
    }
    if (businessId.isNotEmpty) await subscribeTable('current-subscription', 'business_subscriptions', callback, filterColumn: 'business_id', filterValue: businessId);
  }

  static Future<void> unsubscribe(String key) async {
    final c = _channels.remove(key);
    if (c != null) await db.removeChannel(c);
  }

  static Future<void> unsubscribeAll() async {
    if (!_initialized) return;
    await db.removeAllChannels();
    _channels.clear();
  }
}

class _CompatRoot {
  _CompatCollection collection(String name) => _CompatCollection(name);
  Uri getFileUrl(RecordModel record, String filename) {
    if (filename.startsWith('http://') || filename.startsWith('https://')) return Uri.parse(filename);
    return Uri.parse('${SupabaseConfig.url}/storage/v1/object/public/zhirox-receipts/$filename');
  }
}

class _CompatCollection {
  _CompatCollection(this.name);
  final String name;

  String? _quoted(String filter, String field) {
    final m = RegExp('${RegExp.escape(field)}\\s*=\\s*"([^"]+)"').firstMatch(filter);
    return m?.group(1);
  }

  bool? _bool(String filter, String field) {
    final m = RegExp('${RegExp.escape(field)}\\s*=\\s*(true|false)', caseSensitive: false).firstMatch(filter);
    if (m == null) return null;
    return m.group(1)!.toLowerCase() == 'true';
  }

  Future<RecordModel> getOne(String id, {String? expand}) async {
    if (name == 'users') return PBService.getUser(id);
    if (name == 'debts') return PBService.getDebt(id);
    if (name == 'notifications') {
      final rows = await PBService.getNotifications(PBService.client.auth.currentUser?.id ?? '');
      return rows.firstWhere((e) => e.id == id);
    }
    throw Exception('Unsupported collection: $name');
  }

  Future<PBListResult> getList({int page = 1, int perPage = 30, String? filter, String? sort, String? expand}) async {
    final f = filter ?? '';
    List<RecordModel> rows;
    if (name == 'users') {
      final role = _quoted(f, 'role');
      final approved = _bool(f, 'approved');
      if (role == 'admin') {
        try {
          final data = await PBService.getAdminsPage(page: 1, perPage: 1000);
          rows = (data['admins'] as List).map((e) => (e as Map)['admin'] as RecordModel).toList();
        } catch (_) { rows = <RecordModel>[]; }
      } else {
        rows = await PBService.getUsers(role: role, approved: approved);
      }
      final phone = _quoted(f, 'phone');
      final id = _quoted(f, 'id');
      final market = _quoted(f, 'market_name');
      if (phone != null) rows = rows.where((r) => r.getStringValue('phone') == phone).toList();
      if (market != null) rows = rows.where((r) => r.getStringValue('market_name') == market).toList();
      if (id != null && f.contains('id !=')) rows = rows.where((r) => r.id != id).toList();
    } else if (name == 'debts') {
      rows = await PBService.getDebts(customerId: _quoted(f, 'customer'), status: _quoted(f, 'status'), createdBy: _quoted(f, 'created_by'));
      final todayMatch = RegExp(r'due_date\s*<=\s*"([0-9-]+)"').firstMatch(f);
      if (todayMatch != null) {
        final day = DateTime.tryParse(todayMatch.group(1)!);
        if (day != null) rows = rows.where((r) { final d = DateTime.tryParse(r.getStringValue('due_date')); return d != null && !d.isAfter(day) && r.getDoubleValue('remaining') > 0 && r.getStringValue('status') != 'paid'; }).toList();
      }
    } else if (name == 'payments') {
      rows = await PBService.getPayments(debtId: _quoted(f, 'debt'), createdBy: _quoted(f, 'created_by'), customerId: _quoted(f, 'customer'));
    } else if (name == 'notifications') {
      rows = await PBService.getNotifications(PBService.client.auth.currentUser?.id ?? '');
    } else {
      rows = <RecordModel>[];
    }
    if (sort == '-created') rows.sort((a, b) => b.created.compareTo(a.created));
    final total = rows.length;
    final start = ((page - 1) * perPage).clamp(0, total);
    final end = (start + perPage).clamp(0, total);
    final items = rows.sublist(start, end);
    return PBListResult(items: items, totalItems: total, totalPages: perPage <= 0 ? 1 : (total / perPage).ceil(), page: page, perPage: perPage);
  }

  Future<RecordModel> update(String id, {required Map<String, dynamic> body}) async {
    if (name == 'users') { await PBService.updateUser(id, body); return PBService.getUser(id); }
    if (name == 'debts') { await PBService.updateDebt(id, body); return PBService.getDebt(id); }
    if (name == 'notifications') { if (body['is_read'] == true) await PBService.markNotificationRead(id); return getOne(id); }
    throw Exception('Unsupported update: $name');
  }

  Future<void> delete(String id) async {
    if (name == 'users') { await PBService.deleteUser(id); return; }
    if (name == 'debts') { await PBService.deleteDebt(id); return; }
    if (name == 'notifications') { await PBService.deleteNotification(id); return; }
  }

  Future<void> subscribe(String topic, void Function(PBRealtimeEvent) callback) async {
    if (name == 'users') {
      await PBService.subscribeCurrentUser(() async {
        try { callback(PBRealtimeEvent(record: await PBService.getUser(topic))); } catch (_) { callback(PBRealtimeEvent()); }
      });
      return;
    }
    await PBService.subscribeTable('compat:$name:$topic', name, () => callback(PBRealtimeEvent(action: 'update')));
  }

  Future<void> unsubscribe([String? topic]) async {
    if (name == 'users') {
      await PBService.unsubscribe('current-user');
      await PBService.unsubscribe('current-subscription');
      return;
    }
    if (topic == null) {
      final keys = PBService._channels.keys.where((k) => k.startsWith('compat:$name:')).toList();
      for (final key in keys) { await PBService.unsubscribe(key); }
    } else {
      await PBService.unsubscribe('compat:$name:$topic');
    }
  }
}
