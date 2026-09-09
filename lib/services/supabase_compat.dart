import 'dart:async';
import 'dart:convert';

import 'package:pocketbase/pocketbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PBListResult {
  PBListResult({
    required this.items,
    required this.totalItems,
    required this.totalPages,
    required this.page,
    required this.perPage,
  });

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

class _RelationContext {
  _RelationContext({
    this.profiles = const {},
    this.debts = const {},
  });

  final Map<String, Map<String, dynamic>> profiles;
  final Map<String, Map<String, dynamic>> debts;
}

/// Compatibility facade that preserves the subset of the old PocketBase API
/// used by the UI while all network traffic is served by Supabase.
class SupabasePBCompat {
  SupabasePBCompat({required this.ensureInitialized});

  final Future<void> Function() ensureInitialized;
  final Map<String, RealtimeChannel> _channels = {};

  SupabaseClient get _client => Supabase.instance.client;

  SupabaseCollectionCompat collection(String name) {
    return SupabaseCollectionCompat(this, name);
  }

  Uri getFileUrl(RecordModel record, String filename) {
    if (filename.startsWith('http://') || filename.startsWith('https://')) {
      return Uri.parse(filename);
    }
    return Uri.parse(
      '${_client.storage.from('receipts').getPublicUrl(filename)}',
    );
  }

  Future<void> subscribe(
    String logicalName,
    String topic,
    void Function(PBRealtimeEvent) callback,
  ) async {
    await ensureInitialized();
    final table = _tableFor(logicalName);
    final key = '$logicalName:$topic';
    await unsubscribe(logicalName, topic);

    final channel = _client
        .channel('zhirox:$key:${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (payload) {
            Future<void>(() async {
              final raw = payload.newRecord.isNotEmpty
                  ? Map<String, dynamic>.from(payload.newRecord)
                  : Map<String, dynamic>.from(payload.oldRecord);
              final id = raw['id']?.toString() ?? '';
              if (topic != '*' && id != topic) return;

              RecordModel? record;
              if (id.isNotEmpty && payload.eventType != PostgresChangeEvent.delete) {
                try {
                  record = await collection(logicalName).getOne(id);
                } catch (_) {
                  record = _recordFromRaw(logicalName, raw, const _RelationContext());
                }
              } else if (raw.isNotEmpty) {
                record = _recordFromRaw(logicalName, raw, const _RelationContext());
              }
              callback(PBRealtimeEvent(record: record, action: payload.eventType.name));
            });
          },
        )
        .subscribe();

