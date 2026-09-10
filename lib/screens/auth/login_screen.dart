import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Future<void> _launchExternal(String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      AppHelpers.showSnackBar(
        context,
        'نەتوانرا پەیوەندییەکە بکرێتەوە.',
        isError: true,
      );
    }
  }

  void _showOwnerContactDialog() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final surface = isDark ? AppDarkColors.card : Colors.white;
        final border = isDark ? AppDarkColors.cardBorder : const Color(0xFFEAECF0);
        final textPrimary = isDark ? AppDarkColors.textPrimary : const Color(0xFF1D2939);
        final textSecondary = isDark ? AppDarkColors.textSecondary : const Color(0xFF667085);

        Widget contactTile({
          required IconData icon,
          required String title,
          required String subtitle,
          required String url,
        }) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.pop(sheetContext);
                _launchExternal(url);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, size: 19, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontSize: 11.5, color: textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: textSecondary),
                  ],
                ),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
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
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'هەژماری بەڕێوەبەر',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            'تەنها لەلایەن خاوەن سیستەمەوە درووست دەکرێت.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.45,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      contactTile(
                        icon: Icons.chat_outlined,
                        title: 'واتس ئەپ',
                        subtitle: '0750 371 3171',
                        url: 'https://wa.me/9647503713171',
                      ),
                      Divider(height: 1, indent: 58, color: border),
                      contactTile(
                        icon: Icons.video_library_outlined,
                        title: 'تیکتۆک',
                        subtitle: '@zhiroxdebt',
                        url: 'https://www.tiktok.com/@zhiroxdebt',
                      ),
                      Divider(height: 1, indent: 58, color: border),
                      contactTile(
                        icon: Icons.camera_alt_outlined,
                        title: 'سناپ چات',
                        subtitle: '@aram.barzani00',
                        url: 'https://www.snapchat.com/add/aram.barzani00',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                              onPressed: auth.isLoading ? null : _showOwnerContactDialog,
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
