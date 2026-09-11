from pathlib import Path
import re

ROOT = Path.cwd()
pb_path = ROOT / 'lib/services/pb_service.dart'
verify_path = ROOT / 'scripts/verify_online_only.py'

pb = pb_path.read_text(encoding='utf-8')
verify = verify_path.read_text(encoding='utf-8')

page_re = re.compile(
    r"  static Future<Map<String, dynamic>> getAdminsPage\(\{.*?(?=\n  static Future<void> renewAdminSubscription\()",
    re.S,
)
page_match = page_re.search(pb)
if not page_match:
    raise SystemExit('getAdminsPage method not found')

new_page = '''  static Future<Map<String, dynamic>> getAdminsPage({\n    int page = 1,\n    int perPage = 15,\n  }) async {\n    await ensureInitialized();\n    final safePage = page < 1 ? 1 : page;\n    final safePerPage = perPage < 1 ? 1 : (perPage > 100 ? 100 : perPage);\n    final raw = await client.rpc(\n      'get_system_owner_admins_page',\n      params: {\n        'p_page': safePage,\n        'p_per_page': safePerPage,\n      },\n    );\n    if (raw is! Map) throw Exception('invalid admin management page');\n\n    final data = Map<String, dynamic>.from(raw);\n    final admins = <Map<String, dynamic>>[];\n    final rawAdmins = data['admins'];\n    if (rawAdmins is List) {\n      for (final item in rawAdmins) {\n        if (item is! Map) continue;\n        final row = Map<String, dynamic>.from(item);\n        final rawAdmin = row['admin'];\n        if (rawAdmin is! Map) continue;\n        int asInt(dynamic value) =>\n            value is int ? value : int.tryParse('${value ?? 0}') ?? 0;\n        admins.add({\n          'admin': _profileRecord(Map<String, dynamic>.from(rawAdmin)),\n          'employeeCount': asInt(row['employee_count']),\n          'customerCount': asInt(row['customer_count']),\n        });\n      }\n    }\n\n    int asInt(dynamic value, int fallback) =>\n        value is int ? value : int.tryParse('${value ?? ''}') ?? fallback;\n    return {\n      'admins': admins,\n      'totalItems': asInt(data['total_items'], admins.length),\n      'totalPages': asInt(data['total_pages'], 1),\n      'page': asInt(data['page'], safePage),\n    };\n  }\n'''
pb = pb[:page_match.start()] + new_page + pb[page_match.end():]

renew_re = re.compile(
    r"  static Future<void> renewAdminSubscription\(String adminId, int days\) async \{.*?\n  \}",
    re.S,
)
renew_match = renew_re.search(pb)
if not renew_match:
    raise SystemExit('renewAdminSubscription method not found')
new_renew = '''  static Future<void> renewAdminSubscription(String adminId, int days) async {\n    if (days < 1 || days > 3650) throw Exception('invalid_input');\n    await ensureInitialized();\n    await client.rpc(\n      'renew_system_owner_admin_subscription',\n      params: {\n        'p_admin_id': adminId,\n        'p_days': days,\n      },\n    );\n  }'''
pb = pb[:renew_match.start()] + new_renew + pb[renew_match.end():]

# Regression guard: admin-management pagination must remain set-based and\n# System-Owner scoped. Do not restore per-admin employee/customer list calls.\nguard = '''\n# System Owner admin management must use the set-based, owner-checked RPCs.\nfor marker in (\n    "'get_system_owner_admins_page'",\n    "'renew_system_owner_admin_subscription'",\n    "'employeeCount': asInt(row['employee_count'])",\n    "'customerCount': asInt(row['customer_count'])",\n):\n    if marker not in pb:\n        fail(f'lib/services/pb_service.dart: System Owner admin-management marker missing: {marker}')\nadmin_section = pb.split('// ==================== Admin Subscription Management ====================', 1)[-1]\nadmin_section = admin_section.split('// ==================== Admin Approval ====================', 1)[0]\nif 'for (final admin in result.items)' in admin_section:\n    fail('lib/services/pb_service.dart: Admin management must not restore per-admin N+1 queries')\nif 'filter: \'admin_id = "$adminId" && role = "employee"\'' in admin_section or 'filter: \'admin_id = "$adminId" && role = "customer"\'' in admin_section:\n    fail('lib/services/pb_service.dart: Admin management counts must stay set-based')\nadmin_rpc_migration = ROOT / 'supabase/migrations/20260911102326_system_owner_admin_management_rpcs.sql'\nif not admin_rpc_migration.exists():\n    fail(f'{admin_rpc_migration.relative_to(ROOT)}: System Owner admin-management migration must be tracked')\nelse:\n    admin_rpc_source = admin_rpc_migration.read_text(encoding='utf-8')\n    for marker in (\n        'security definer',\n        'p.is_system_owner = true',\n        'a.is_system_owner = false',\n        'get_system_owner_admins_page',\n        'renew_system_owner_admin_subscription',\n        'revoke all on function public.get_system_owner_admins_page(integer, integer) from public, anon;',\n        'revoke all on function public.renew_system_owner_admin_subscription(uuid, integer) from public, anon;',\n    ):\n        if marker not in admin_rpc_source.lower():\n            fail(f'{admin_rpc_migration.relative_to(ROOT)}: System Owner RPC security marker missing: {marker}')\n'''
anchor = '\nif violations:\n'
if guard not in verify:
    if anchor not in verify:
        raise SystemExit('verifier anchor not found')
    verify = verify.replace(anchor, guard + anchor, 1)

pb_path.write_text(pb, encoding='utf-8')
verify_path.write_text(verify, encoding='utf-8')
print('System Owner admin-management RPC client applied.')
