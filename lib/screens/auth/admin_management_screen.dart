import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class _SubscriptionPlan {
  const _SubscriptionPlan(this.code, this.label, this.days);

  final String code;
  final String label;
  final int? days;
}

const _subscriptionPlans = <_SubscriptionPlan>[
  _SubscriptionPlan('monthly', 'مانگانە — ٣٠ ڕۆژ', 30),
  _SubscriptionPlan('quarterly', '٣ مانگ — ٩٠ ڕۆژ', 90),
  _SubscriptionPlan('semiannual', '٦ مانگ — ١٨٠ ڕۆژ', 180),
  _SubscriptionPlan('annual', 'ساڵانە — ٣٦٥ ڕۆژ', 365),
  _SubscriptionPlan('custom', 'ماوەی تایبەت', null),
];

String _subscriptionPlanLabel(String code) {
  for (final plan in _subscriptionPlans) {
    if (plan.code == code) return plan.label;
  }
  return 'ماوەی تایبەت';
}

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  final List<Map<String, dynamic>> _admins = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _loadInFlight = false;
  String? _loadError;
  int _currentPage = 1;
  int _totalItems = 0;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadAdmins();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _friendlyError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network') ||
        raw.contains('connection')) {
      return 'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.';
    }
    if (raw.contains('system_owner_required') ||
        raw.contains('forbidden') ||
        raw.contains('unauthorized') ||
        raw.contains('permission')) {
      return 'تەنها خاوەن سیستەم دەسەڵاتی ئەم کردارەی هەیە.';
    }
    if (raw.contains('market_exists') ||
        (raw.contains('market') && raw.contains('already'))) {
      return 'ئەم ناوی مارکێتە پێشتر تۆمارکراوە.';
    }
    if (raw.contains('phone_exists') ||
        (raw.contains('phone') &&
            (raw.contains('already') || raw.contains('unique')))) {
      return 'ئەم ژمارە مۆبایلە پێشتر تۆمارکراوە.';
    }
    return 'کردارەکە سەرکەوتوو نەبوو. دووبارە هەوڵ بدە.';
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadAdmins() async {
    if (!mounted || _loadInFlight || _isLoadingMore) return;
    _loadInFlight = true;

    if (_admins.isEmpty) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    } else {
      setState(() => _loadError = null);
    }

    try {
      final data = await PBService.getAdminsPage(page: 1, perPage: 15);
      if (!mounted) return;
      final items = (data['admins'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _admins
          ..clear()
          ..addAll(items);
        _totalItems = data['totalItems'] as int;
        _totalPages = data['totalPages'] as int;
        _currentPage = 1;
        _isLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (_admins.isEmpty) _loadError = _friendlyError(e);
      });
      if (_admins.isNotEmpty) {
        AppHelpers.showSnackBar(context, _friendlyError(e), isError: true);
      }
    } finally {
      _loadInFlight = false;
    }
  }

  Future<void> _loadMore() async {
    if (!mounted ||
        _loadInFlight ||
        _isLoadingMore ||
        _currentPage >= _totalPages) {
      return;
    }

    _loadInFlight = true;
    setState(() => _isLoadingMore = true);
    try {
      final data = await PBService.getAdminsPage(
        page: _currentPage + 1,
        perPage: 15,
      );
      if (!mounted) return;
      final items = (data['admins'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _admins.addAll(items);
        _currentPage = data['page'] as int;
        _totalPages = data['totalPages'] as int;
      });
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, _friendlyError(e), isError: true);
      }
    } finally {
      _loadInFlight = false;
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final textPrimary =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Scaffold(
      backgroundColor:
          isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'بەڕێوەبردنی بەڕێوەبەران',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            if (!_isLoading)
              Text(
                '$_totalItems بەڕێوەبەر',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                ),
              ),
          ],
        ),
        backgroundColor: isDark ? AppDarkColors.surface : Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: border),
        ),
        actions: [
          IconButton(
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAdmins,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: AppColors.primary,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'هەژمار و بەشداری',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'دۆخ، ماوەی بەشداری و ژمارەی بەکارهێنەران لە یەک شوێن',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.45,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$_totalItems',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoading && _admins.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null && _admins.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ErrorState(
                  message: _loadError!,
                  onRetry: _loadAdmins,
                  isDark: isDark,
                ),
              )
            else if (_admins.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  isDark: isDark,
                  onAdd: _showCreateAdminDialog,
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _AdminCard(
                      data: _admins[index],
                      isDark: isDark,
                      onRenew: _showRenewDialog,
                      onDelete: _showDeleteConfirm,
                    ),
                    childCount: _admins.length,
                  ),
                ),
              ),
              if (_isLoadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateAdminDialog() async {
    final marketCtrl = TextEditingController();
    final adminNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '30');
    final formKey = GlobalKey<FormState>();
    bool loading = false;
    bool obscure = true;
    String selectedPlan = 'monthly';

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            final textSecondary = isDark
                ? AppDarkColors.textSecondary
                : const Color(0xFF667085);
            return AlertDialog(
              backgroundColor: isDark ? AppDarkColors.card : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'بەڕێوەبەری نوێ',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'زانیاری مارکێت',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 9),
                        _buildField(
                          marketCtrl,
                          'ناوی مارکێت',
                          Icons.store_outlined,
                          isDark: isDark,
                          hint: 'سوپەرمارکێتی ...',
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          adminNameCtrl,
                          'ناوی بەڕێوەبەر',
                          Icons.person_outline_rounded,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'زانیاری چوونەژوورەوە',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 9),
                        _buildField(
                          phoneCtrl,
                          'ژمارە مۆبایل',
                          Icons.phone_iphone_rounded,
                          isDark: isDark,
                          hint: '07xxxxxxxxx',
                          keyboardType: TextInputType.phone,
                          isLtr: true,
                          minLength: 7,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          passCtrl,
                          'وشەی نهێنی',
                          Icons.lock_outline_rounded,
                          isDark: isDark,
                          obscureText: obscure,
                          isPassword: true,
                          isLtr: true,
                          onToggle: () {
                            if (ctx.mounted) {
                              setDialogState(() => obscure = !obscure);
                            }
                          },
                          minLength: 8,
                        ),
                        const SizedBox(height: 12),
                        _buildField(
                          confirmCtrl,
                          'دووبارەکردنەوەی وشەی نهێنی',
                          Icons.lock_reset_rounded,
                          isDark: isDark,
                          obscureText: obscure,
                          isLtr: true,
                          matchCtrl: passCtrl,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'بەشداری',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 9),
                        DropdownButtonFormField<String>(
                          initialValue: selectedPlan,
                          decoration: const InputDecoration(
                            labelText: 'پلانی بەشداری',
                            prefixIcon: Icon(Icons.workspace_premium_outlined),
                          ),
                          items: _subscriptionPlans
                              .map(
                                (plan) => DropdownMenuItem(
                                  value: plan.code,
                                  child: Text(plan.label),
                                ),
                              )
                              .toList(),
                          onChanged: loading
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  final plan = _subscriptionPlans.firstWhere(
                                    (item) => item.code == value,
                                  );
                                  setDialogState(() => selectedPlan = value);
                                  if (plan.days != null) {
                                    daysCtrl.text = plan.days.toString();
                                  }
                                },
                        ),
                        if (selectedPlan == 'custom') ...[
                          const SizedBox(height: 12),
                          _buildField(
                            daysCtrl,
                            'ماوەی بەشداری (ڕۆژ)',
                            Icons.event_available_outlined,
                            isDark: isDark,
                            keyboardType: TextInputType.number,
                            isLtr: true,
                            validator: (value) {
                              final days = int.tryParse(value?.trim() ?? '');
                              if (days == null || days < 1 || days > 3650) {
                                return 'ماوە دەبێت لە ١ تا ٣٦٥٠ ڕۆژ بێت';
                              }
                              return null;
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final form = formKey.currentState;
                          if (form == null || !form.validate()) return;
                          FocusScope.of(ctx).unfocus();
                          setDialogState(() => loading = true);
                          try {
                            await PBService.registerAdmin(
                              marketName: marketCtrl.text.trim(),
                              adminName: adminNameCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              password: passCtrl.text,
                              subscriptionPlan: selectedPlan,
                              subscriptionDays:
                                  int.parse(daysCtrl.text.trim()),
                            );
                            if (!ctx.mounted || !mounted) return;
                            Navigator.pop(ctx);
                            AppHelpers.showSnackBar(
                              context,
                              'بەڕێوەبەر بە سەرکەوتوویی تۆمارکرا.',
                            );
                            await _loadAdmins();
                          } catch (e) {
                            if (ctx.mounted) {
                              setDialogState(() => loading = false);
                            }
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                _friendlyError(e),
                                isError: true,
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('تۆمارکردن'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      marketCtrl.dispose();
      adminNameCtrl.dispose();
      phoneCtrl.dispose();
      passCtrl.dispose();
      confirmCtrl.dispose();
      daysCtrl.dispose();
    }
  }

  Future<void> _showRenewDialog(String adminId, String currentPlan) async {
    final hasCurrentPlan = _subscriptionPlans.any(
      (plan) => plan.code == currentPlan,
    );
    final selectedCurrentPlan = hasCurrentPlan ? currentPlan : 'custom';
    final currentPlanDays = _subscriptionPlans
        .firstWhere((plan) => plan.code == selectedCurrentPlan)
        .days;
    final daysCtrl = TextEditingController(
      text: (currentPlanDays ?? 30).toString(),
    );
    final formKey = GlobalKey<FormState>();
    bool loading = false;
    String selectedPlan = selectedCurrentPlan;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppDarkColors.card : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: const Text(
                'نوێکردنەوەی بەشداری',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedPlan,
                      decoration: const InputDecoration(
                        labelText: 'پلانی بەشداری',
                        prefixIcon: Icon(Icons.workspace_premium_outlined),
                      ),
                      items: _subscriptionPlans
                          .map(
                            (plan) => DropdownMenuItem(
                              value: plan.code,
                              child: Text(plan.label),
                            ),
                          )
                          .toList(),
                      onChanged: loading
                          ? null
                          : (value) {
                              if (value == null) return;
                              final plan = _subscriptionPlans.firstWhere(
                                (item) => item.code == value,
                              );
                              setDialogState(() => selectedPlan = value);
                              if (plan.days != null) {
                                daysCtrl.text = plan.days.toString();
                              }
                            },
                    ),
                    if (selectedPlan == 'custom') ...[
                      const SizedBox(height: 12),
                      _buildField(
                        daysCtrl,
                        'ژمارەی ڕۆژ',
                        Icons.event_repeat_rounded,
                        isDark: isDark,
                        keyboardType: TextInputType.number,
                        isLtr: true,
                        validator: (value) {
                          final days = int.tryParse(value?.trim() ?? '');
                          if (days == null || days < 1 || days > 3650) {
                            return 'ماوە دەبێت لە ١ تا ٣٦٥٠ ڕۆژ بێت';
                          }
                          return null;
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final form = formKey.currentState;
                          if (form == null || !form.validate()) return;
                          final days = int.parse(daysCtrl.text.trim());
                          setDialogState(() => loading = true);
                          try {
                            await PBService.renewAdminSubscription(
                              adminId,
                              selectedPlan,
                              days,
                            );
                            if (!ctx.mounted || !mounted) return;
                            Navigator.pop(ctx);
                            AppHelpers.showSnackBar(
                              context,
                              'بەشداری نوێکرایەوە.',
                            );
                            await _loadAdmins();
                          } catch (e) {
                            if (ctx.mounted) {
                              setDialogState(() => loading = false);
                            }
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                _friendlyError(e),
                                isError: true,
                              );
                            }
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('نوێکردنەوە'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      daysCtrl.dispose();
    }
  }

  Future<void> _showDeleteConfirm(
    String adminId,
    String marketName,
    int totalUsers,
  ) async {
    bool loading = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final textSecondary = isDark
              ? AppDarkColors.textSecondary
              : const Color(0xFF667085);
          return AlertDialog(
            backgroundColor: isDark ? AppDarkColors.card : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                  size: 22,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'سڕینەوەی $marketName',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              'هەموو داتای پەیوەست بە ئەم مارکێتە دەسڕێتەوە، لەوانە $totalUsers کارمەند/کڕیار، قەرزەکان و ئاگادارکردنەوەکان. ئەم کردارە ناگەڕێتەوە.',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('پاشگەزبوونەوە'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: loading
                    ? null
                    : () async {
                        setDialogState(() => loading = true);
                        try {
                          await PBService.deleteAdminWithData(adminId);
                          if (!ctx.mounted || !mounted) return;
                          Navigator.pop(ctx);
                          AppHelpers.showSnackBar(
                            context,
                            'بەڕێوەبەر و داتاکانی سڕانەوە.',
                          );
                          await _loadAdmins();
                        } catch (e) {
                          if (ctx.mounted) {
                            setDialogState(() => loading = false);
                          }
                          if (mounted) {
                            AppHelpers.showSnackBar(
                              context,
                              _friendlyError(e),
                              isError: true,
                            );
                          }
                        }
                      },
                child: loading
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('سڕینەوە'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    required bool isDark,
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
    bool isPassword = false,
    bool isLtr = false,
    VoidCallback? onToggle,
    int? minLength,
    TextEditingController? matchCtrl,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textDirection: isLtr ? TextDirection.ltr : null,
      textAlign: isLtr ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontSize: 14,
        color: isDark ? AppDarkColors.textPrimary : null,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 19),
        suffixIcon: isPassword
            ? IconButton(
                onPressed: onToggle,
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
              )
            : null,
      ),
      validator: validator ??
          (value) {
            if (value == null || value.trim().isEmpty) {
              return '$label بنووسە';
            }
            if (minLength != null && value.length < minLength) {
              return 'لانیکەم $minLength پیت';
            }
            if (matchCtrl != null && value != matchCtrl.text) {
              return 'وشەی نهێنی یەکناگرنەوە';
            }
            return null;
          },
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.data,
    required this.isDark,
    required this.onRenew,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final bool isDark;
  final void Function(String, String) onRenew;
  final void Function(String, String, int) onDelete;

  @override
  Widget build(BuildContext context) {
    final admin = data['admin'] as RecordModel;
    final employeeCount = data['employeeCount'] as int;
    final customerCount = data['customerCount'] as int;
    final marketName = admin.getStringValue('market_name');
    final adminName = admin.getStringValue('name');
    final phone = admin.getStringValue('phone');
    final subscriptionEnd = admin.getStringValue('subscription_end');
    final subscriptionPlan = admin.getStringValue('subscription_plan');
    final endDate = DateTime.tryParse(subscriptionEnd);

    final status = _subscriptionStatus(endDate);
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final textPrimary =
        isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: AppColors.primary,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        marketName.isEmpty ? 'مارکێت' : marketName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        adminName.isEmpty ? phone : '$adminName • $phone',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 11,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: status.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        status.label,
                        style: TextStyle(
                          color: status.color,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'کردارەکان',
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    size: 21,
                    color: textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'renew') {
                      onRenew(
                        admin.id,
                        subscriptionPlan.isEmpty ? 'custom' : subscriptionPlan,
                      );
                    } else if (value == 'delete') {
                      onDelete(
                        admin.id,
                        marketName,
                        employeeCount + customerCount,
                      );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'renew',
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_repeat_rounded,
                            size: 19,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 10),
                          Text('نوێکردنەوەی بەشداری'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: Colors.red,
                          ),
                          SizedBox(width: 10),
                          Text('سڕینەوە'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: border),
            const SizedBox(height: 9),
            Wrap(
              spacing: 14,
              runSpacing: 7,
              children: [
                _meta(
                  Icons.badge_outlined,
                  '$employeeCount کارمەند',
                  textSecondary,
                ),
                _meta(
                  Icons.people_outline_rounded,
                  '$customerCount کڕیار',
                  textSecondary,
                ),
                _meta(
                  Icons.workspace_premium_outlined,
                  _subscriptionPlanLabel(subscriptionPlan),
                  textSecondary,
                ),
                _meta(
                  Icons.event_outlined,
                  endDate == null
                      ? 'کۆتایی: دیاری نەکراوە'
                      : 'کۆتایی: ${DateFormat('yyyy/MM/dd').format(endDate.toLocal())}',
                  textSecondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  _SubscriptionStatus _subscriptionStatus(DateTime? endDate) {
    if (endDate == null) {
      return const _SubscriptionStatus(
        label: 'بەروار نییە',
        color: Colors.grey,
      );
    }
    final remaining = endDate.difference(DateTime.now()).inDays;
    if (remaining < 0) {
      return const _SubscriptionStatus(
        label: 'تەواو بووە',
        color: Colors.red,
      );
    }
    if (remaining <= 10) {
      return _SubscriptionStatus(
        label: '$remaining ڕۆژ',
        color: Colors.orange,
      );
    }
    return _SubscriptionStatus(
      label: '$remaining ڕۆژ',
      color: Colors.green,
    );
  }
}

class _SubscriptionStatus {
  const _SubscriptionStatus({required this.label, required this.color});

  final String label;
  final Color color;
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
    required this.isDark,
  });

  final String message;
  final VoidCallback onRetry;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Colors.orange,
                size: 25,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: textSecondary, height: 1.5),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('دووبارە هەوڵ بدە'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isDark, required this.onAdd});

  final bool isDark;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final textSecondary =
        isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.admin_panel_settings_outlined,
                color: AppColors.primary,
                size: 25,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'هیچ بەڕێوەبەرێک نییە',
              style: TextStyle(
                color: textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('بەڕێوەبەری نوێ'),
            ),
          ],
        ),
      ),
    );
  }
}
