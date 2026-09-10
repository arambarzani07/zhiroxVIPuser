import 'package:flutter/material.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class RegisterCustomerScreen extends StatefulWidget {
  const RegisterCustomerScreen({super.key});

  @override
  State<RegisterCustomerScreen> createState() => _RegisterCustomerScreenState();
}

class _RegisterCustomerScreenState extends State<RegisterCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _loadingAdmins = true;
  String? _adminLoadError;
  List<RecordModel> _admins = [];
  String? _selectedAdminId;

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyRegistrationError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('network') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection')) {
      return 'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێتەکەت بپشکنە و دووبارە هەوڵ بدە.';
    }
    if (raw.contains('phone') &&
        (raw.contains('exist') || raw.contains('already') || raw.contains('unique'))) {
      return 'ئەم ژمارە مۆبایلە پێشتر تۆمارکراوە.';
    }
    if (raw.contains('market') || raw.contains('admin')) {
      return 'مارکێتە هەڵبژێردراوەکە بەردەست نییە. دووبارە مارکێت هەڵبژێرە.';
    }
    return 'نەتوانرا داواکارییەکەت بنێردرێت. دووبارە هەوڵ بدە.';
  }

  Future<void> _loadAdmins() async {
    if (!mounted) return;
    setState(() {
      _loadingAdmins = true;
      _adminLoadError = null;
    });

    try {
      final allAdmins = await PBService.getAdminList();
      final seen = <String>{};
      final unique = <RecordModel>[];
      for (final admin in allAdmins) {
        final name = admin.getStringValue('market_name').trim();
        if (name.isNotEmpty && seen.add(name)) unique.add(admin);
      }
      unique.sort(
        (a, b) => a
            .getStringValue('market_name')
            .compareTo(b.getStringValue('market_name')),
      );
      if (!mounted) return;
      setState(() {
        _admins = unique;
        if (_selectedAdminId != null &&
            !_admins.any((admin) => admin.id == _selectedAdminId)) {
          _selectedAdminId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _adminLoadError = 'نەتوانرا لیستی مارکێتەکان بار بکرێت.';
      });
    } finally {
      if (mounted) setState(() => _loadingAdmins = false);
    }
  }

  Future<void> _register() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    if (_selectedAdminId == null) {
      AppHelpers.showSnackBar(context, 'تکایە مارکێتێک هەڵبژێرە.', isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      await PBService.registerCustomer(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text,
        adminId: _selectedAdminId!,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: Colors.green),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'داواکاری نێردرا',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: const Text(
            AppStrings.requestSent,
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('باشە'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        _friendlyRegistrationError(e),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration({
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
    }) {
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
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
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
          'خۆتۆمارکردن وەک کڕیار',
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
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    section(
                      title: 'مارکێت',
                      subtitle: 'ئەو مارکێتە هەڵبژێرە کە قەرزەکانت لەگەڵیدا تۆمار دەکرێن.',
                      icon: Icons.storefront_outlined,
                      children: [
                        if (_adminLoadError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.wifi_off_rounded, color: Colors.orange, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _adminLoadError!,
                                    style: TextStyle(fontSize: 11.5, color: textSecondary),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loadingAdmins ? null : _loadAdmins,
                                  child: const Text('دووبارە'),
                                ),
                              ],
                            ),
                          ),
                        ] else
                          DropdownButtonFormField<String>(
                            initialValue: _selectedAdminId,
                            isExpanded: true,
                            decoration: _fieldDecoration(
                              label: AppStrings.selectMarket,
                              icon: Icons.store_rounded,
                              hint: _loadingAdmins
                                  ? 'مارکێتەکان بار دەکرێن...'
                                  : 'مارکێت هەڵبژێرە',
                            ),
                            items: _admins
                                .map(
                                  (admin) => DropdownMenuItem<String>(
                                    value: admin.id,
                                    child: Text(
                                      admin.getStringValue('market_name'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _loadingAdmins || _isLoading
                                ? null
                                : (value) => setState(() => _selectedAdminId = value),
                            validator: (value) => value == null ? 'مارکێتێک هەڵبژێرە' : null,
                          ),
                        if (!_loadingAdmins &&
                            _adminLoadError == null &&
                            _admins.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              'هێشتا هیچ مارکێتێکی بەردەست نییە.',
                              style: TextStyle(fontSize: 11.5, color: textSecondary),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    section(
                      title: 'زانیاری هەژمار',
                      subtitle: 'زانیاری بنەڕەتی خۆت بنووسە؛ داواکارییەکەت پاشان بۆ مارکێت دەنێردرێت.',
                      icon: Icons.person_add_alt_1_outlined,
                      children: [
                        TextFormField(
                          controller: _nameController,
                          enabled: !_isLoading,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(
                            label: AppStrings.name,
                            icon: Icons.person_outline_rounded,
                            hint: 'ناوی سیانی',
                          ),
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'ناو بنووسە'
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
                          decoration: _fieldDecoration(
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
                          textInputAction: TextInputAction.done,
                          textDirection: TextDirection.ltr,
                          autofillHints: const [AutofillHints.newPassword],
                          onFieldSubmitted: (_) => _register(),
                          decoration: _fieldDecoration(
                            label: AppStrings.password,
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
                            if (value == null || value.isEmpty) {
                              return 'وشەی نهێنی بنووسە';
                            }
                            if (value.length < 8) {
                              return 'وشەی نهێنی لانیکەم ٨ پیت بێت';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading || _loadingAdmins || _adminLoadError != null
                            ? null
                            : _register,
                        icon: _isLoading
                            ? const SizedBox.shrink()
                            : const Icon(Icons.send_outlined, size: 19),
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
                                'ناردنی داواکاری',
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
