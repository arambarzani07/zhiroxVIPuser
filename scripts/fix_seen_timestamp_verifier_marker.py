from pathlib import Path

path = Path.cwd() / 'scripts/verify_online_only.py'
text = path.read_text(encoding='utf-8')
old = "    'DateTime? readThrough',\n"
new = "    'required DateTime readThrough',\n"
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one stale nullable read-through marker, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Updated stale read-through verifier marker.')
