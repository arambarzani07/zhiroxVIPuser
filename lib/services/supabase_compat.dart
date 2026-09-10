import 'dart:async';
import 'dart:convert';

import 'package:pocketbase/pocketbase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// supabase_flutter 2.17.x exposes FunctionException (singular). Keeping this
// alias lets the migrated service retain its compatibility-oriented naming.
typedef FunctionsException = FunctionException;

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
  const _RelationContext({
    this.profiles = const {},
    this.debts = const {},
  });

  final Map<String, Map<String, dynamic>> profiles;
  final Map<String, Map<String, dynamic>> debts;
}

/// Keeps the old PocketBase-shaped UI contract while Supabase handles all I/O.
class SupabasePBCompat {
  SupabasePBCompat({required this.ensureInitialized});

  final Future<void> Function() ensureInitialized;
  final Map<String, RealtimeChannel> _channels = {};

  SupabaseClient get _client => Supabase.instance.client;

  SupabaseCollectionCompat collection(String name) =>
      SupabaseCollectionCompat(this, name);

  Uri getFileUrl(RecordModel record, String filename) {
    if (filename.startsWith('http://') || filename.startsWith('https://')) {
      return Uri.parse(filename);
    }
    return Uri.parse(_client.storage.from('receipts').getPublicUrl(filename));
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
            unawaited(Future<void>(() async {
              final raw = payload.newRecord.isNotEmpty
                  ? Map<String, dynamic>.from(payload.newRecord)
                  : Map<String, dynamic>.from(payload.oldRecord);
              final id = raw['id']?.toString() ?? '';
              if (topic != '*' && id != topic) return;

              RecordModel? record;
              if (id.isNotEmpty &&
                  payload.eventType != PostgresChangeEvent.delete) {
                try {
                  record = await collection(logicalName).getOne(id);
                } catch (_) {
                  record = _recordFromRaw(
                    logicalName,
                    raw,
                    const _RelationContext(),
                  );
                }
              } else if (raw.isNotEmpty) {
                record = _recordFromRaw(
                  logicalName,
                  raw,
                  const _RelationContext(),
                );
              }

              callback(
                PBRealtimeEvent(
                  record: record,
                  action: payload.eventType.name,
                ),
              );
            }));
          },
        )
        .subscribe();

    _channels[key] = channel;
  }

  Future<void> unsubscribe(String logicalName, [String? topic]) async {
    await ensureInitialized();
    final prefix = '$logicalName:';
    final keys = _channels.keys.where((key) {
      return topic == null
          ? key.startsWith(prefix)
          : key == '$logicalName:$topic';
    }).toList();

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
    if (logicalName == 'users') return const _RelationContext();

    // Relation data is part of the live record contract. Never downgrade a
    // failed profiles/debts request to an empty relation context, because that
    // makes a network/database failure look like legitimately missing data.
    final profileData = await _client.from('profiles').select();
    final profiles = (profileData as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    List<Map<String, dynamic>> debts = const [];
    if (logicalName == 'payments') {
      final debtData = await _client.from('debts').select();
      debts = (debtData as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }

    return _RelationContext(
      profiles: {for (final row in profiles) row['id'].toString(): row},
      debts: {for (final row in debts) row['id'].toString(): row},
    );
  }

  Map<String, dynamic> _writeMap(
    String logicalName,
    Map<String, dynamic> body,
  ) {
    final result = Map<String, dynamic>.from(body);

    for (final key in const [
      'password',
      'passwordConfirm',
      'password_text',
      'oldPassword',
      'email',
      'telegram_bot_token',
      'created',
      'updated',
    ]) {
      result.remove(key);
    }

    if (logicalName == 'debts') {
    // Optional PostgreSQL date/timestamp columns must receive NULL,
    // never an empty string (which raises Postgres error 22007).
    for (final key in const ['due_date', 'custom_date']) {
      final value = result[key];
      if (value is String && value.trim().isEmpty) {
        result[key] = null;
      }
    }
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

    return result;
  }

  Map<String, dynamic> _recordJson(
    String logicalName,
    Map<String, dynamic> raw,
    _RelationContext ctx,
  ) {
    final created = raw['created_at']?.toString() ?? '';
    final updated = raw['updated_at']?.toString() ?? created;
    final out = <String, dynamic>{
      'id': raw['id']?.toString() ?? '',
      'collectionId': '',
      'collectionName': logicalName,
      'created': created,
      'updated': updated,
    };

    if (logicalName == 'users') {
      out.addAll(raw);
      final phone = raw['phone']?.toString() ?? '';
      out['email'] = phone.isEmpty ? '' : '$phone@zhirox.local';
      return out;
    }

    if (logicalName == 'debts') {
      out.addAll(raw);
      out['customer'] = raw['customer_id']?.toString() ?? '';
      out['items'] = jsonEncode(raw['items'] ?? const []);
      out['receipt_image'] = raw['receipt_image_path']?.toString() ?? '';
      out.remove('customer_id');
      out.remove('receipt_image_path');

      final expand = <String, dynamic>{};
      final customer = ctx.profiles[raw['customer_id']?.toString() ?? ''];
      final creator = ctx.profiles[raw['created_by']?.toString() ?? ''];
      if (customer != null) {
        expand['customer'] = _recordJson('users', customer, ctx);
      }
      if (creator != null) {
        expand['created_by'] = _recordJson('users', creator, ctx);
      }
      if (expand.isNotEmpty) out['expand'] = expand;
      return out;
    }

    if (logicalName == 'payments') {
      out.addAll(raw);
      out['debt'] = raw['debt_id']?.toString() ?? '';
      out.remove('debt_id');

      final expand = <String, dynamic>{};
      final debt = ctx.debts[raw['debt_id']?.toString() ?? ''];
      final creator = ctx.profiles[raw['created_by']?.toString() ?? ''];
      if (debt != null) {
        expand['debt'] = _recordJson('debts', debt, ctx);
      }
      if (creator != null) {
        expand['created_by'] = _recordJson('users', creator, ctx);
      }
      if (expand.isNotEmpty) out['expand'] = expand;
      return out;
    }

    if (logicalName == 'notifications') {
      out.addAll(raw);
      out['customer'] = raw['customer_id']?.toString() ?? '';
      out['sender'] = raw['sender_id']?.toString() ?? '';
      out.remove('customer_id');
      out.remove('sender_id');

      final expand = <String, dynamic>{};
      final customer = ctx.profiles[raw['customer_id']?.toString() ?? ''];
      final sender = ctx.profiles[raw['sender_id']?.toString() ?? ''];
      if (customer != null) {
        expand['customer'] = _recordJson('users', customer, ctx);
      }
      if (sender != null) {
        expand['sender'] = _recordJson('users', sender, ctx);
      }
      if (expand.isNotEmpty) out['expand'] = expand;
      return out;
    }

    return out;
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
        final profile = ctx.profiles[raw['customer_id']?.toString() ?? ''];
        return profile?[path.substring('customer.'.length)];
      }
    }

    if (logicalName == 'payments') {
      if (path == 'debt') return raw['debt_id'];
      if (path.startsWith('debt.customer')) {
        final debt = ctx.debts[raw['debt_id']?.toString() ?? ''];
        if (path == 'debt.customer') return debt?['customer_id'];
        if (path == 'debt.customer.admin_id') {
          final profile =
              ctx.profiles[debt?['customer_id']?.toString() ?? ''];
          return profile?['admin_id'];
        }
      }
    }

    if (logicalName == 'notifications') {
      if (path == 'customer') return raw['customer_id'];
      if (path == 'sender') return raw['sender_id'];
    }

    return raw[path];
  }

  List<String> _splitTopLevel(String input, String separator) {
    final parts = <String>[];
    var start = 0;
    var depth = 0;
    var quoted = false;

    for (var i = 0; i <= input.length - separator.length; i++) {
      final ch = input[i];
      if (ch == '"' && (i == 0 || input[i - 1] != '\\')) quoted = !quoted;
      if (!quoted) {
        if (ch == '(') depth++;
        if (ch == ')') depth--;
        if (depth == 0 &&
            input.substring(i, i + separator.length) == separator) {
          parts.add(input.substring(start, i).trim());
          start = i + separator.length;
          i += separator.length - 1;
        }
      }
    }

    if (parts.isEmpty) return [input.trim()];
    parts.add(input.substring(start).trim());
    return parts;
  }

  String _trimOuterParens(String input) {
    var value = input.trim();
    while (value.startsWith('(') && value.endsWith(')')) {
      var depth = 0;
      var valid = true;
      for (var i = 0; i < value.length; i++) {
        if (value[i] == '(') depth++;
        if (value[i] == ')') depth--;
        if (depth == 0 && i < value.length - 1) {
          valid = false;
          break;
        }
      }
      if (!valid) break;
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  dynamic _literal(String input) {
    var value = input.trim();
    if (value.startsWith('"') &&
        value.endsWith('"') &&
        value.length >= 2) {
      value = value
          .substring(1, value.length - 1)
          .replaceAll('\\"', '"')
          .replaceAll('\\\\', '\\');
      return value;
    }
    if (value == 'true') return true;
    if (value == 'false') return false;
    return num.tryParse(value) ?? value;
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
    final expr = _trimOuterParens(expression);
    if (expr.isEmpty) return true;

    final orParts = _splitTopLevel(expr, '||');
    if (orParts.length > 1) {
      return orParts.any((part) => _matches(logicalName, raw, part, ctx));
    }

    final andParts = _splitTopLevel(expr, '&&');
    if (andParts.length > 1) {
      return andParts.every((part) => _matches(logicalName, raw, part, ctx));
    }

    final match = RegExp(
      r'^([A-Za-z0-9_.]+)\s*(>=|<=|!=|=|>|<|~)\s*(.+)$',
    ).firstMatch(expr);
    if (match == null) return true;

    final left = _valueForPath(logicalName, raw, match.group(1)!, ctx);
    final op = match.group(2)!;
    final right = _literal(match.group(3)!);

    switch (op) {
      case '=':
        return left is num && right is num
            ? left == right
            : left?.toString() == right?.toString();
      case '!=':
        return left is num && right is num
            ? left != right
            : left?.toString() != right?.toString();
      case '~':
        return (left?.toString() ?? '')
            .toLowerCase()
            .contains(right.toString().toLowerCase());
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
    final context = await _owner._contextFor(logicalName);
    if (logicalName == 'debts') await _signReceipt(raw);
    return _owner._recordFromRaw(logicalName, raw, context);
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
    final context = await _owner._contextFor(logicalName);

    if (filter.trim().isNotEmpty) {
      rows = rows
          .where(
            (row) =>
                _owner._matches(logicalName, row, filter, context),
          )
          .toList();
    }

    if (sort.trim().isNotEmpty) {
      final first = sort.split(',').first.trim();
      final descending = first.startsWith('-');
      final field = descending ? first.substring(1) : first;
      rows.sort((a, b) {
        final aValue = _owner._valueForPath(logicalName, a, field, context);
        final bValue = _owner._valueForPath(logicalName, b, field, context);
        final comparison = _owner._compare(aValue, bValue);
        return descending ? -comparison : comparison;
      });
    }

    final total = rows.length;
    final safePerPage = perPage <= 0 ? 30 : perPage;
    final safePage = page <= 0 ? 1 : page;
    final start = (safePage - 1) * safePerPage;
    final end = (start + safePerPage).clamp(0, total).toInt();
    final pageRows = start >= total
        ? <Map<String, dynamic>>[]
        : rows.sublist(start, end);

    if (logicalName == 'debts') {
      for (final row in pageRows) {
        await _signReceipt(row);
      }
    }

    final items = pageRows
        .map((row) => _owner._recordFromRaw(logicalName, row, context))
        .toList();

    return PBListResult(
      items: items,
      totalItems: total,
      totalPages: total == 0 ? 0 : (total / safePerPage).ceil(),
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
    return _owner._recordFromRaw(
      logicalName,
      Map<String, dynamic>.from(data),
      await _owner._contextFor(logicalName),
    );
  }

  Future<RecordModel> update(
    String id, {
    required Map<String, dynamic> body,
  }) async {
    await _owner.ensureInitialized();
    final mapped = _owner._writeMap(logicalName, body);
    final data =
        await _client.from(_table).update(mapped).eq('id', id).select().single();
    return _owner._recordFromRaw(
      logicalName,
      Map<String, dynamic>.from(data),
      await _owner._contextFor(logicalName),
    );
  }

  Future<void> delete(String id) async {
    await _owner.ensureInitialized();
    await _client.from(_table).delete().eq('id', id);
  }

  Future<void> subscribe(
    String topic,
    void Function(PBRealtimeEvent) callback,
  ) {
    return _owner.subscribe(logicalName, topic, callback);
  }

  Future<void> unsubscribe([String? topic]) {
    return _owner.unsubscribe(logicalName, topic);
  }

  Future<void> _signReceipt(Map<String, dynamic> raw) async {
    final path = raw['receipt_image_path']?.toString() ?? '';
    if (path.isEmpty ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return;
    }
    try {
      raw['receipt_image_path'] =
          await _client.storage.from('receipts').createSignedUrl(path, 3600);
    } catch (_) {}
  }
}
