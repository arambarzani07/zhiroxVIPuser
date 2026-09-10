import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class RegisterAdminScreen extends StatefulWidget {
  const RegisterAdminScreen({super.key});

  @override
  State<RegisterAdminScreen> createState() => _RegisterAdminScreenState();
}

class _RegisterAdminScreenState extends State<RegisterAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ownerPhoneController = TextEditingController();
  final _ownerPasswordController = TextEditingController();
  final _marketNameController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscureOwnerPassword = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _ownerPhoneController.dispose();
    _ownerPasswordController.dispose();
    _marketNameController.dispose();
    _adminNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _friendlyRegistrationError(Object error) {
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('socketexception') ||
        normalized.contains('clientexception') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('connection refused') ||
        normalized.contains('network')) {
      return 'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.';
    }
    if (normalized.contains('system_owner_required') ||
        normalized.contains('invalid login') ||
        normalized.contains('invalid credentials') ||
        normalized.contains('authapierror')) {
      return 'زانیاری پشتڕاستکردنەوەی خاوەن سیستەم دروست نییە یان دەسەڵاتی پێویست نییە.';
    }
    if (normalized.contains('market_exists') ||
        normalized.contains('market already exists')) {
      return 'ئەم ناوی مارکێتە پێشتر تۆمارکراوە.';
    }
    if (normalized.contains('phone_exists') ||
        normalized.contains('already') ||
        normalized.contains('unique')) {
      return 'ئەم ژمارە مۆبایلە پێشتر تۆمارکراوە.';
    }
    if (normalized.contains('invalid_input')) {
      return 'زانیارییەکان تەواو یان دروست نین.';
    }
    return 'نەتوانرا هەژماری بەڕێوەبەر درووست بکرێت. دووبارە هەوڵ بدە.';
  }

  Future<void> _register() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    final ownerClient = SupabaseClient(
      SupabaseConfig.url,
      SupabaseConfig.publishableKey,
    );

    try {
      final ownerPhone = _ownerPhoneController.text.trim();
      final ownerLogin = await ownerClient.auth.signInWithPassword(
        email: '$ownerPhone@zhirox.local',
        password: _ownerPasswordController.text,
      );
      if (ownerLogin.user == null) {
        throw Exception('invalid credentials');
      }

      final response = await ownerClient.functions.invoke(
        'account-admin',
        body: {
          'action': 'create_user',
          'role': 'admin',
          'market_name': _marketNameController.text.trim(),
          'name': _adminNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'password': _passwordController.text,
          'subscription_days': 30,
        },
      );

      final data = response.data;
      if (data is! Map || data['user'] is! Map) {
        final code = data is Map ? data['error']?.toString() : data?.toString();
        throw Exception(code ?? 'admin creation failed');
      }

      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'هەژماری بەڕێوەبەر و مارکێتەکە بە سەرکەوتوویی درووست کرا.',
      );
      Navigator.pop(context);
    } on AuthException catch (_) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        'زانیاری پشتڕاستکردنەوەی خاوەن سیستەم هەڵەیە.',
        isError: true,
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        _friendlyRegistrationError(e),
        isError: true,
      );
    } finally {
      try {
        await ownerClient.auth.signOut();
      } catch (_) {}
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final textPrimary = isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary = isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    Widget section({
      required String title,
      required String subtitle,
      required IconData icon,
      required List<Widget> children,
      bool owner = false,
    }) {
      final accent = owner ? Colors.deepPurple : AppColors.primary;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                          ),
                          if (owner) ...[
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                'OWNER',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.45,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'دروستکردنی بەڕێوەبەر',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? AppDarkColors.surface : Colors.white,
        foregroundColor: textPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: border),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      section(
                        title: 'پشتڕاستکردنەوەی خاوەن سیستەم',
                        subtitle: 'ئەم بەشە تەنها بۆ پشتڕاستکردنەوەی دەسەڵاتی System Owner ـە.',
                        icon: Icons.verified_user_outlined,
                        owner: true,
                        children: [
                          TextFormField(
                            controller: _ownerPhoneController,
                            enabled: !_isLoading,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            textDirection: TextDirection.ltr,
                            decoration: _decoration(
                              label: 'ژمارە مۆبایلی خاوەن سیستەم',
                              icon: Icons.shield_outlined,
                              hint: '07xxxxxxxxx',
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'ژمارەی خاوەن سیستەم بنووسە'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _ownerPasswordController,
                            enabled: !_isLoading,
                            obscureText: _obscureOwnerPassword,
                            textInputAction: TextInputAction.next,
                            textDirection: TextDirection.ltr,
                            decoration: _decoration(
                              label: 'وشەی نهێنی خاوەن سیستەم',
                              icon: Icons.key_outlined,
                              suffix: IconButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(
                                          () => _obscureOwnerPassword = !_obscureOwnerPassword,
                                        ),
                                icon: Icon(
                                  _obscureOwnerPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value == null || value.isEmpty
                                ? 'وشەی نهێنی خاوەن سیستەم بنووسە'
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      section(
                        title: 'مارکێتی نوێ',
                        subtitle: 'ناوی بازرگانییەکە دیاری بکە؛ ئەم ناوە لە هەژمار و ڕاپۆرتەکاندا بەکاردێت.',
                        icon: Icons.storefront_outlined,
                        children: [
                          TextFormField(
                            controller: _marketNameController,
                            enabled: !_isLoading,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration(
                              label: AppStrings.marketName,
                              icon: Icons.store_outlined,
                              hint: 'ناوی مارکێتەکە',
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'ناوی مارکێت بنووسە'
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      section(
                        title: 'هەژماری بەڕێوەبەر',
                        subtitle: 'زانیاری بەڕێوەبەری سەرەکیی ئەم مارکێتە بنووسە.',
                        icon: Icons.admin_panel_settings_outlined,
                        children: [
                          TextFormField(
                            controller: _adminNameController,
                            enabled: !_isLoading,
                            textInputAction: TextInputAction.next,
                            decoration: _decoration(
                              label: 'ناوی بەڕێوەبەر',
                              icon: Icons.person_outline_rounded,
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'ناوی بەڕێوەبەر بنووسە'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            enabled: !_isLoading,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            textDirection: TextDirection.ltr,
                            autofillHints: const [AutofillHints.telephoneNumber],
                            decoration: _decoration(
                              label: AppStrings.phone,
                              icon: Icons.phone_iphone_rounded,
                              hint: '07xxxxxxxxx',
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'ژمارە مۆبایل بنووسە'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            enabled: !_isLoading,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            textDirection: TextDirection.ltr,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: _decoration(
                              label: 'وشەی نهێنی بەڕێوەبەر',
                              icon: Icons.lock_outline_rounded,
                              suffix: IconButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(
                                          () => _obscurePassword = !_obscurePassword,
                                        ),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'وشەی نهێنی بنووسە';
                              if (value.length < 8) return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPasswordController,
                            enabled: !_isLoading,
                            obscureText: _obscureConfirmPassword,
                            textInputAction: TextInputAction.done,
                            textDirection: TextDirection.ltr,
                            onFieldSubmitted: (_) => _register(),
                            decoration: _decoration(
                              label: 'دووبارەکردنەوەی وشەی نهێنی',
                              icon: Icons.lock_reset_outlined,
                              suffix: IconButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => setState(
                                          () => _obscureConfirmPassword = !_obscureConfirmPassword,
                                        ),
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (value) => value != _passwordController.text
                                ? 'وشەی نهێنی یەکناگرنەوە'
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _register,
                          icon: _isLoading
                              ? const SizedBox.shrink()
                              : const Icon(Icons.add_business_outlined, size: 19),
                          label: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'دروستکردنی هەژماری بەڕێوەبەر',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
