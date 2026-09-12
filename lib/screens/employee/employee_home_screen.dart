import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/widgets/app_design.dart';

class EmployeeHomeScreen extends StatelessWidget {
  const EmployeeHomeScreen({super.key, required this.onOpenCustomers});
  final VoidCallback onOpenCustomers;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permissions = <String>[
      if (auth.canAddCustomers) 'زیادکردنی کڕیار',
      if (auth.canAddDebts) 'زیادکردنی قەرز',
      if (auth.canEditDebts) 'دەستکاری قەرز',
      if (auth.canRecordPayments) 'تۆمارکردنی پارەدان',
      if (auth.canSendNotifications) 'ناردنی ئاگادارکردنەوە',
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.primarySoft,
                child: const Icon(Icons.badge_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('بەخێربێیتەوە', style: Theme.of(context)
                      .textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                  Text(auth.userFullName.isEmpty ? auth.userName : auth.userFullName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
                ],
              )),
            ]),
            const SizedBox(height: 24),
            const AppSectionHeader(
              title: 'کارەکانی ئەمڕۆ',
              subtitle: 'لە یەک شوێنەوە دەست بە کار بکە',
            ),
            const SizedBox(height: 10),
            AppSurface(child: Column(children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: AppColors.primarySoft,
                  child: Icon(Icons.people_rounded, color: AppColors.primary),
                ),
                title: const Text('کڕیارەکان', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('گەڕان، بینین و تۆمارکردنی مامەڵە'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: onOpenCustomers,
              ),
              if (auth.canAddCustomers) ...[
                const Divider(),
                FilledButton.icon(
                  onPressed: onOpenCustomers,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('زیادکردنی کڕیاری نوێ'),
                ),
              ],
            ])),
            const SizedBox(height: 22),
            const AppSectionHeader(
              title: 'دەسەڵاتە چالاکەکان',
              subtitle: 'لە لایەن بەڕێوەبەرەوە دیاری کراون',
            ),
            const SizedBox(height: 10),
            AppSurface(child: permissions.isEmpty
                ? const Text('هیچ دەسەڵاتێکی کرداریت پێ نەدراوە.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: permissions.map((value) => Chip(
                      avatar: const Icon(Icons.check_circle_outline, size: 17),
                      label: Text(value),
                    )).toList(),
                  )),
          ],
        ),
      ),
    );
  }
}
