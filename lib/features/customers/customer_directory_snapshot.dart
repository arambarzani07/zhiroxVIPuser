import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocketbase/pocketbase.dart';

/// Read-only first-page preview. The live server remains the source of truth.
class CustomerDirectorySnapshot {
  const CustomerDirectorySnapshot({
    required this.users,
    required this.inbox,
    required this.totalItems,
    required this.hasMore,
    required this.nextCursor,
    required this.updatedAt,
  });

  final List<RecordModel> users;
  final Map<String, Map<String, dynamic>> inbox;
  final int totalItems;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
  final DateTime updatedAt;
}

abstract class CustomerDirectorySnapshotStore {
  Future<CustomerDirectorySnapshot?> read(String userId, String tenantId);
  Future<void> write(String userId, String tenantId, CustomerDirectorySnapshot snapshot);
  Future<void> clear(String userId, String tenantId);
}

class SecureCustomerDirectorySnapshotStore implements CustomerDirectorySnapshotStore {
  const SecureCustomerDirectorySnapshotStore();
  static const _storage = FlutterSecureStorage();
  static const _fields = <String>[
    'name', 'father_name', 'grandfather_name', 'phone', 'role',
    'active', 'approved', 'is_pinned', 'is_vip', 'created_at', 'updated_at',
  ];
  static const _inboxFields = <String>[
    'remaining', 'open_debt_count', 'last_activity_at', 'last_kind',
    'last_amount', 'last_preview', 'last_event_type', 'unread',
  ];

  static String _key(String userId, String tenantId) =>
      'zhirox_directory_preview_v1_${sha256.convert(utf8.encode('$userId:$tenantId'))}';

  @override
  Future<CustomerDirectorySnapshot?> read(String userId, String tenantId) async {
    if (userId.isEmpty || tenantId.isEmpty) return null;
    try {
      final raw = await _storage.read(key: _key(userId, tenantId));
      if (raw == null) return null;
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      if (data['version'] != 1 || data['user_id'] != userId || data['tenant_id'] != tenantId) return null;
      final updatedAt = DateTime.tryParse('${data['updated_at'] ?? ''}');
      if (updatedAt == null || DateTime.now().difference(updatedAt).inDays >= 7 || updatedAt.isAfter(DateTime.now().add(const Duration(minutes: 5)))) return null;
      final rows = data['items'];
      if (rows is! List) return null;
      final users = <RecordModel>[];
      for (final entry in rows) {
        if (entry is! Map || entry['id'] is! String || (entry['id'] as String).isEmpty) return null;
        final row = Map<String, dynamic>.from(entry);
        users.add(RecordModel.fromJson({
          ...row,
          'collectionId': '', 'collectionName': 'users',
          'created': row['created_at']?.toString() ?? '',
          'updated': row['updated_at']?.toString() ?? '',
        }));
      }
      final inbox = <String, Map<String, dynamic>>{};
      if (data['inbox'] is Map) {
        for (final entry in (data['inbox'] as Map).entries) {
          if (entry.key is String && entry.value is Map) {
            inbox[entry.key as String] = Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }
      return CustomerDirectorySnapshot(
        users: users, inbox: inbox,
        totalItems: (data['total_items'] as num?)?.toInt() ?? users.length,
        hasMore: data['has_more'] == true,
        nextCursor: data['next_cursor'] is Map ? Map<String, dynamic>.from(data['next_cursor'] as Map) : null,
        updatedAt: updatedAt,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String userId, String tenantId, CustomerDirectorySnapshot snapshot) async {
    if (userId.isEmpty || tenantId.isEmpty) return;
    final inbox = <String, Map<String, dynamic>>{};
    for (final user in snapshot.users) {
      final original = snapshot.inbox[user.id];
      if (original == null) continue;
      inbox[user.id] = {for (final key in _inboxFields) if (original.containsKey(key)) key: original[key]};
    }
    final data = {
      'version': 1,
      'user_id': userId, 'tenant_id': tenantId,
      'updated_at': snapshot.updatedAt.toIso8601String(),
      'total_items': snapshot.totalItems,
      'has_more': snapshot.hasMore,
      'next_cursor': snapshot.nextCursor,
      'items': [
        for (final user in snapshot.users.take(60)) {
          'id': user.id,
          for (final key in _fields) key: user.data[key],
        },
      ],
      'inbox': inbox,
    };
    await _storage.write(key: _key(userId, tenantId), value: jsonEncode(data));
  }

  @override
  Future<void> clear(String userId, String tenantId) async {
    if (userId.isEmpty || tenantId.isEmpty) return;
    await _storage.delete(key: _key(userId, tenantId));
  }
}
