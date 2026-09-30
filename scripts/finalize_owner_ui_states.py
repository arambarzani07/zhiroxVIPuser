from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUTH = ROOT / 'lib' / 'screens' / 'auth'

COMMON_ERROR = '''              ? Center(\n                  child: Padding(\n                    padding: const EdgeInsets.all(24),\n                    child: Column(\n                      mainAxisSize: MainAxisSize.min,\n                      children: [\n                        const Icon(Icons.cloud_off_rounded, size: 44),\n                        const SizedBox(height: 12),\n                        Text(_error!, textAlign: TextAlign.center),\n                        const SizedBox(height: 12),\n                        FilledButton(\n                          onPressed: _load,\n                          child: const Text('دووبارە هەوڵ بدە'),\n                        ),\n                      ],\n                    ),\n                  ),\n                )\n'''

NEW_ERROR = '''              ? OwnerStatePanel.error(\n                  message: _error!,\n                  onAction: _load,\n                )\n'''

changed = []
for path in sorted(AUTH.glob('owner_*_screen.dart')) + [AUTH / 'import_permission_screen.dart']:
    if not path.exists():
        continue
    text = path.read_text()
    original = text
    text = text.replace(COMMON_ERROR, NEW_ERROR)
    text = text.replace(
        'child: ListView(\n                    padding: const EdgeInsets.all(16),',
        'child: ListView(\n                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),',
    )
    text = text.replace(
        "? const Center(child: Text('هیچ مارکێتێک بەردەست نییە'))",
        "? const OwnerStatePanel.empty(\n                  title: 'هیچ مارکێتێک بەردەست نییە',\n                  message: 'سەرەتا مارکێتێک دروست بکە، پاشان دەسەڵات و پلانەکەی ڕێکبخە.',\n                )",
    )
    text = text.replace(
        "? Center(child: Text(_error?.toString() ?? 'زانیاری بەردەست نییە'))",
        "? OwnerStatePanel.error(\n                  message: _error?.toString() ?? 'زانیاری بەردەست نییە',\n                  onAction: _load,\n                )",
    )
    if text != original:
        path.write_text(text)
        changed.append(path.name)

print('finalized:', ', '.join(changed))
