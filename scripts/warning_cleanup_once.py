from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')
lib = root / 'lib'

# Flutter 3.47 deprecates Color.withOpacity in favor of withValues(alpha: ...).
for path in lib.rglob('*.dart'):
    text = path.read_text(encoding='utf-8')
    updated = text.replace('.withOpacity(', '.withValues(alpha: ')
    if updated != text:
        path.write_text(updated, encoding='utf-8')

# Workmanager's isInDebugMode parameter is deprecated and has no effect.
main_path = lib / 'main.dart'
main = main_path.read_text(encoding='utf-8')
main = main.replace(
    'await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);',
    'await Workmanager().initialize(callbackDispatcher);',
)
main = main.replace(
    """            await auth.logout();
            if (mounted) {
              AppHelpers.showSnackBar(
                context,
                'ماوەی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بۆ نوێکردنەوە.',
                isError: true,
              );
            }
""",
    """            await auth.logout();
            if (!context.mounted) return;
            AppHelpers.showSnackBar(
              context,
              'ماوەی بەشداریت تەواو بووە. تکایە پەیوەندی بکە بۆ نوێکردنەوە.',
              isError: true,
            );
""",
)
main_path.write_text(main, encoding='utf-8')

# Remove a redundant non-null assertion already promoted by the null check.
admin_path = lib / 'screens/admin/admin_dashboard.dart'
admin = admin_path.read_text(encoding='utf-8')
admin = admin.replace('_stats = freshStats!;', '_stats = freshStats;')
admin_path.write_text(admin, encoding='utf-8')

# Future.wait already infers PBListResult for each entry; casts are unnecessary.
pb_path = lib / 'services/pb_service.dart'
pb = pb_path.read_text(encoding='utf-8')
for index, name in enumerate(('customers', 'debts', 'payments', 'pending', 'recent')):
    pb = pb.replace(
        f'final {name} = results[{index}] as PBListResult;',
        f'final {name} = results[{index}];',
    )
pb_path.write_text(pb, encoding='utf-8')

# Remove dead members left behind by earlier compact redesigns.
add_path = lib / 'screens/shared/add_debt_screen.dart'
add = add_path.read_text(encoding='utf-8')
start = add.find('\n  double get _totalAmount {')
end = add.find('\n  Future<void> _selectDate() async {', start)
if start != -1 and end != -1:
    add = add[:start] + add[end:]
add_path.write_text(add, encoding='utf-8')

user_list_path = lib / 'screens/shared/user_list_screen.dart'
user_list = user_list_path.read_text(encoding='utf-8')
start = user_list.find('\n  List<Color> _getAvatarGradient(')
end = user_list.find('\n  Future<void> _showPaymentDialog', start)
if start != -1 and end != -1:
    user_list = user_list[:start] + user_list[end:]
user_list = user_list.replace(
    """    } catch (e) {
      if (mounted) Navigator.pop(context); // Dismiss loading on error
      AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
    }
""",
    """    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading on error
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا پارەدانەوە ئامادە بکرێت. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
""",
)
user_list_path.write_text(user_list, encoding='utf-8')

profile_path = lib / 'screens/shared/user_profile_screen.dart'
profile = profile_path.read_text(encoding='utf-8')
start = profile.find('\n  Widget _buildAnimatedStatChip(')
end = profile.find('\n  Widget _buildTextField({', start)
if start != -1 and end != -1:
    profile = profile[:start] + profile[end:]

old_user_missing = """    if (_user == null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('بەکارهێنەر نەدۆزرایەوە')),
      );
    }
"""
new_user_missing = """    if (_loadError != null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.orange),
                const SizedBox(height: 12),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.6,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('دووبارە هەوڵ بدە'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('بەکارهێنەر نەدۆزرایەوە')),
      );
    }
"""
if old_user_missing in profile:
    profile = profile.replace(old_user_missing, new_user_missing, 1)
profile = profile.replace(
    "AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);",
    "AppHelpers.showSnackBar(context, AppHelpers.backendErrorMessage(e), isError: true);",
)
profile_path.write_text(profile, encoding='utf-8')

print('Warning cleanup patch applied.')
