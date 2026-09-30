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

class OwnerMarketSummary {
  const OwnerMarketSummary({
    required this.id,
    required this.marketName,
    required this.adminName,
    required this.phone,
    required this.active,
    required this.approved,
  });

  final String id;
  final String marketName;
  final String adminName;
  final String phone;
  final bool active;
  final bool approved;

  factory OwnerMarketSummary.fromJson(Map<String, dynamic> json) {
    return OwnerMarketSummary(
      id: json['id']?.toString() ?? '',
      marketName: json['market_name']?.toString() ?? '',
      adminName: json['admin_name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      active: json['active'] == true,
      approved: json['approved'] == true,
    );
  }

  String get displayName => marketName.trim().isEmpty ? adminName : marketName;
}

class OwnerMarketPermissionEntry {
  const OwnerMarketPermissionEntry({
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
    required this.applicable,
    required this.scopeType,
    required this.mode,
    required this.effectiveAllowed,
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
  final bool applicable;
  final String? scopeType;
  final String mode;
  final bool effectiveAllowed;

  factory OwnerMarketPermissionEntry.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['scopes'];
    return OwnerMarketPermissionEntry(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      groupKey: json['group_key']?.toString() ?? '',
      groupLabel: json['group_label']?.toString() ?? '',
      riskLevel: (json['risk_level'] as num?)?.toInt() ?? 1,
      scopes: rawScopes is List
          ? rawScopes.map((value) => value.toString()).toList(growable: false)
          : const <String>[],
      requiresReason: json['requires_reason'] == true,
      requiresReauth: json['requires_reauth'] == true,
      requiresTypedConfirmation: json['requires_typed_confirmation'] == true,
      requiresTwoPersonApproval: json['requires_two_person_approval'] == true,
      applicable: json['applicable'] == true,
      scopeType: json['scope_type']?.toString(),
      mode: json['mode']?.toString() ?? 'inherit',
      effectiveAllowed: json['effective_allowed'] == true,
    );
  }
}

class OwnerMarketPermissionMatrix {
  const OwnerMarketPermissionMatrix({
    required this.market,
    required this.count,
    required this.editableCount,
    required this.permissions,
  });

  final OwnerMarketSummary market;
  final int count;
  final int editableCount;
  final List<OwnerMarketPermissionEntry> permissions;

  factory OwnerMarketPermissionMatrix.fromJson(Map<String, dynamic> json) {
    final rawMarket = json['market'];
    final rawPermissions = json['permissions'];
    if (rawMarket is! Map || rawPermissions is! List) {
      throw Exception('invalid_owner_market_permission_matrix');
    }
    final permissions = rawPermissions
        .whereType<Map>()
        .map((value) => OwnerMarketPermissionEntry.fromJson(
              Map<String, dynamic>.from(value),
            ))
        .where((value) => value.key.isNotEmpty)
        .toList(growable: false);
    final count = (json['count'] as num?)?.toInt() ?? permissions.length;
    if (count != permissions.length ||
        permissions.length != OwnerPermissionService.expectedPermissionCount) {
      throw Exception(
        'owner_market_permission_matrix_count_mismatch:'
        '$count/${permissions.length}/${OwnerPermissionService.expectedPermissionCount}',
      );
    }
    return OwnerMarketPermissionMatrix(
      market: OwnerMarketSummary.fromJson(Map<String, dynamic>.from(rawMarket)),
      count: count,
      editableCount: (json['editable_count'] as num?)?.toInt() ??
          permissions.where((value) => value.applicable).length,
      permissions: permissions,
    );
  }
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

  static Future<List<OwnerMarketSummary>> fetchMarkets() async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_system_owner_tenants_page',
      params: const {'p_page': 1, 'p_per_page': 100},
    );
    if (raw is! Map) throw Exception('invalid_owner_market_list');
    final rows = raw['tenants'];
    if (rows is! List) throw Exception('invalid_owner_market_list_rows');
    return rows
        .whereType<Map>()
        .map((value) => OwnerMarketSummary.fromJson(
              Map<String, dynamic>.from(value),
            ))
        .where((value) => value.id.isNotEmpty)
        .toList(growable: false);
  }

  static Future<OwnerMarketPermissionMatrix> fetchMarketMatrix(
    String adminId,
  ) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_system_owner_market_permission_matrix',
      params: {'p_admin_id': adminId},
    );
    if (raw is! Map) throw Exception('invalid_owner_market_permission_matrix');
    return OwnerMarketPermissionMatrix.fromJson(Map<String, dynamic>.from(raw));
  }

  static Future<OwnerMarketPermissionMatrix> saveMarketMatrix({
    required String adminId,
    required Map<String, String> changes,
    String reason = '',
  }) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'set_system_owner_market_permission_matrix',
      params: {
        'p_admin_id': adminId,
        'p_changes': changes.entries
            .map((entry) => {'key': entry.key, 'mode': entry.value})
            .toList(growable: false),
        'p_reason': reason.trim(),
      },
    );
    if (raw is! Map) throw Exception('invalid_owner_market_permission_matrix');
    return OwnerMarketPermissionMatrix.fromJson(Map<String, dynamic>.from(raw));
  }
}
