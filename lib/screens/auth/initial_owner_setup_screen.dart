import 'package:flutter/material.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/helpers.dart';

class InitialOwnerSetupScreen extends StatefulWidget {
  const InitialOwnerSetupScreen({super.key});

  @override
  State<InitialOwnerSetupScreen> createState() => _InitialOwnerSetupScreenState();
}

class _InitialOwnerSetupScreenState extends State<InitialOwnerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _busy = false;
  bool _obscurePassword = true;
  bool _checking = true;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final open = await PBService.initialOwnerBootstrapOpen();
      if (!mounted) return;
      setState(() {
        _open = open;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
    }
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || _busy) return;

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final ready = await PBService.registerInitialSystemOwner(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;

      if (ready) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('System Owner درووست کرا'),
            content: const Text(
              'هەژماری خاوەنی سیستەم درووست کرا. ئێستا دەتوانیت بە ئیمەیل و وشەی نهێنی بچیتە ژوورەوە.',
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
        if (mounted) Navigator.pop(context);
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('ئیمەیلەکەت پشتڕاست بکەرەوە'),
          content: const Text(
            'Supabase داوای پشتڕاستکردنەوەی ئیمەیل دەکات. لینکەکە لە ئیمەیلەکەت بکەرەوە، پاشان لەم ئەپە بە هەمان ئیمەیل و وشەی نهێنی بچۆ ژوورەوە. یەکەم login خۆکار System Owner ـەکە تەواو دەکات.',
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
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final message = raw.contains('bootstrap_closed')
          ? 'System Owner پێشتر درووست کراوە.'
          : raw.contains('User already registered')
              ? 'ئەم ئیمەیلە پێشتر تۆمارکراوە.'
              : 'نەتوانرا هەژماری خاوەن درووست بکرێت. زانیارییەکان بپشکنە و دووبارە هەوڵ بدە.';
      AppHelpers.showSnackBar(context, message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'دامەزراندنی یەکەم خاوەن',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: _checking
            ? const Center(child: CircularProgressIndicator())
            : !_open
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'System Owner پێشتر درووست کراوە؛ bootstrap قوفڵە.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: isDark
                                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                                      : const Color(0xFFF4F6FB),
                                ),
                                child: const Text(
                                  'ئەم هەنگاوە تەنها یەک جار لە داتابەیسی نوێ کار دەکات. دوای دروستبوونی System Owner خۆکار قوفڵ دەبێت.',
                                  style: TextStyle(height: 1.55),
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextFormField(
                                controller: _nameController,
                                enabled: !_busy,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'ناوی خاوەن',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().length < 2
                                        ? 'ناو بنووسە'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _emailController,
                                enabled: !_busy,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                textDirection: TextDirection.ltr,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'ئیمەیل',
                                  hintText: 'name@example.com',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (!text.contains('@') || !text.contains('.')) {
                                    return 'ئیمەیلی دروست بنووسە';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phoneController,
                                enabled: !_busy,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                textDirection: TextDirection.ltr,
                                decoration: const InputDecoration(
                                  labelText: 'ژمارە مۆبایل',
                                  hintText: '07xxxxxxxxx',
                                  prefixIcon: Icon(Icons.phone_iphone_outlined),
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  return RegExp(r'^\d{8,15}$').hasMatch(text)
                                      ? null
                                      : 'ژمارەی دروست بنووسە';
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                enabled: !_busy,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.next,
                                textDirection: TextDirection.ltr,
                                decoration: InputDecoration(
                                  labelText: 'وشەی نهێنی',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    onPressed: _busy
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
                                validator: (value) => value == null || value.length < 12
                                    ? 'لانیکەم ١٢ پیت/ژمارە'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmController,
                                enabled: !_busy,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                textDirection: TextDirection.ltr,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                  labelText: 'دووبارەی وشەی نهێنی',
                                  prefixIcon: Icon(Icons.lock_reset_outlined),
                                ),
                                validator: (value) => value != _passwordController.text
                                    ? 'وشەی نهێنی یەکسان نییە'
                                    : null,
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _busy ? null : _submit,
                                  icon: _busy
                                      ? const SizedBox.shrink()
                                      : const Icon(Icons.verified_user_outlined),
                                  label: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text(
                                          'دروستکردنی System Owner',
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
    );
  }
}
