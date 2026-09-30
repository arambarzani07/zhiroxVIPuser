#!/usr/bin/env python3
from pathlib import Path

path = Path('lib/screens/auth/owner_dashboard.dart')
text = path.read_text(encoding='utf-8')

import_line = "import 'package:zhirox/screens/auth/owner_permission_center_screen.dart';\n"
anchor_import = "import 'package:zhirox/screens/auth/owner_entitlements_center_screen.dart';\n"
if import_line not in text:
    if anchor_import not in text:
        raise SystemExit('owner dashboard import anchor not found')
    text = text.replace(anchor_import, anchor_import + import_line, 1)

marker = "title: const Text('ناوەندی دەسەڵاتەکانی Owner'),"
if marker not in text:
    anchor = """                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.support_agent_rounded,
                        color: Colors.indigo,
                      ),
                    ),
                    title: const Text('ناوەندی پشتیوانی'),
"""
    tile = """                  const Divider(height: 1),
                  ListTile(
                    minTileHeight: 72,
                    leading: CircleAvatar(
                      backgroundColor: Colors.deepPurple.withValues(alpha: 0.10),
                      child: const Icon(
                        Icons.admin_panel_settings_rounded,
                        color: Colors.deepPurple,
                      ),
                    ),
                    title: const Text('ناوەندی دەسەڵاتەکانی Owner'),
                    subtitle: const Text(
                      '٢٠٠ دەسەڵات، Risk، Scope و پالیسی پاراستن لە catalog ـی live',
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OwnerPermissionCenterScreen(),
                      ),
                    ),
                  ),
"""
    if anchor not in text:
        raise SystemExit('owner dashboard support tile anchor not found')
    text = text.replace(anchor, tile + anchor, 1)

path.write_text(text, encoding='utf-8')
print('Owner permission center wired into owner dashboard')
