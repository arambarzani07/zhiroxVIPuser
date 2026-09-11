from pathlib import Path
import re

ROOT = Path.cwd()
ui_path = ROOT / 'lib/screens/shared/user_list_screen.dart'
verify_path = ROOT / 'scripts/verify_online_only.py'

ui = ui_path.read_text(encoding='utf-8')
verify = verify_path.read_text(encoding='utf-8')

method_re = re.compile(
    r"  Future<void> _loadUsers\(\{String\? search\}\) async \{.*?(?=\n  Future<void> _loadCustomerInboxInBackground\()",
    re.S,
)
m = method_re.search(ui)
if not m:
    raise SystemExit('_loadUsers method not found')
method = m.group(0)
old_catch = "    } catch (_) {\n      if (!mounted) return;\n      setState(() {\n        _users = [];"
new_catch = "    } catch (_) {\n      if (!mounted || generation != _loadGeneration) return;\n      setState(() {\n        _users = [];"
if new_catch not in method:
    if old_catch not in method:
        raise SystemExit('stale failure catch marker not found')
    method = method.replace(old_catch, new_catch, 1)
    ui = ui[:m.start()] + method + ui[m.end():]

old_reconnect = "    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {\n      if (online && mounted) _loadUsers();\n    });"
new_reconnect = "    _connectivitySub = ConnectivityService.instance.statusStream.listen((online) {\n      if (online && mounted) {\n        _loadUsers(search: _searchController.text.trim());\n      }\n    });"
if new_reconnect not in ui:
    if old_reconnect not in ui:
        raise SystemExit('connectivity reload marker not found')
    ui = ui.replace(old_reconnect, new_reconnect, 1)

guard = '''\n# Customer-list async loads must ignore stale failures and preserve the active\n# search query when connectivity returns.\nif 'if (!mounted || generation != _loadGeneration) return;' not in customer_list_source:\n    fail('lib/screens/shared/user_list_screen.dart: stale customer-list failures must be generation-guarded')\nif 'if (online && mounted) _loadUsers();' in customer_list_source:\n    fail('lib/screens/shared/user_list_screen.dart: reconnect must not discard the active customer search')\nif "_loadUsers(search: _searchController.text.trim());" not in customer_list_source:\n    fail('lib/screens/shared/user_list_screen.dart: reconnect/search-preserving reload marker missing')\n'''
anchor = "\nif violations:\n"
if guard not in verify:
    if anchor not in verify:
        raise SystemExit('verifier final anchor not found')
    verify = verify.replace(anchor, guard + anchor, 1)

ui_path.write_text(ui, encoding='utf-8')
verify_path.write_text(verify, encoding='utf-8')
print('Customer list generation guard applied.')
