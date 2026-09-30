import 'package:zhirox/services/pb_service.dart';

class OwnerPermissionCatalogEntry {
  const OwnerPermissionCatalogEntry({
    required this.key,
    required this.label,
    required this.groupKey,
    required this.groupLabel,
    required this.riskLevel,
    required this.scopes,
    required this.requiresReason,
    required this.requiresReauth,
    required this.requiresTypedConfirmation,
    required this.requiresTwoPersonApproval,
    required this.active,
    required this.allowedPlatform,
  });

  final String key;
  final String label;
  final String groupKey;
  final String groupLabel;
  final int riskLevel;
  final List<String> scopes;
  final bool requiresReason;
  final bool requiresReauth;
  final bool requiresTypedConfirmation;
  final bool requiresTwoPersonApproval;
  final bool active;
  final bool allowedPlatform;

  factory OwnerPermissionCatalogEntry.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['scopes'];
    final scopes = rawScopes is List
        ? rawScopes.map((value) => value.toString()).toList(growable: false)
        : const <String>[];
    return OwnerPermissionCatalogEntry(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      groupKey: json['group_key']?.toString() ?? '',
      groupLabel: json['group_label']?.toString() ?? '',
      riskLevel: (json['risk_level'] as num?)?.toInt() ?? 1,
      scopes: scopes,
      requiresReason: json['requires_reason'] == true,
      requiresReauth: json['requires_reauth'] == true,
      requiresTypedConfirmation: json['requires_typed_confirmation'] == true,
      requiresTwoPersonApproval: json['requires_two_person_approval'] == true,
      active: json['active'] != false,
      allowedPlatform: json['allowed_platform'] == true,
    );
  }
}

class OwnerPermissionCatalog {
  const OwnerPermissionCatalog({
    required this.count,
    required this.permissions,
  });

  final int count;
  final List<OwnerPermissionCatalogEntry> permissions;
}

class OwnerPermissionService {
  static const expectedPermissionCount = 200;

  static Future<OwnerPermissionCatalog> fetchCatalog() async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc('get_system_owner_permission_catalog');
    if (raw is! Map) {
      throw Exception('invalid_owner_permission_catalog');
    }

    final map = Map<String, dynamic>.from(raw);
    final rawPermissions = map['permissions'];
    if (rawPermissions is! List) {
      throw Exception('invalid_owner_permission_catalog_permissions');
    }

    final permissions = rawPermissions
        .whereType<Map>()
        .map((value) => OwnerPermissionCatalogEntry.fromJson(
              Map<String, dynamic>.from(value),
            ))
        .where((value) => value.key.isNotEmpty && value.active)
        .toList(growable: false);

    final remoteCount = (map['count'] as num?)?.toInt() ?? permissions.length;
    if (remoteCount != permissions.length ||
        permissions.length != expectedPermissionCount) {
      throw Exception(
        'owner_permission_catalog_count_mismatch:'
        '$remoteCount/${permissions.length}/$expectedPermissionCount',
      );
    }

    return OwnerPermissionCatalog(
      count: remoteCount,
      permissions: permissions,
    );
  }
}
