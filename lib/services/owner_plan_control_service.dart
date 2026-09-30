import 'package:zhirox/services/pb_service.dart';

class OwnerPlanLimitDefinition {
  const OwnerPlanLimitDefinition({
    required this.key,
    required this.label,
    required this.description,
    required this.minValue,
    required this.maxValue,
    required this.zeroMeansUnlimited,
  });

  final String key;
  final String label;
  final String description;
  final int minValue;
  final int maxValue;
  final bool zeroMeansUnlimited;

  factory OwnerPlanLimitDefinition.fromJson(Map<String, dynamic> json) {
    return OwnerPlanLimitDefinition(
      key: '${json['limit_key'] ?? ''}',
      label: '${json['display_name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      minValue: (json['min_value'] as num?)?.toInt() ?? 0,
      maxValue: (json['max_value'] as num?)?.toInt() ?? 0,
      zeroMeansUnlimited: json['zero_means_unlimited'] == true,
    );
  }
}

class OwnerPlanLimits {
  const OwnerPlanLimits({required this.catalog, required this.plans});
  final List<OwnerPlanLimitDefinition> catalog;
  final Map<String, Map<String, int>> plans;
}

class OwnerTenantLimitEntry {
  const OwnerTenantLimitEntry({
    required this.key,
    required this.label,
    required this.description,
    required this.planValue,
    required this.overrideValue,
    required this.effectiveValue,
    required this.source,
    required this.maxValue,
    required this.zeroMeansUnlimited,
  });

  final String key;
  final String label;
  final String description;
  final int planValue;
  final int? overrideValue;
  final int effectiveValue;
  final String source;
  final int maxValue;
  final bool zeroMeansUnlimited;

  factory OwnerTenantLimitEntry.fromJson(Map<String, dynamic> json) {
    return OwnerTenantLimitEntry(
      key: '${json['limit_key'] ?? ''}',
      label: '${json['display_name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      planValue: (json['plan_value'] as num?)?.toInt() ?? 0,
      overrideValue: json['override_value'] == null
          ? null
          : (json['override_value'] as num?)?.toInt(),
      effectiveValue: (json['effective_value'] as num?)?.toInt() ?? 0,
      source: '${json['source'] ?? 'plan'}',
      maxValue: (json['max_value'] as num?)?.toInt() ?? 0,
      zeroMeansUnlimited: json['zero_means_unlimited'] == true,
    );
  }
}

class OwnerTenantPlanControl {
  const OwnerTenantPlanControl({
    required this.adminId,
    required this.planKey,
    required this.limits,
  });

  final String adminId;
  final String planKey;
  final List<OwnerTenantLimitEntry> limits;
}

class OwnerPlanControlService {
  static Future<OwnerPlanLimits> fetchPlanLimits() async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc('get_system_owner_plan_limits');
    if (raw is! Map) throw Exception('invalid_plan_limits');
    final map = Map<String, dynamic>.from(raw);
    final catalog = <OwnerPlanLimitDefinition>[];
    if (map['catalog'] is List) {
      for (final row in map['catalog'] as List) {
        if (row is Map) {
          catalog.add(OwnerPlanLimitDefinition.fromJson(
            Map<String, dynamic>.from(row),
          ));
        }
      }
    }
    final plans = <String, Map<String, int>>{};
    final rawPlans = map['plans'];
    if (rawPlans is Map) {
      for (final entry in rawPlans.entries) {
        final values = <String, int>{};
        if (entry.value is Map) {
          for (final value in (entry.value as Map).entries) {
            values['${value.key}'] = (value.value as num?)?.toInt() ?? 0;
          }
        }
        plans['${entry.key}'] = values;
      }
    }
    return OwnerPlanLimits(catalog: catalog, plans: plans);
  }

  static Future<void> setPlanLimit({
    required String planKey,
    required String limitKey,
    required int value,
  }) async {
    await PBService.ensureInitialized();
    await PBService.client.rpc(
      'set_system_owner_plan_limit',
      params: {
        'p_plan_key': planKey,
        'p_limit_key': limitKey,
        'p_limit_value': value,
      },
    );
  }

  static Future<OwnerTenantPlanControl> fetchTenantLimits(String adminId) async {
    await PBService.ensureInitialized();
    final raw = await PBService.client.rpc(
      'get_system_owner_tenant_limits',
      params: {'p_admin_id': adminId},
    );
    if (raw is! Map) throw Exception('invalid_tenant_limits');
    final map = Map<String, dynamic>.from(raw);
    final limits = <OwnerTenantLimitEntry>[];
    if (map['limits'] is List) {
      for (final row in map['limits'] as List) {
        if (row is Map) {
          limits.add(OwnerTenantLimitEntry.fromJson(
            Map<String, dynamic>.from(row),
          ));
        }
      }
    }
    return OwnerTenantPlanControl(
      adminId: '${map['admin_id'] ?? adminId}',
      planKey: '${map['plan_key'] ?? 'standard'}',
      limits: limits,
    );
  }

  static Future<void> setTenantLimitOverride({
    required String adminId,
    required String limitKey,
    required int? value,
  }) async {
    await PBService.ensureInitialized();
    await PBService.client.rpc(
      'set_system_owner_tenant_limit_override',
      params: {
        'p_admin_id': adminId,
        'p_limit_key': limitKey,
        'p_limit_value': value,
      },
    );
  }

  static Future<void> setTenantPlan({
    required String adminId,
    required String planKey,
  }) async {
    await PBService.ensureInitialized();
    await PBService.client.rpc(
      'set_system_owner_tenant_feature_plan',
      params: {'p_admin_id': adminId, 'p_plan_key': planKey},
    );
  }
}
