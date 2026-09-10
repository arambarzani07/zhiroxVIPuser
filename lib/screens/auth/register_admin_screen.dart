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
    final raw = error.toString();
    final normalized = raw.toLowerCase();

    if (normalized.contains('socketexception') ||
        normalized.contains('clientexception') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('connection refused') ||
        normalized.contains('network')) {
      return 'پەیوەندی بە سێرڤەر نەکرا. تکایە ئینتەرنێت بپشکنە و دووبارە هەوڵ بدەرەوە.';
    }

    if (normalized.contains('system_owner_required') ||
        normalized.contains('invalid login') ||
        normalized.contains('invalid credentials') ||
        normalized.contains('authapierror')) {
      return 'ژمارە یان وشەی نهێنی خاوەن سیستەم هەڵەیە، یان ئەم هەژمارە دەسەڵاتی System Owner ـی نییە.';
    }

    if (normalized.contains('market_exists') ||
        normalized.contains('market already exists')) {
      return 'ئەم ناوی مارکێتە پێشتر تۆمارکراوە.';
    }

    if (normalized.contains('phone_exists') ||
        normalized.contains('ژمارەیە پێشتر تۆمارکراوە')) {
      return 'ئەم ژمارە مۆبایلە پێشتر تۆمارکراوە.';
    }

    if (normalized.contains('invalid_input')) {
      return 'زانیارییەکان تەواو یان دروست نین.';
    }

    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

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
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'ژمارە یان وشەی نهێنی خاوەن سیستەم هەڵەیە.',
          isError: true,
        );
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          _friendlyRegistrationError(e),
          isError: true,
        );
      }
    } finally {
      try {
        await ownerClient.auth.signOut();
      } catch (_) {}
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دروستکردنی بەڕێوەبەر — Owner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 42,
                      color: AppColors.primary,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'پشتڕاستکردنەوەی خاوەن سیستەم',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'تەنها System Owner دەتوانێت هەژماری بەڕێوەبەری مارکێت درووست بکات.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              TextFormField(
                controller: _ownerPhoneController,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'ژمارە مۆبایلی خاوەن سیستەم',
                  prefixIcon: Icon(Icons.shield_outlined),
                  hintText: '07xxxxxxxxx',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'ژمارەی خاوەن سیستەم بنووسە'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _ownerPasswordController,
                obscureText: _obscureOwnerPassword,
                decoration: InputDecoration(
                  labelText: 'وشەی نهێنی خاوەن سیستەم',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscureOwnerPassword = !_obscureOwnerPassword,
                    ),
                    icon: Icon(
                      _obscureOwnerPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
                validator: (v) => v == null || v.isEmpty
                    ? 'وشەی نهێنی خاوەن سیستەم بنووسە'
                    : null,
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 18),
              const Text(
                'زانیاری مارکێت و بەڕێوەبەری نوێ',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _marketNameController,
                decoration: const InputDecoration(
                  labelText: AppStrings.marketName,
                  prefixIcon: Icon(Icons.store),
                  hintText: 'ناوی مارکێتەکە...',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'ناوی مارکێت بنووسە'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _adminNameController,
                decoration: const InputDecoration(
                  labelText: 'ناوی بەڕێوەبەر',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'ناوی بەڕێوەبەر بنووسە'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: AppStrings.phone,
                  prefixIcon: Icon(Icons.phone),
                  hintText: '07xxxxxxxxx',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'ژمارە مۆبایل بنووسە'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'وشەی نهێنی بەڕێوەبەری نوێ',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'وشەی نهێنی بنووسە';
                  if (v.length < 8) return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscurePassword,
                decoration: const InputDecoration(
                  labelText: 'دووبارەکردنەوەی وشەی نهێنی',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'وشەی نهێنی یەکناگرنەوە';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _register,
                  icon: _isLoading
                      ? const SizedBox.shrink()
                      : const Icon(Icons.add_business_rounded),
                  label: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'دروستکردنی هەژماری بەڕێوەبەر',
                          style: TextStyle(fontSize: 17),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
