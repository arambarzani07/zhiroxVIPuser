from pathlib import Path
import os

root = Path(os.environ.get('REPO_ROOT', Path.cwd())).resolve()
profile_path = root / 'lib/screens/shared/user_profile_screen.dart'
text = profile_path.read_text(encoding='utf-8')
old = '    final runningBalances = _financialRunningBalances(allTimelineItems);\n'
new = '''    // A partial newest-page window has no trustworthy opening ledger balance.\n    // Hide per-row running balances until the complete history is hydrated.\n    final runningBalances = _financialTimelineHasMore\n        ? const <String, double?>{}\n        : _financialRunningBalances(allTimelineItems);\n'''
if text.count(old) != 1:
    raise SystemExit(f'running balance anchor count={text.count(old)}')
profile_path.write_text(text.replace(old, new, 1), encoding='utf-8')

verify_path = root / 'scripts/verify_online_only.py'
verify = verify_path.read_text(encoding='utf-8')
anchor = "    'مامەڵە کۆنەکان باربکە',\n):\n"
replacement = "    'مامەڵە کۆنەکان باربکە',\n    '_financialTimelineHasMore\\n        ? const <String, double?>{}',\n):\n"
if verify.count(anchor) != 1:
    raise SystemExit(f'verifier anchor count={verify.count(anchor)}')
verify_path.write_text(verify.replace(anchor, replacement, 1), encoding='utf-8')
