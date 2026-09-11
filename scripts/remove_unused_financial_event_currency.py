from pathlib import Path
import os

root = Path(os.environ.get('REPO_ROOT', Path.cwd())).resolve()
path = root / 'lib/screens/shared/user_profile_screen.dart'
text = path.read_text(encoding='utf-8')
old = """    final amount = record.getDoubleValue('amount');\n    final currency = record.getStringValue('currency').isEmpty\n        ? 'IQD'\n        : record.getStringValue('currency');\n    // Audit events store the canonical amount but do not snapshot dollar_rate.\n"""
new = """    final amount = record.getDoubleValue('amount');\n    // Audit events store the canonical amount but do not snapshot dollar_rate.\n"""
if text.count(old) != 1:
    raise SystemExit(f'expected one system-event currency block, found {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Removed unused Financial Chat event currency variable.')
