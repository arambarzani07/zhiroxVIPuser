from pathlib import Path

ROOT = Path.cwd()
main_path = ROOT / 'lib/main.dart'
verify_path = ROOT / 'scripts/verify_online_only.py'

main = main_path.read_text(encoding='utf-8')
verify = verify_path.read_text(encoding='utf-8')

anchor = "        if (!auth.isLoggedIn) return const LoginScreen();\n\n        switch (auth.userRole) {"
replacement = """        if (!auth.isLoggedIn) return const LoginScreen();

        // User edition must never expose System Owner capabilities. Even if
        // valid owner credentials are entered here, keep the account isolated
        // to the dedicated ZHIROX Owner application.
        if (auth.user?.getBoolValue('is_system_owner') ?? false) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 56,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'ئەم هەژمارە بۆ ZHIROX Owner ـە',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'بۆ بەڕێوەبردنی هەژمارەکانی بەڕێوەبەر، ئەپی ZHIROX Owner بەکاربهێنە. ئەپی User دەسەڵاتی خاوەن سیستەم نادات.',
                          textAlign: TextAlign.center,
                          style: TextStyle(height: 1.7),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: auth.isLoading ? null : () => auth.logout(),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('چوونەدەرەوە'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        switch (auth.userRole) {"""

if replacement not in main:
    if anchor not in main:
        raise SystemExit('User AuthWrapper anchor not found')
    main = main.replace(anchor, replacement, 1)

# Edition-separation regression guard. User source must not ship owner/admin
# creation screens and must explicitly block System Owner accounts.
guard = """
# User-edition Owner isolation must remain enforced.
for forbidden_path in (
    ROOT / 'lib/screens/auth/admin_management_screen.dart',
    ROOT / 'lib/screens/auth/register_admin_screen.dart',
):
    if forbidden_path.exists():
        fail(f'{forbidden_path.relative_to(ROOT)}: owner-only screen must not ship in User source')
if 'AdminManagementScreen' in main:
    fail('lib/main.dart: User source must not reference AdminManagementScreen')
for marker in (
    "auth.user?.getBoolValue('is_system_owner') ?? false",
    'ئەم هەژمارە بۆ ZHIROX Owner ـە',
    'ئەپی User دەسەڵاتی خاوەن سیستەم نادات.',
):
    if marker not in main:
        fail(f'lib/main.dart: User owner-isolation marker missing: {marker}')
"""
verify_anchor = '\nif violations:\n'
if guard not in verify:
    if verify_anchor not in verify:
        raise SystemExit('Verifier final anchor not found')
    verify = verify.replace(verify_anchor, guard + verify_anchor, 1)

main_path.write_text(main, encoding='utf-8')
verify_path.write_text(verify, encoding='utf-8')
print('User Owner-app isolation applied.')
