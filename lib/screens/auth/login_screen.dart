import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/providers/theme_provider.dart';
import 'package:zhirox/screens/auth/register_customer_screen.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyLoginError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('network') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection')) {
      return 'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.';
    }
    if (raw.contains('invalid') ||
        raw.contains('credential') ||
        raw.contains('password') ||
        raw.contains('unauthorized')) {
      return 'ژمارە مۆبایل یان وشەی نهێنی هەڵەیە.';
    }
    if (raw.contains('locked') || raw.contains('too many')) {
      return 'هەوڵی زۆر دراوە. کەمێک چاوەڕێ بکە و دووبارە هەوڵ بدە.';
    }
    return 'نەتوانرا بچیتە ژوورەوە. دووبارە هەوڵ بدە.';
  }

  Future<void> _login() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    FocusScope.of(context).unfocus();
    try {
      await context.read<AuthProvider>().login(
        _phoneController.text.trim(),
        _passwordController.text,
      );
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(context, _friendlyLoginError(e), isError: true);
    }
  }

  void _openCustomerRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterCustomerScreen()),
    );
  }

  void _openAdminRegistration() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('هەژماری بەڕێوەبەر'),
        content: const Text(
          'بۆ دروستکردنی هەژماری بەڕێوەبەر، سەرەتا بە هەژماری خاوەن سیستەم بچۆ ژوورەوە. دوای چوونەژوورەوە، لە پەڕەی بەڕێوەبردنی بەڕێوەبەران هەژماری نوێ دروست بکە.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('باشە'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppDarkColors.card : Colors.white;
    final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
    final textPrimary = isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
    final textSecondary = isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Spacer(),
                  IconButton(
                    tooltip: isDark ? 'ڕووناک' : 'تاریک',
                    onPressed: auth.isLoading
                        ? null
                        : () => context.read<ThemeProvider>().toggleTheme(),
                    icon: Icon(
                      isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
                      size: 21,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                width: 68,
                                height: 68,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  color: Colors.white,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'ژیرۆکس',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 27,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'سیستەمی بەڕێوەبردنی قەرز',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textSecondary,
                              ),
                            ),
                            const SizedBox(height: 26),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'چوونەژوورەوە',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ژمارە مۆبایل و وشەی نهێنی هەژمارەکەت بنووسە.',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.5,
                                      color: textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _phoneController,
                                    enabled: !auth.isLoading,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [AutofillHints.telephoneNumber],
                                    textDirection: TextDirection.ltr,
                                    decoration: const InputDecoration(
                                      labelText: 'ژمارە مۆبایل',
                                      hintText: '07xxxxxxxxx',
                                      prefixIcon: Icon(Icons.phone_iphone_rounded),
                                    ),
                                    validator: (value) => value == null || value.trim().isEmpty
                                        ? 'ژمارە مۆبایل بنووسە'
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _passwordController,
                                    enabled: !auth.isLoading,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [AutofillHints.password],
                                    textDirection: TextDirection.ltr,
                                    onFieldSubmitted: (_) => _login(),
                                    decoration: InputDecoration(
                                      labelText: 'وشەی نهێنی',
                                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword ? 'نیشاندان' : 'شاردنەوە',
                                        onPressed: auth.isLoading
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
                                    validator: (value) => value == null || value.isEmpty
                                        ? 'وشەی نهێنی بنووسە'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: auth.isLoading ? null : _login,
                                      child: auth.isLoading
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Text(
                                              'چوونەژوورەوە',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: auth.isLoading ? null : _openAdminRegistration,
                              icon: const Icon(Icons.admin_panel_settings_outlined, size: 19),
                              label: const Text(
                                'دروستکردنی هەژماری بەڕێوەبەر',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                minimumSize: const Size(double.infinity, 46),
                                side: BorderSide(
                                  color: AppColors.primary.withValues(alpha: 0.30),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: auth.isLoading ? null : _openCustomerRegistration,
                              child: const Text(
                                'خۆتۆمارکردن وەک کڕیار',
                                style: TextStyle(fontWeight: FontWeight.w700),
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
          ],
        ),
      ),
    );
  }
}
