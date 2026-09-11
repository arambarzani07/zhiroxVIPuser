from pathlib import Path

path = Path('scripts/verify_online_only.py')
text = path.read_text(encoding='utf-8')
old = 'پارەدانەوەی تەواو'
new = 'پارە وەرگرتنەوەی تەواو'
if old not in text:
    raise SystemExit(f'expected verifier marker not found: {old}')
text = text.replace(old, new)
path.write_text(text, encoding='utf-8')

stale = ('پارەدانەوە', 'قەرزی نوێ', 'سنوری قەرز', 'بێ سنور')
remaining = [marker for marker in stale if marker in text]
if remaining:
    raise SystemExit(f'stale UI verifier markers remain: {remaining}')
print('UI verifier terminology aligned.')
