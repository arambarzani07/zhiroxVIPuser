import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class UserProfileScreenClean extends StatefulWidget {
  final String userId;

  const UserProfileScreenClean({super.key, required this.userId});

  @override
  State<UserProfileScreenClean> createState() => _UserProfileScreenCleanState();
}

class _UserProfileScreenCleanState extends State<UserProfileScreenClean> {
  RecordModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUser());
  }

  Future<void> _loadUser() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = await PBService.getUser(widget.userId);
      if (mounted) _user = user;
    } catch (_) {
      // No internal wording in user-facing UI.
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwnProfile = auth.userId == widget.userId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppDarkColors.card : Colors.white;
    final textColor = isDark ? AppDarkColors.textPrimary : AppColors.textPrimary;
    final subColor = isDark ? AppDarkColors.textSecondary : AppColors.textSecondary;

    final user = _user;
    final name = user?.getStringValue('name') ?? (isOwnProfile ? auth.userName : '');
    final role = user?.getStringValue('role') ?? (isOwnProfile ? auth.userRole : '');
    final phone = user?.getStringValue('phone') ?? '';
    final marketName = user?.getStringValue('market_name') ?? auth.marketName;
    final debtLimit = user?.getDoubleValue('debt_limit') ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
        body: RefreshIndicator(
          onRefresh: _loadUser,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primary.withOpacity(0.72)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.22),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(18)),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0] : 'ز',
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('هەژمار', style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(name.isEmpty ? 'بەکارهێنەر' : name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                            if (role.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(AppHelpers.roleName(role), style: TextStyle(color: Colors.white.withOpacity(0.76))),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
              else ...[
                _InfoCard(title: 'زانیاری گشتی', cardColor: cardColor, textColor: textColor, children: [
                  _InfoRow(label: 'ناو', value: name.isEmpty ? '—' : name, subColor: subColor),
                  _InfoRow(label: 'ڕۆڵ', value: role.isEmpty ? '—' : AppHelpers.roleName(role), subColor: subColor),
                  if (phone.isNotEmpty) _InfoRow(label: 'ژمارە مۆبایل', value: phone, subColor: subColor, ltr: true),
                  if (marketName.isNotEmpty) _InfoRow(label: 'مارکێت', value: marketName, subColor: subColor),
                  if (role == 'customer') _InfoRow(label: 'سنووری قەرز', value: debtLimit <= 0 ? 'بێ سنوور' : AppHelpers.formatCurrency(debtLimit), subColor: subColor, ltr: true),
                ]),
                const SizedBox(height: 16),
                if (isOwnProfile)
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await AppHelpers.showConfirmDialog(
                          context,
                          title: AppStrings.logout,
                          message: 'دڵنیایت لە چوونەدەرەوە؟',
                        );
                        if (confirm && context.mounted) {
                          await context.read<AuthProvider>().logout();
                        }
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text(AppStrings.logout),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Color cardColor;
  final Color textColor;
  final List<Widget> children;

  const _InfoCard({required this.title, required this.cardColor, required this.textColor, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color subColor;
  final bool ltr;

  const _InfoRow({required this.label, required this.value, required this.subColor, this.ltr = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: subColor, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.left,
              textDirection: ltr ? TextDirection.ltr : TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
