from pathlib import Path
import re

ROOT = Path.cwd()
pb_path = ROOT / 'lib/services/pb_service.dart'
verify_path = ROOT / 'scripts/verify_online_only.py'
edge_path = ROOT / 'supabase/functions/delete-account/index.ts'

pb = pb_path.read_text(encoding='utf-8')
verify = verify_path.read_text(encoding='utf-8')

method_re = re.compile(
    r"  static Future<void> deleteAdminWithData\(String adminId\) async \{.*?(?=\n  static Future<int> checkSubscriptionDaysLeft\()",
    re.S,
)
match = method_re.search(pb)
if not match:
    raise SystemExit('deleteAdminWithData method not found')
new_method = '''  static Future<void> deleteAdminWithData(String adminId) async {\n    await ensureInitialized();\n    try {\n      final response = await client.functions.invoke(\n        'delete-account',\n        body: {'user_id': adminId},\n      );\n      if (response.data is Map && response.data['error'] != null) {\n        throw _functionError(response.data);\n      }\n    } on FunctionsException catch (e) {\n      throw _functionError(e.details ?? e.reasonPhrase ?? e.status);\n    }\n  }\n'''
pb = pb[:match.start()] + new_method + pb[match.end():]

error_cases = '''      case 'system_owner_required':\n        return 'تەنها خاوەنی سیستەم دەتوانێت ئەم کردارە ئەنجام بدات';\n      case 'cannot_delete_system_owner':\n        return 'هەژماری خاوەنی سیستەم ناتوانرێت بسڕدرێتەوە';\n      case 'admin_not_found':\n        return 'هەژماری بەڕێوەبەر نەدۆزرایەوە';\n      case 'tenant_member_delete_failed':\n        return 'سڕینەوەی هەندێک هەژماری ناو مارکێت سەرکەوتوو نەبوو؛ دووبارە هەوڵ بدەرەوە';\n      case 'admin_delete_failed':\n        return 'سڕینەوەی هەژماری بەڕێوەبەر سەرکەوتوو نەبوو';\n'''
anchor = "      case 'invalid_input':\n"
if "case 'tenant_member_delete_failed':" not in pb:
    if anchor not in pb:
        raise SystemExit('function error anchor not found')
    pb = pb.replace(anchor, error_cases + anchor, 1)

edge_rel = 'supabase/functions/delete-account/index.ts'
guard = f'''\n# System Owner admin deletion must use its JWT-verified dedicated Edge Function.\nadmin_section = pb.split('// ==================== Admin Subscription Management ====================', 1)[-1]\nadmin_section = admin_section.split('// ==================== Admin Approval ====================', 1)[0]\nif "'delete-account'" not in admin_section:\n    fail('lib/services/pb_service.dart: System Owner admin deletion must use delete-account')\nif "'account-admin'" in admin_section and "'action': 'delete_user'" in admin_section:\n    fail('lib/services/pb_service.dart: System Owner admin deletion must not use the legacy account-admin delete path')\nsecure_delete_edge = ROOT / '{edge_rel}'\nif not secure_delete_edge.exists():\n    fail('{edge_rel}: secure admin deletion Edge Function must be tracked')\nelse:\n    secure_delete_source = secure_delete_edge.read_text(encoding='utf-8')\n    for marker in (\n        'requesterProfile.is_system_owner !== true',\n        'target.role !== "admin"',\n        'target.is_system_owner === true',\n        'admin.auth.admin.deleteUser(userId)',\n        'admin.auth.admin.deleteUser(targetId)',\n        'admin.storage.from("receipts").remove(batch)',\n    ):\n        if marker not in secure_delete_source:\n            fail(f'{edge_rel}: secure deletion marker missing: {{marker}}')\n    for forbidden in (\n        '.from("payments").delete()',\n        '.from("debts").delete()',\n        '.from("notifications").delete()',\n    ):\n        if forbidden in secure_delete_source:\n            fail(f'{edge_rel}: relational cleanup must stay FK-cascade driven, found {{forbidden}}')\n'''
verify_anchor = '\nif violations:\n'
if '# System Owner admin deletion must use its JWT-verified dedicated Edge Function.' not in verify:
    if verify_anchor not in verify:
        raise SystemExit('verifier anchor not found')
    verify = verify.replace(verify_anchor, guard + verify_anchor, 1)

pb_path.write_text(pb, encoding='utf-8')
verify_path.write_text(verify, encoding='utf-8')
print('Secure System Owner admin deletion client applied.')