    _channels[key] = channel;
  }

  Future<void> unsubscribe(String logicalName, [String? topic]) async {
    await ensureInitialized();
    final prefix = '$logicalName:';
    final keys = _channels.keys
        .where((key) => topic == null ? key.startsWith(prefix) : key == '$logicalName:$topic')
        .toList();
    for (final key in keys) {
      final channel = _channels.remove(key);
      if (channel != null) {
        try {
          await _client.removeChannel(channel);
        } catch (_) {}
      }
    }
  }

  String _tableFor(String logicalName) {
    switch (logicalName) {
      case 'users':
        return 'profiles';
      case 'debts':
      case 'payments':
      case 'notifications':
        return logicalName;
      default:
        throw ArgumentError('Unsupported collection: $logicalName');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRaw(String logicalName) async {
    await ensureInitialized();
    final data = await _client.from(_tableFor(logicalName)).select();
    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<_RelationContext> _contextFor(String logicalName) async {
    if (logicalName == 'users') return _RelationContext();

    List<Map<String, dynamic>> profileRows = const [];
    List<Map<String, dynamic>> debtRows = const [];
    try {
      final data = await _client.from('profiles').select();
      profileRows = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}

    if (logicalName == 'payments') {
      try {
        final data = await _client.from('debts').select();
        debtRows = (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } catch (_) {}
    }

    return _RelationContext(
      profiles: {for (final row in profileRows) row['id'].toString(): row},
      debts: {for (final row in debtRows) row['id'].toString(): row},
    );
  }

  Map<String, dynamic> _writeMap(String logicalName, Map<String, dynamic> body) {
    final result = Map<String, dynamic>.from(body);
    result.remove('password');
    result.remove('passwordConfirm');
    result.remove('password_text');
    result.remove('oldPassword');
    result.remove('email');
    result.remove('telegram_bot_token');

    if (logicalName == 'debts') {
      if (result.containsKey('customer')) {
        result['customer_id'] = result.remove('customer');
      }
      if (result.containsKey('receipt_image')) {
        result['receipt_image_path'] = result.remove('receipt_image');
      }
      if (result['items'] is String) {
        try {
          result['items'] = jsonDecode(result['items'] as String);
        } catch (_) {
          result['items'] = <dynamic>[];
        }
      }
    } else if (logicalName == 'payments') {
      if (result.containsKey('debt')) {
        result['debt_id'] = result.remove('debt');
      }
    } else if (logicalName == 'notifications') {
      if (result.containsKey('customer')) {
        result['customer_id'] = result.remove('customer');
      }
      if (result.containsKey('sender')) {
        result['sender_id'] = result.remove('sender');
      }
    }
    result.remove('created');
    result.remove('updated');
    return result;
  }

  Map<String, dynamic> _recordJson(
    String logicalName,
    Map<String, dynamic> raw,
    _RelationContext ctx,
  ) {
    final created = raw['created_at']?.toString() ?? '';
    final updated = raw['updated_at']?.toString() ?? created;
    final json = <String, dynamic>{
      'id': raw['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': logicalName,
      'created': created,
      'updated': updated,
    };

    if (logicalName == 'users') {
      json.addAll(raw);
      final phone = raw['phone']?.toString() ?? '';
      json['email'] = phone.isEmpty ? '' : '$phone@zhirox.local';
    } else if (logicalName == 'debts') {
      json.addAll(raw);
      json['customer'] = raw['customer_id']?.toString() ?? '';
      json['items'] = jsonEncode(raw['items'] ?? const []);
      json['receipt_image'] = raw['receipt_image_path']?.toString() ?? '';
      json.remove('customer_id');
      json.remove('receipt_image_path');

      final expand = <String, dynamic>{};
      final customer = ctx.profiles[raw['customer_id']?.toString() ?? ''];
      if (customer != null) {
        expand['customer'] = [_recordJson('users', customer, ctx)];
      }
      final creator = ctx.profiles[raw['created_by']?.toString() ?? ''];
      if (creator != null) {
        expand['created_by'] = [_recordJson('users', creator, ctx)];
      }
      if (expand.isNotEmpty) json['expand'] = expand;
    } else if (logicalName == 'payments') {
      json.addAll(raw);
      json['debt'] = raw['debt_id']?.toString() ?? '';
      json.remove('debt_id');

      final expand = <String, dynamic>{};
      final debt = ctx.debts[raw['debt_id']?.toString() ?? ''];
      if (debt != null) {
        expand['debt'] = [_recordJson('debts', debt, ctx)];
      }
      final creator = ctx.profiles[raw['created_by']?.toString() ?? ''];
      if (creator != null) {
        expand['created_by'] = [_recordJson('users', creator, ctx)];
      }
      if (expand.isNotEmpty) json['expand'] = expand;
    } else if (logicalName == 'notifications') {
      json.addAll(raw);
      json['customer'] = raw['customer_id']?.toString() ?? '';
      json['sender'] = raw['sender_id']?.toString() ?? '';
      json.remove('customer_id');
      json.remove('sender_id');

      final expand = <String, dynamic>{};
      final customer = ctx.profiles[raw['customer_id']?.toString() ?? ''];
      if (customer != null) {
        expand['customer'] = [_recordJson('users', customer, ctx)];
      }
      final sender = ctx.profiles[raw['sender_id']?.toString() ?? ''];
      if (sender != null) {
        expand['sender'] = [_recordJson('users', sender, ctx)];
      }
      if (expand.isNotEmpty) json['expand'] = expand;
    }

    return json;
  }

  RecordModel _recordFromRaw(
    String logicalName,
    Map<String, dynamic> raw,
    _RelationContext ctx,
  ) {
    return RecordModel.fromJson(_recordJson(logicalName, raw, ctx));
  }

  dynamic _valueForPath(
    String logicalName,
    Map<String, dynamic> raw,
    String path,
    _RelationContext ctx,
  ) {
    if (path == 'created') return raw['created_at'];
    if (path == 'updated') return raw['updated_at'];

    if (logicalName == 'debts') {
      if (path == 'customer') return raw['customer_id'];
      if (path.startsWith('customer.')) {
        final p = ctx.profiles[raw['customer_id']?.toString() ?? ''];
        return p?[path.substring('customer.'.length)];
      }
    }
    if (logicalName == 'payments') {
      if (path == 'debt') return raw['debt_id'];
      if (path.startsWith('debt.customer')) {
        final debt = ctx.debts[raw['debt_id']?.toString() ?? ''];
        if (path == 'debt.customer') return debt?['customer_id'];
        if (path == 'debt.customer.admin_id') {
          final p = ctx.profiles[debt?['customer_id']?.toString() ?? ''];
          return p?['admin_id'];
        }
      }
    }
    if (logicalName == 'notifications') {
      if (path == 'customer') return raw['customer_id'];
      if (path == 'sender') return raw['sender_id'];
    }
    return raw[path];
  }

  List<String> _splitTopLevel(String value, String separator) {
    final parts = <String>[];
    var start = 0;
    var depth = 0;
    var quote = false;
    for (var i = 0; i <= value.length - separator.length; i++) {
      final ch = value[i];
      if (ch == '"' && (i == 0 || value[i - 1] != '\\')) quote = !quote;
      if (!quote) {
        if (ch == '(') depth++;
        if (ch == ')') depth--;
        if (depth == 0 && value.substring(i, i + separator.length) == separator) {
          parts.add(value.substring(start, i).trim());
          start = i + separator.length;
          i += separator.length - 1;
        }
      }
    }
    if (parts.isEmpty) return [value.trim()];
    parts.add(value.substring(start).trim());
    return parts;
  }

  String _trimOuterParens(String value) {
    var v = value.trim();
    while (v.startsWith('(') && v.endsWith(')')) {
      var depth = 0;
      var balanced = true;
      for (var i = 0; i < v.length; i++) {
        if (v[i] == '(') depth++;
        if (v[i] == ')') depth--;
        if (depth == 0 && i < v.length - 1) {
          balanced = false;
          break;
        }
      }
      if (!balanced) break;
      v = v.substring(1, v.length - 1).trim();
    }
    return v;
  }

  dynamic _parseLiteral(String value) {
    var v = value.trim();
    if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
      v = v.substring(1, v.length - 1).replaceAll('\\"', '"').replaceAll('\\\\', '\\');
      return v;
    }
    if (v == 'true') return true;
    if (v == 'false') return false;
    return num.tryParse(v) ?? v;
  }

  int _compare(dynamic left, dynamic right) {
    if (left is num && right is num) return left.compareTo(right);
    final l = left?.toString() ?? '';
    final r = right?.toString() ?? '';
    final ld = DateTime.tryParse(l.replaceFirst(' ', 'T'));
    final rd = DateTime.tryParse(r.replaceFirst(' ', 'T'));
    if (ld != null && rd != null) return ld.compareTo(rd);
    return l.compareTo(r);
  }

  bool _matches(
    String logicalName,
    Map<String, dynamic> raw,
    String expression,
    _RelationContext ctx,
  ) {
    var expr = _trimOuterParens(expression);
    if (expr.isEmpty) return true;

    final orParts = _splitTopLevel(expr, '||');
    if (orParts.length > 1) {
      return orParts.any((part) => _matches(logicalName, raw, part, ctx));
    }
    final andParts = _splitTopLevel(expr, '&&');
    if (andParts.length > 1) {
      return andParts.every((part) => _matches(logicalName, raw, part, ctx));
    }

    final match = RegExp(r'^([A-Za-z0-9_.]+)\s*(>=|<=|!=|=|>|<|~)\s*(.+)$').firstMatch(expr);
    if (match == null) return true;
    final field = match.group(1)!;
    final op = match.group(2)!;
    final right = _parseLiteral(match.group(3)!);
    final left = _valueForPath(logicalName, raw, field, ctx);

    switch (op) {
      case '=':
        if (left is num && right is num) return left == right;
        return left?.toString() == right?.toString();
      case '!=':
        if (left is num && right is num) return left != right;
        return left?.toString() != right?.toString();
      case '~':
        return (left?.toString() ?? '').toLowerCase().contains(right.toString().toLowerCase());
      case '>':
        return _compare(left, right) > 0;
      case '<':
        return _compare(left, right) < 0;
      case '>=':
        return _compare(left, right) >= 0;
      case '<=':
        return _compare(left, right) <= 0;
    }
    return true;
  }
}

class SupabaseCollectionCompat {
  SupabaseCollectionCompat(this._owner, this.logicalName);

  final SupabasePBCompat _owner;
  final String logicalName;

  SupabaseClient get _client => Supabase.instance.client;
  String get _table => _owner._tableFor(logicalName);

  Future<RecordModel> getOne(String id, {String? expand}) async {
    await _owner.ensureInitialized();
    final data = await _client.from(_table).select().eq('id', id).single();
    final raw = Map<String, dynamic>.from(data);
    final ctx = await _owner._contextFor(logicalName);
    if (logicalName == 'debts') {
      await _signReceipt(raw);
    }
    return _owner._recordFromRaw(logicalName, raw, ctx);
  }

  Future<PBListResult> getList({
    int page = 1,
    int perPage = 30,
    String filter = '',
    String sort = '',
    String? expand,
  }) async {
    await _owner.ensureInitialized();
    var rows = await _owner._fetchRaw(logicalName);
    final ctx = await _owner._contextFor(logicalName);

    if (filter.trim().isNotEmpty) {
      rows = rows
          .where((row) => _owner._matches(logicalName, row, filter, ctx))
          .toList();
    }

    if (sort.trim().isNotEmpty) {
      final first = sort.split(',').first.trim();
      final desc = first.startsWith('-');
      final field = desc ? first.substring(1) : first;
      rows.sort((a, b) {
        final av = _owner._valueForPath(logicalName, a, field, ctx);
        final bv = _owner._valueForPath(logicalName, b, field, ctx);
        final cmp = _owner._compare(av, bv);
        return desc ? -cmp : cmp;
      });
    }

    final total = rows.length;
    final safePerPage = perPage <= 0 ? 30 : perPage;
    final safePage = page <= 0 ? 1 : page;
    final start = (safePage - 1) * safePerPage;
    final end = (start + safePerPage).clamp(0, total);
    final pageRows = start >= total ? <Map<String, dynamic>>[] : rows.sublist(start, end);

    if (logicalName == 'debts') {
      for (final row in pageRows) {
        await _signReceipt(row);
      }
    }

    final items = pageRows
        .map((row) => _owner._recordFromRaw(logicalName, row, ctx))
        .toList();
    final totalPages = total == 0 ? 0 : (total / safePerPage).ceil();
    return PBListResult(
      items: items,
      totalItems: total,
      totalPages: totalPages,
      page: safePage,
      perPage: safePerPage,
    );
  }

  Future<List<RecordModel>> getFullList({
    String filter = '',
    String sort = '',
    String? expand,
  }) async {
    final result = await getList(
      page: 1,
      perPage: 10000,
      filter: filter,
      sort: sort,
      expand: expand,
    );
    return result.items;
  }

  Future<RecordModel> create({
    required Map<String, dynamic> body,
    List<dynamic>? files,
  }) async {
    await _owner.ensureInitialized();
    final mapped = _owner._writeMap(logicalName, body);
    final data = await _client.from(_table).insert(mapped).select().single();
    final raw = Map<String, dynamic>.from(data);
    final ctx = await _owner._contextFor(logicalName);
    return _owner._recordFromRaw(logicalName, raw, ctx);
  }

  Future<RecordModel> update(String id, {required Map<String, dynamic> body}) async {
    await _owner.ensureInitialized();
    final mapped = _owner._writeMap(logicalName, body);
    final data = await _client.from(_table).update(mapped).eq('id', id).select().single();
    final raw = Map<String, dynamic>.from(data);
    final ctx = await _owner._contextFor(logicalName);
    return _owner._recordFromRaw(logicalName, raw, ctx);
  }

  Future<void> delete(String id) async {
    await _owner.ensureInitialized();
    await _client.from(_table).delete().eq('id', id);
  }

  Future<void> subscribe(String topic, void Function(PBRealtimeEvent) callback) {
    return _owner.subscribe(logicalName, topic, callback);
  }

  Future<void> unsubscribe([String? topic]) {
    return _owner.unsubscribe(logicalName, topic);
  }

  Future<void> _signReceipt(Map<String, dynamic> raw) async {
    final path = raw['receipt_image_path']?.toString() ?? '';
    if (path.isEmpty || path.startsWith('http://') || path.startsWith('https://')) return;
    try {
      raw['receipt_image_path'] = await _client.storage.from('receipts').createSignedUrl(path, 3600);
    } catch (_) {}
  }
}
