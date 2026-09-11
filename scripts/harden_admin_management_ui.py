from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / 'lib/screens/auth/admin_management_screen.dart'
verify = root / 'scripts/verify_online_only.py'
text = path.read_text(encoding='utf-8')

old_guard = '    if (!mounted || _loadInFlight) return;\n'
new_guard = '    if (!mounted || _loadInFlight || _isLoadingMore) return;\n'
if old_guard in text:
    text = text.replace(old_guard, new_guard, 1)
elif new_guard not in text:
    raise SystemExit('loadAdmins guard anchor missing')

load_more_anchor = '''    setState(() => _isLoadingMore = true);
    try {
'''
load_more_replacement = '''    _loadInFlight = true;
    setState(() => _isLoadingMore = true);
    try {
'''
if load_more_anchor in text:
    text = text.replace(load_more_anchor, load_more_replacement, 1)
elif load_more_replacement not in text:
    raise SystemExit('loadMore lock anchor missing')

finally_anchor = '''    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
'''
finally_replacement = '''    } finally {
      _loadInFlight = false;
      if (mounted) setState(() => _isLoadingMore = false);
    }
'''
if finally_anchor in text:
    text = text.replace(finally_anchor, finally_replacement, 1)
elif finally_replacement not in text:
    raise SystemExit('loadMore unlock anchor missing')

old_validator = '''                            if (days == null || days <= 0) {
                              return 'ژمارەی ڕۆژێکی دروست بنووسە';
                            }
'''
new_validator = '''                            if (days == null || days < 1 || days > 3650) {
                              return 'ماوە دەبێت لە ١ تا ٣٦٥٠ ڕۆژ بێت';
                            }
'''
count = text.count(old_validator)
if count:
    text = text.replace(old_validator, new_validator)
if text.count(new_validator) < 2:
    raise SystemExit(f'subscription validator count={text.count(new_validator)}')

path.write_text(text, encoding='utf-8')

v = verify.read_text(encoding='utf-8')
marker = '# Owner admin-management paging must serialize refresh and pagination.'
if marker not in v:
    block = r'''
# Owner admin-management paging must serialize refresh and pagination.
if edition == 'owner-source':
    owner_management = (LIB / 'screens/auth/admin_management_screen.dart').read_text(encoding='utf-8')
    if owner_management.count('_loadInFlight = true;') < 2:
        fail('lib/screens/auth/admin_management_screen.dart: refresh/load-more requests must share one in-flight lock')
    if '_loadInFlight = false;\n      if (mounted) setState(() => _isLoadingMore = false);' not in owner_management:
        fail('lib/screens/auth/admin_management_screen.dart: load-more lock must always release in finally')
    if owner_management.count("return 'ماوە دەبێت لە ١ تا ٣٦٥٠ ڕۆژ بێت';") < 2:
        fail('lib/screens/auth/admin_management_screen.dart: subscription day validation must match backend bounds')

'''
    if '\nif violations:\n' not in v:
        raise SystemExit('verifier end anchor missing')
    v = v.replace('\nif violations:\n', '\n' + block + 'if violations:\n', 1)
verify.write_text(v, encoding='utf-8')
