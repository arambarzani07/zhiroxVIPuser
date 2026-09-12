import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/shared/user_profile_screen.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/widgets/app_design.dart';

class EmployeeSettingsScreen extends StatelessWidget {
  const EmployeeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('ڕێکخستنەکان', style: Theme.of(context)
                .textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(auth.marketName, style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            AppSurface(
              padding: EdgeInsets.zero,
              child: Column(children: [
                ListTile(
                  minTileHeight: 68,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(Icons.person_outline, color: AppColors.primary),
                  ),
                  title: const Text('پرۆفایل'),
                  subtitle: const Text('زانیاری هەژمار و وشەی نهێنی'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => UserProfileScreen(userId: auth.userId),
                  )),
                ),
                const Divider(height: 1),
                ListTile(
                  minTileHeight: 68,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primarySoft,
                    child: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                      color: AppColors.primary),
                  ),
                  title: Text(isDark ? 'دۆخی ڕووناک' : 'دۆخی تاریک'),
                  subtitle: const Text('گۆڕینی ڕەنگی ڕووکار'),
                  trailing: Switch(
                    value: isDark,
                    onChanged: (_) => context.read<ThemeProvider>().toggleTheme(),
                  ),
                  onTap: () => context.read<ThemeProvider>().toggleTheme(),
                ),
                const Divider(height: 1),
                ListTile(
                  minTileHeight: 68,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.danger.withValues(alpha: 0.10),
                    child: const Icon(Icons.logout, color: AppColors.danger),
                  ),
                  title: const Text('چوونەدەرەوە',
                    style: TextStyle(color: AppColors.danger)),
                  subtitle: const Text('دەرچوون لە هەژمار'),
                  onTap: () async {
                    final ok = await AppHelpers.showConfirmDialog(
                      context,
                      title: 'چوونەدەرەوە',
                      message: 'دڵنیایت لە چوونەدەرەوە؟',
                    );
                    if (ok && context.mounted) auth.logout();
                  },
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
