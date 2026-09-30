#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
paths = [
    root / 'scripts/expand_permissions_to_180.py',
    root / 'scripts/verify_employee_permissions_contract.py',
]
old = r'r"^\\s*(can_[a-z0-9_]+)\\s*=\\s*new\\.\\1\\s*,?\\s*$"'
new = r'r"^\\s*(?:set\\s+)?(can_[a-z0-9_]+)\\s*=\\s*new\\.\\1\\s*,?\\s*$"'
for path in paths:
    if not path.exists():
        continue
    text = path.read_text(encoding='utf-8')
    if old in text:
        text = text.replace(old, new)
        path.write_text(text, encoding='utf-8')
        print(f'fixed {path.relative_to(root)}')
