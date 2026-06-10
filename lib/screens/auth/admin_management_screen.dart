import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen>
    with TickerProviderStateMixin {
  final List<Map<String, dynamic>> _admins = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  int _totalItems = 0;
  int _totalPages = 1;

  late AnimationController _headerAnimController;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _headerFade = CurvedAnimation(
      parent: _headerAnimController,
      curve: Curves.easeOut,
    );
    _scrollController.addListener(_onScroll);
    _loadAdmins();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _headerAnimController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadAdmins() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
    });
    try {
      final data = await PBService.getAdminsPage(page: 1, perPage: 15);
      _admins.clear();
      _admins.addAll((data['admins'] as List).cast<Map<String, dynamic>>());
      _totalItems = data['totalItems'] as int;
      _totalPages = data['totalPages'] as int;
      _currentPage = 1;
      _headerAnimController.forward(from: 0);
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    setState(() => _isLoadingMore = true);
    try {
      final data = await PBService.getAdminsPage(
        page: _currentPage + 1,
        perPage: 15,
      );
      _admins.addAll((data['admins'] as List).cast<Map<String, dynamic>>());
      _currentPage = data['page'] as int;
      _totalPages = data['totalPages'] as int;
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }
    if (mounted) setState(() => _isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppDarkColors.background
          : const Color(0xFFF5F7FA),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          // ───── Gradient AppBar ─────
          SliverAppBar(
            expandedHeight: 160,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            title: const Text(
              'بەڕێوبردنی بەڕێوبەرەکان',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withOpacity(0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 16),
                    child: FadeTransition(
                      opacity: _headerFade,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Admin Count
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$_totalItems',
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        height: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'بەڕێوبەر',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withOpacity(0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              // Add Button
                              _buildAddButton(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ───── Refresh indicator area ─────
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_admins.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'هیچ بەڕێوەبەرێک نییە',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateAdminDialog(),
                      icon: const Icon(Icons.person_add_rounded),
                      label: const Text('بەڕێوەبەری نوێ زیاد بکە'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // ───── Admin Cards ─────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  return _AnimatedAdminCard(
                    index: index,
                    data: _admins[index],
                    isDark: isDark,
                    onRenew: (id) => _showRenewDialog(id),
                    onDelete: (id, name, count) =>
                        _showDeleteConfirm(id, name, count),
                  );
                }, childCount: _admins.length),
              ),
            ),

            // ───── Loading More Indicator ─────
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),

            // ───── Bottom spacing ─────
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Material(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _showCreateAdminDialog(),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.person_add_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'بەڕێوەبەری نوێ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== Dialogs ====================

  void _showCreateAdminDialog() {
    final marketCtrl = TextEditingController();
    final adminNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '30');
    final formKey = GlobalKey<FormState>();
    bool loading = false;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDark ? AppDarkColors.card : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_add_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'بەڕێوەبەری نوێ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? AppDarkColors.textPrimary : null,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildField(
                        marketCtrl,
                        'ناوی مارکێت',
                        Icons.store,
                        isDark: isDark,
                        hint: 'سوپەرمارکێتی ...',
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        adminNameCtrl,
                        'ناوی بەڕێوەبەر',
                        Icons.person,
                        isDark: isDark,
                        hint: 'ناوی خۆت...',
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        phoneCtrl,
                        'ژمارە مۆبایل',
                        Icons.phone_iphone,
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
                        Icons.lock_outline,
                        isDark: isDark,
                        obscureText: obscure,
                        isPassword: true,
                        isLtr: true,
                        onToggle: () =>
                            setDialogState(() => obscure = !obscure),
                        minLength: 8,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        confirmCtrl,
                        'دووبارەکردنەوەی وشەی نهێنی',
                        Icons.lock_outline,
                        isDark: isDark,
                        obscureText: obscure,
                        isLtr: true,
                        matchCtrl: passCtrl,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        daysCtrl,
                        'ماوەی بەشداری (ڕۆژ)',
                        Icons.timer,
                        isDark: isDark,
                        keyboardType: TextInputType.number,
                        isLtr: true,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => loading = true);
                          try {
                            final phone = phoneCtrl.text.trim();
                            final marketName = marketCtrl.text.trim();

                            // Check unique phone
                            final existingPhone = await PBService.pb
                                .collection('users')
                                .getList(
                                  filter: 'phone = "$phone"',
                                  perPage: 1,
                                );
                            if (existingPhone.items.isNotEmpty) {
                              setDialogState(() => loading = false);
                              if (mounted) {
                                AppHelpers.showSnackBar(
                                  context,
                                  'ئەم ژمارەیە پێشتر بەکارهێنراوە',
                                  isError: true,
                                );
                              }
                              return;
                            }

                            // Check unique market name
                            final existingMarket = await PBService.pb
                                .collection('users')
                                .getList(
                                  filter:
                                      'role = "admin" && market_name = "$marketName"',
                                  perPage: 1,
                                );
                            if (existingMarket.items.isNotEmpty) {
                              setDialogState(() => loading = false);
                              if (mounted) {
                                AppHelpers.showSnackBar(
                                  context,
                                  'ئەم ناوەی مارکێتە پێشتر بەکارهێنراوە',
                                  isError: true,
                                );
                              }
                              return;
                            }

                            await PBService.registerAdmin(
                              marketName: marketName,
                              adminName: adminNameCtrl.text.trim(),
                              phone: phone,
                              password: passCtrl.text,
                              subscriptionDays: int.parse(daysCtrl.text.trim()),
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              AppHelpers.showSnackBar(
                                context,
                                'بەڕێوەبەر بە سەرکەوتوویی تۆمارکرا!',
                              );
                              _loadAdmins();
                            }
                          } catch (e) {
                            setDialogState(() => loading = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'هەڵە: $e',
                                isError: true,
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('تۆمارکردن'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRenewDialog(String adminId) {
    final daysCtrl = TextEditingController(text: '30');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppDarkColors.card : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'نوێکردنەوەی بەشداری',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppDarkColors.textPrimary : null,
                ),
              ),
              content: _buildField(
                daysCtrl,
                'ماوەی نوێ (ڕۆژ)',
                Icons.timer,
                isDark: isDark,
                keyboardType: TextInputType.number,
                isLtr: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final days = int.tryParse(daysCtrl.text.trim()) ?? 30;
                          setDialogState(() => loading = true);
                          try {
                            await PBService.renewAdminSubscription(
                              adminId,
                              days,
                            );
                            if (mounted) {
                              Navigator.pop(ctx);
                              AppHelpers.showSnackBar(
                                context,
                                'بەشداری نوێکرایەوە!',
                              );
                              _loadAdmins();
                            }
                          } catch (e) {
                            setDialogState(() => loading = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'هەڵە: $e',
                                isError: true,
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('نوێکردنەوە'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirm(String adminId, String marketName, int totalUsers) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppDarkColors.card : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سڕینەوەی $marketName',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? AppDarkColors.textPrimary : null,
                      ),
                    ),
                  ),
                ],
              ),
              content: Text(
                'ئایا دڵنیایت لە سڕینەوەی ئەم بەڕێوەبەرە؟\n\n'
                'هەموو داتاکان دەسڕێنەوە:\n'
                '• هەموو کارمەند و کڕیارەکان ($totalUsers یوزەر)\n'
                '• هەموو قەرزەکان\n'
                '• هەموو ئاگادارکردنەوەکان\n\n'
                '⚠️ ئەم کردارە ناگەڕێتەوە!',
                style: TextStyle(
                  color: isDark ? AppDarkColors.textSecondary : null,
                  height: 1.5,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('پاشگەزبوونەوە'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          setDialogState(() => loading = true);
                          try {
                            await PBService.deleteAdminWithData(adminId);
                            if (mounted) {
                              Navigator.pop(ctx);
                              AppHelpers.showSnackBar(
                                context,
                                'بەڕێوەبەر سڕایەوە',
                              );
                              _loadAdmins();
                            }
                          } catch (e) {
                            setDialogState(() => loading = false);
                            if (mounted) {
                              AppHelpers.showSnackBar(
                                context,
                                'هەڵە: $e',
                                isError: true,
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('سڕینەوە'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==================== Shared Field Builder ====================

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
        labelStyle: TextStyle(
          fontSize: 13,
          color: isDark ? AppDarkColors.textSecondary : null,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 13,
          color: isDark ? AppDarkColors.textSecondary : null,
        ),
        prefixIcon: Icon(
          icon,
          size: 20,
          color: AppColors.primary.withOpacity(0.7),
        ),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : Colors.grey[400],
                ),
                onPressed: onToggle,
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppDarkColors.cardBorder : Colors.grey[300]!,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? AppDarkColors.cardBorder : Colors.grey[300]!,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        filled: true,
        fillColor: isDark ? AppDarkColors.inputFill : Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        isDense: true,
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return '$label بنووسە';
        if (minLength != null && v.length < minLength) {
          return 'لانیکەم $minLength پیت';
        }
        if (matchCtrl != null && v != matchCtrl.text) {
          return 'وشەی نهێنی یەکناگرنەوە';
        }
        return null;
      },
    );
  }
}

// ==================== Animated Admin Card ====================

class _AnimatedAdminCard extends StatefulWidget {
  final int index;
  final Map<String, dynamic> data;
  final bool isDark;
  final Function(String) onRenew;
  final Function(String, String, int) onDelete;

  const _AnimatedAdminCard({
    required this.index,
    required this.data,
    required this.isDark,
    required this.onRenew,
    required this.onDelete,
  });

  @override
  State<_AnimatedAdminCard> createState() => _AnimatedAdminCardState();
}

class _AnimatedAdminCardState extends State<_AnimatedAdminCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Stagger the animation based on index
    Future.delayed(Duration(milliseconds: 60 * (widget.index % 10)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final admin = widget.data['admin'] as RecordModel;
    final empCount = widget.data['employeeCount'] as int;
    final custCount = widget.data['customerCount'] as int;
    final marketName = admin.getStringValue('market_name');
    final adminName = admin.getStringValue('name');
    final phone = admin.getStringValue('phone');
    final subEnd = admin.getStringValue('subscription_end');

    DateTime? endDate;
    int daysLeft = 9999;
    if (subEnd.isNotEmpty) {
      endDate = DateTime.parse(subEnd);
      daysLeft = endDate.difference(DateTime.now()).inDays;
    }

    Color statusColor;
    String statusText;
    IconData statusIcon;
    if (daysLeft < 0) {
      statusColor = Colors.red;
      statusText = 'تەواو بووە';
      statusIcon = Icons.error_outline;
    } else if (daysLeft <= 10) {
      statusColor = Colors.orange;
      statusText = '$daysLeft ڕۆژ ماوە';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = Colors.green;
      statusText = '$daysLeft ڕۆژ ماوە';
      statusIcon = Icons.check_circle_outline;
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: widget.isDark ? AppDarkColors.card : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isDark
                  ? AppDarkColors.cardBorder
                  : Colors.grey[200]!,
            ),
            boxShadow: widget.isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Market Name + Status
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withOpacity(0.15),
                            AppColors.primary.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.store_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            marketName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: widget.isDark
                                  ? AppDarkColors.textPrimary
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            adminName,
                            style: TextStyle(
                              fontSize: 13,
                              color: widget.isDark
                                  ? AppDarkColors.textSecondary
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                Divider(
                  color: widget.isDark
                      ? AppDarkColors.divider
                      : Colors.grey[200],
                  height: 1,
                ),
                const SizedBox(height: 12),

                // Stats Row
                Row(
                  children: [
                    _miniStat(Icons.phone, phone),
                    const SizedBox(width: 16),
                    _miniStat(Icons.people_outline, '$empCount کارمەند'),
                    const SizedBox(width: 16),
                    _miniStat(Icons.person_outline, '$custCount کڕیار'),
                  ],
                ),

                if (endDate != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: widget.isDark
                            ? AppDarkColors.textSecondary
                            : Colors.grey[500],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'کۆتایی بەشداری: ${DateFormat('yyyy/MM/dd').format(endDate)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark
                              ? AppDarkColors.textSecondary
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onRenew(admin.id),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('نوێکردنەوە'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onDelete(
                          admin.id,
                          marketName,
                          empCount + custCount,
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('سڕینەوە'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: widget.isDark ? AppDarkColors.textSecondary : Colors.grey[500],
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: widget.isDark
                ? AppDarkColors.textSecondary
                : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
