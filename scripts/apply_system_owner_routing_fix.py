from pathlib import Path

ROOT = Path.cwd()
main_path = ROOT / 'lib/main.dart'
login_path = ROOT / 'lib/screens/auth/login_screen.dart'
management_path = ROOT / 'lib/screens/auth/admin_management_screen.dart'

main = main_path.read_text(encoding='utf-8')
login = login_path.read_text(encoding='utf-8')
management = management_path.read_text(encoding='utf-8')

# 1) Authenticated System Owner gets the dedicated management screen.
main_import = "import 'package:zhirox/screens/auth/admin_management_screen.dart';\n"
login_import = "import 'package:zhirox/screens/auth/login_screen.dart';\n"
if main_import not in main:
    if login_import not in main:
        raise SystemExit('main login import anchor not found')
    main = main.replace(login_import, main_import + login_import, 1)

route_anchor = "        if (!auth.isLoggedIn) return const LoginScreen();\n\n        switch (auth.userRole) {"
route_replacement = "        if (!auth.isLoggedIn) return const LoginScreen();\n\n        if (auth.user?.getBoolValue('is_system_owner') ?? false) {\n          return const AdminManagementScreen();\n        }\n\n        switch (auth.userRole) {"
if route_replacement not in main:
    if route_anchor not in main:
        raise SystemExit('System Owner route anchor not found')
    main = main.replace(route_anchor, route_replacement, 1)

# 2) Logged-out Owner app must not open an admin-registration form that the
# server will reject. Keep the visible button but make it explain the secure flow.
register_import = "import 'package:zhirox/screens/auth/register_admin_screen.dart';\n"
login = login.replace(register_import, '')
old_method = """  void _openAdminRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterAdminScreen()),
    );
  }
"""
new_method = """  void _openAdminRegistration() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('هەژماری بەڕێوەبەر'),
        content: const Text(
          'بۆ دروستکردنی هەژماری بەڕێوەبەر، سەرەتا بە هەژماری خاوەن سیستەم بچۆ ژوورەوە. دوای چوونەژوورەوە، لە پەڕەی بەڕێوەبردنی بەڕێوەبەران هەژماری نوێ دروست بکە.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('باشە'),
          ),
        ],
      ),
    );
  }
"""
if new_method not in login:
    if old_method not in login:
        raise SystemExit('owner login registration method anchor not found')
    login = login.replace(old_method, new_method, 1)

# 3) Dedicated System Owner screen needs a proper AuthProvider logout path.
provider_import = "import 'package:provider/provider.dart';\n"
auth_import = "import 'package:zhirox/providers/auth_provider.dart';\n"
flutter_import = "import 'package:flutter/material.dart';\n"
if provider_import not in management:
    if flutter_import not in management:
        raise SystemExit('management flutter import anchor not found')
    management = management.replace(flutter_import, flutter_import + provider_import, 1)
if auth_import not in management:
    anchor = provider_import if provider_import in management else flutter_import
    management = management.replace(anchor, anchor + auth_import, 1)

create_action = """          IconButton(
            tooltip: 'بەڕێوەبەری نوێ',
            onPressed: _showCreateAdminDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 21),
          ),
          const SizedBox(width: 4),
"""
secure_actions = """          IconButton(
            tooltip: 'بەڕێوەبەری نوێ',
            onPressed: _showCreateAdminDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 21),
          ),
          IconButton(
            tooltip: 'چوونەدەرەوە',
            onPressed: () async {
              await context.read<AuthProvider>().logout();
            },
            icon: const Icon(Icons.logout_rounded, size: 21),
          ),
          const SizedBox(width: 4),
"""
if secure_actions not in management:
    if create_action not in management:
        raise SystemExit('management appbar action anchor not found')
    management = management.replace(create_action, secure_actions, 1)

main_path.write_text(main, encoding='utf-8')
login_path.write_text(login, encoding='utf-8')
management_path.write_text(management, encoding='utf-8')
print('System Owner authenticated routing flow applied.')
