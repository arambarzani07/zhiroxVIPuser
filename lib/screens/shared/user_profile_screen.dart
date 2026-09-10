import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/models/record_model.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

/// Customer-only profile for the end-user application.
///
/// Privileged employee/admin controls deliberately do not live in this binary.
/// Phone identity is shown read-only because changing it also requires changing
/// the Supabase Auth identity on the server.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _nameController = TextEditingController();
  RecordModel? _user;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool _isOwnCustomer(AuthProvider auth) {
    return auth.userRole == 'customer' &&
        auth.userId.isNotEmpty &&
        auth.userId == widget.userId;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (!_isOwnCustomer(auth)) {
      setState(() {
        _loading = false;
        _error = 'دەسەڵاتی بینینی ئەم پرۆفایلەت نییە';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await PBService.getUser(auth.userId);
      if (!mounted) return;
      if (user.id != auth.userId || user.getStringValue('role') != 'customer') {
        throw Exception('PROFILE_SCOPE_MISMATCH');
      }
      _nameController.text = user.getStringValue('name');
      setState(() {
        _user = user;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'پرۆفایل بار نەبوو. تکایە دووبارە هەوڵ بدەرەوە.';
      });
    }
  }

  Future<void> _saveName() async {
    final auth = context.read<AuthProvider>();
    if (!_isOwnCustomer(auth)) return;

    final name = _nameController.text.trim();
    if (name.length < 2) {
      AppHelpers.showSnackBar(context, 'ناوێکی دروست بنووسە', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await PBService.updateUser(auth.userId, {'name': name});
      await auth.refreshUser();
      await _load();
      if (mounted) {
        AppHelpers.showSnackBar(context, 'پرۆفایل نوێکرایەوە');
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, e.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final auth = context.read<AuthProvider>();
    if (!_isOwnCustomer(auth)) return;

    final oldController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    var obscureOld = true;
    var obscureNew = true;
    bool working = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !working,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> submit() async {
            final oldPassword = oldController.text;
            final newPassword = newController.text;
            final confirmPassword = confirmController.text;

            if (oldPassword.isEmpty) {
              AppHelpers.showSnackBar(
                context,
                'وشەی نهێنی ئێستا بنووسە',
                isError: true,
              );
              return;
            }
            if (newPassword.length < 8) {
              AppHelpers.showSnackBar(
                context,
                'وشەی نهێنی نوێ لانیکەم ٨ پیت بێت',
                isError: true,
              );
              return;
            }
            if (newPassword != confirmPassword) {
              AppHelpers.showSnackBar(
                context,
                'دوو وشەی نهێنییە نوێیەکە یەکسان نین',
                isError: true,
              );
              return;
            }

            setDialogState(() => working = true);
            try {
              await PBService.changePassword(
                userId: auth.userId,
                oldPassword: oldPassword,
                newPassword: newPassword,
              );
              if (!mounted) return;
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              AppHelpers.showSnackBar(context, 'وشەی نهێنی گۆڕدرا');
            } catch (e) {
              if (mounted) {
                AppHelpers.showSnackBar(context, e.toString(), isError: true);
              }
              if (dialogContext.mounted) {
                setDialogState(() => working = false);
              }
            }
          }

          return AlertDialog(
            title: const Text('گۆڕینی وشەی نهێنی'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: oldController,
                    obscureText: obscureOld,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'وشەی نهێنی ئێستا',
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscureOld = !obscureOld,
                        ),
                        icon: Icon(
                          obscureOld ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newController,
                    obscureText: obscureNew,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'وشەی نهێنی نوێ',
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                          () => obscureNew = !obscureNew,
                        ),
                        icon: Icon(
                          obscureNew ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: obscureNew,
                    onSubmitted: working ? null : (_) => submit(),
                    decoration: const InputDecoration(
                      labelText: 'دووبارەکردنەوەی وشەی نهێنی نوێ',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: working ? null : () => Navigator.pop(dialogContext),
                child: const Text('پاشگەزبوونەوە'),
              ),
              FilledButton(
                onPressed: working ? null : submit,
                child: working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('گۆڕین'),
              ),
            ],
          );
        },
      ),
    );

    oldController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  Future<void> _logout() async {
    final confirmed = await AppHelpers.showConfirmDialog(
      context,
      title: 'چوونەدەرەوە',
      message: 'دڵنیایت لە چوونەدەرەوە لە هەژمارەکەت؟',
    );
    if (!confirmed || !mounted) return;
    await context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!_isOwnCustomer(auth)) {
      return Scaffold(
        appBar: AppBar(title: const Text('پرۆفایل')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'ئەم بەشە تەنها بۆ هەژماری خۆت بەردەستە.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : AppColors.background,
      appBar: AppBar(
        title: const Text('پرۆفایل'),
        actions: [
          IconButton(
            tooltip: 'گۆڕینی ڕووکار',
            onPressed: () => context.read<ThemeProvider>().toggleTheme(),
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _ProfileHeader(user: _user!, auth: auth),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'زانیارییە سەرەکییەکان',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _nameController,
                                textInputAction: TextInputAction.done,
                                onSubmitted: _saving ? null : (_) => _saveName(),
                                decoration: const InputDecoration(
                                  labelText: 'ناو',
                                  prefixIcon: Icon(Icons.person_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: _user!.getStringValue('phone'),
                                readOnly: true,
                                decoration: const InputDecoration(
                                  labelText: 'ژمارە مۆبایل',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                  helperText:
                                      'گۆڕینی ژمارە پێویستی بە پشتگیری بەڕێوەبەر هەیە',
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _saving ? null : _saveName,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: const Text('پاشەکەوتکردن'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.lock_outline_rounded),
                              title: const Text('گۆڕینی وشەی نهێنی'),
                              subtitle: const Text(
                                'وشەی نهێنی لە Supabase Auth بە پارێزراوی دەگۆڕدرێت',
                              ),
                              trailing: const Icon(Icons.chevron_left_rounded),
                              onTap: _changePassword,
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(
                                Icons.logout_rounded,
                                color: AppColors.danger,
                              ),
                              title: const Text(
                                'چوونەدەرەوە',
                                style: TextStyle(color: AppColors.danger),
                              ),
                              onTap: _logout,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.auth});

  final RecordModel user;
  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    final fullName = [
      user.getStringValue('name'),
      user.getStringValue('father_name'),
      user.getStringValue('grandfather_name'),
    ].where((part) => part.trim().isNotEmpty).join(' ');
    final market = user.getStringValue('market_name').isNotEmpty
        ? user.getStringValue('market_name')
        : auth.marketName;
    final limit = user.getDoubleValue('debt_limit');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF673AB7)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.person_rounded,
              size: 38,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            fullName.isEmpty ? 'کڕیار' : fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (market.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              market,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 13,
              ),
            ),
          ],
          if (limit > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'سنوری قەرز: ${AppHelpers.formatCurrency(limit)}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 52),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('دووبارە هەوڵدانەوە'),
            ),
          ],
        ),
      ),
    );
  }
}
