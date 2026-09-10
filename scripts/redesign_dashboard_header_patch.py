from pathlib import Path

path = Path('lib/screens/admin/admin_dashboard.dart')
text = path.read_text()

# 1) Replace the crowded dashboard top bar with one settings entry.
start = text.index('                    // Top Bar')
end = text.index('                    // Welcome - Tappable for profile menu', start)
new_top = r'''                    // Compact top bar: secondary actions live in Settings.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Row(
                        children: [
                          Text(
                            AppStrings.appName,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showAdminProfileMenu(auth),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.16),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.tune_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

'''
text = text[:start] + new_top + text[end:]

# 2) Tighten the welcome/stats area so the header does not dominate the screen.
text = text.replace(
    'padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),',
    'padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),',
    1,
)
text = text.replace(
    'padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),',
    'padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),',
    1,
)

# 3) Replace Settings bottom sheet and add report action there.
start = text.index('  void _showAdminProfileMenu(AuthProvider auth)')
end = text.index('  void _showChangePhoneDialog(AuthProvider auth)', start)
settings_block = r'''  void _showAdminProfileMenu(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final marketName = auth.user?.getStringValue('market_name') ?? AppStrings.appName;
    final phone = auth.user?.getStringValue('phone') ?? 'نەدراوە';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.82,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppDarkColors.card : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isDark ? AppDarkColors.cardBorder : Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                        size: 23,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            marketName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            phone,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppDarkColors.textSecondary
                                  : Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'ڕێکخستنەکان',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.summarize_outlined,
                  iconColor: AppColors.primary,
                  title: 'کەشفی حیساب و ڕاپۆرت',
                  subtitle: 'ڕاپۆرتی قەرز و پارەدانەوە چاپ بکە',
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_showReportMenu(auth));
                  },
                ),
                _settingsTile(
                  isDark: isDark,
                  icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  iconColor: Colors.indigo,
                  title: isDark ? 'ڕووناکی' : 'دۆخی تاریک',
                  subtitle: 'ڕووکار و ڕەنگی ئەپ بگۆڕە',
                  onTap: () {
                    Navigator.pop(ctx);
                    context.read<ThemeProvider>().toggleTheme();
                  },
                ),
                const Divider(height: 24),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.phone_android_rounded,
                  iconColor: Colors.blue,
                  title: 'گۆڕینی ژمارە مۆبایل',
                  subtitle: phone,
                  ltrSubtitle: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChangePhoneDialog(auth);
                  },
                ),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.lock_outline_rounded,
                  iconColor: Colors.orange,
                  title: 'گۆڕینی وشەی نهێنی',
                  subtitle: 'وشەی نهێنیی نوێ دابنێ',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showChangePasswordDialog(auth);
                  },
                ),
                const Divider(height: 24),
                _settingsTile(
                  isDark: isDark,
                  icon: Icons.logout_rounded,
                  iconColor: Colors.red,
                  title: AppStrings.logout,
                  subtitle: 'لە هەژمارەکەت بچۆ دەرەوە',
                  destructive: true,
                  showChevron: false,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await AppHelpers.showConfirmDialog(
                      context,
                      title: AppStrings.logout,
                      message: 'دڵنیایت لە چوونەدەرەوە؟',
                    );
                    if (confirm && mounted) auth.logout();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsTile({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
    bool showChevron = true,
    bool ltrSubtitle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: destructive
                              ? Colors.red
                              : isDark
                                  ? AppDarkColors.textPrimary
                                  : const Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        textDirection:
                            ltrSubtitle ? TextDirection.ltr : TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppDarkColors.textSecondary
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                if (showChevron)
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: isDark ? Colors.grey[600] : Colors.grey[350],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showReportMenu(AuthProvider auth) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).brightness == Brightness.dark
                ? AppDarkColors.card
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'کەشفی حیساب',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Icon(Icons.select_all_rounded, color: AppColors.primary),
                title: const Text(
                  'هەموو ماوەکان',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('ڕاپۆرتی تەواوی قەرزەکان'),
                onTap: () => Navigator.pop(ctx, 'all'),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.date_range_rounded, color: Colors.orange),
                title: const Text(
                  'دیاریکردنی بەروار',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('لە بەروارێکەوە تا بەروارێکی تر'),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    DateTime? fromDate;
    DateTime? toDate;
    String? dateFilter;
    if (choice == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: now,
        initialDateRange: DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        ),
      );
      if (picked == null || !mounted) return;
      fromDate = picked.start;
      toDate = picked.end;
      final fromStr = DateFormat('yyyy-MM-dd').format(fromDate);
      final toStr = DateFormat(
        'yyyy-MM-dd',
      ).format(toDate.add(const Duration(days: 1)));
      dateFilter =
          'created >= "$fromStr 00:00:00" && created <= "$toStr 00:00:00"';
    }

    try {
      final allDebts = await PBService.getDebts(
        adminId: auth.userId,
        filter: dateFilter,
      );
      double reportDebt = 0;
      double reportRemaining = 0;
      double reportPaid = 0;
      final customerIds = <String>{};
      for (final debt in allDebts) {
        final amount = debt.getDoubleValue('amount');
        final remaining = debt.getDoubleValue('remaining');
        reportDebt += amount;
        reportRemaining += remaining;
        reportPaid += amount - remaining;
        customerIds.add(debt.getStringValue('customer'));
      }
      await PdfService.generateAdminReport(
        allDebts: allDebts,
        marketName: AppStrings.appName,
        adminName: auth.userName,
        adminPhone: auth.user?.getStringValue('phone') ?? '',
        totalDebt: reportDebt,
        totalRemaining: reportRemaining,
        totalPaid: reportPaid,
        totalCustomers: customerIds.length,
        fromDate: fromDate,
        toDate: toDate,
      );
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'نەتوانرا ڕاپۆرت دروست بکرێت',
          isError: true,
        );
      }
    }
  }

'''
text = text[:start] + settings_block + text[end:]

# 4) Make all four statistics cards compact and visually equal.
start = text.index('  Widget _buildHeaderStat(')
end = text.index('  Widget _buildActivityCard(', start)
stat_block = r'''  Widget _buildHeaderStat(
    IconData icon,
    String label,
    double value,
    bool isCurrency,
  ) {
    return Expanded(
      child: Container(
        height: 82,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withOpacity(0.14)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isCurrency
                        ? AppHelpers.formatCurrency(value)
                        : value.toInt().toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

'''
text = text[:start] + stat_block + text[end:]

path.write_text(text)
