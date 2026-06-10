import 'package:flutter/material.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class RegisterAdminScreen extends StatefulWidget {
  const RegisterAdminScreen({super.key});

  @override
  State<RegisterAdminScreen> createState() => _RegisterAdminScreenState();
}

class _RegisterAdminScreenState extends State<RegisterAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _marketNameController = TextEditingController();
  final _adminNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _marketNameController.dispose();
    _adminNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await PBService.registerAdmin(
        marketName: _marketNameController.text.trim(),
        adminName: _adminNameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        subscriptionDays: 30,
      );

      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'بەڕێوبەر بە سەرکەوتوویی تۆمارکرا. ئێستا داخڵ بە.',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.registerAdmin)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // لۆگۆ
              Container(
                width: 80,
                height: 80,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.store_rounded,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),

              TextFormField(
                controller: _marketNameController,
                decoration: const InputDecoration(
                  labelText: AppStrings.marketName,
                  prefixIcon: Icon(Icons.store),
                  hintText: 'ناوی مارکێتەکەت...',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'ناوی مارکێت بنووسە' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _adminNameController,
                decoration: const InputDecoration(
                  labelText: 'ناوی بەڕێوەبەر',
                  prefixIcon: Icon(Icons.person),
                  hintText: 'ناوی خۆت...',
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'ناوی بەڕێوەبەر بنووسە' : null,
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
                validator: (v) =>
                    v == null || v.isEmpty ? 'ژمارە مۆبایل بنووسە' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: AppStrings.password,
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
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
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          AppStrings.registerAdmin,
                          style: TextStyle(fontSize: 18),
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
