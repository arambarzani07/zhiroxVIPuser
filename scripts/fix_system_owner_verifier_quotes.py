from pathlib import Path

path = Path('scripts/verify_online_only.py')
text = path.read_text(encoding='utf-8')
lines = text.splitlines()
replacement = "if 'admin_id = \"$adminId\" && role = \"employee\"' in admin_section or 'admin_id = \"$adminId\" && role = \"customer\"' in admin_section:"
changed = False
for index, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith("if 'filter: 'admin_id") and 'role = \"employee\"' in line and 'role = \"customer\"' in line:
        lines[index] = replacement
        changed = True
        break
if not changed and replacement not in text:
    raise SystemExit('System Owner verifier quote target not found')
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print('System Owner verifier quote fix applied.')
