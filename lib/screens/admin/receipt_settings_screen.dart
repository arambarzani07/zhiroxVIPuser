import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/receipt_settings_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';

class ReceiptSettingsScreen extends StatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  State<ReceiptSettingsScreen> createState() => _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends State<ReceiptSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _secondaryPhoneController = TextEditingController();
  final _registrationController = TextEditingController();
  final _footerController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _paperSize = 'a4';
  bool _showCustomerPhone = true;
  bool _showAdminName = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _secondaryPhoneController.dispose();
    _registrationController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (auth.userRole != 'admin') {
      setState(() {
        _loading = false;
        _error = 'تەنها بەڕێوەبەر دەتوانێت پسوولە ڕێکبخات.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final settings = await ReceiptSettingsService.load(
        adminId: auth.userId,
        fallbackMarketName: auth.marketName,
        fallbackPhone: auth.user?.getStringValue('phone') ?? '',
      );
      if (!mounted) return;
      setState(() {
        _titleController.text = settings.receiptTitle;
        _addressController.text = settings.address;
        _phoneController.text = settings.phone;
        _secondaryPhoneController.text = settings.secondaryPhone;
        _registrationController.text = settings.registrationNo;
        _footerController.text = settings.footerNote;
        _paperSize = settings.paperSize;
        _showCustomerPhone = settings.showCustomerPhone;
        _showAdminName = settings.showAdminName;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا ڕێکخستنەکانی پسوولە باربکرێن. دووبارە هەوڵ بدە.',
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final auth = context.read<AuthProvider>();
    if (auth.userRole != 'admin') return;

    setState(() => _saving = true);
    try {
      final settings = MarketReceiptSettings(
        adminId: auth.userId,
        receiptTitle: _titleController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        secondaryPhone: _secondaryPhoneController.text.trim(),
        registrationNo: _registrationController.text.trim(),
        footerNote: _footerController.text.trim(),
        paperSize: _paperSize,
        showCustomerPhone: _showCustomerPhone,
        showAdminName: _showAdminName,
      );
      await ReceiptSettingsService.save(settings);
      if (!mounted) return;
      AppHelpers.showSnackBar(context, 'ڕێکخستنەکانی پسوولە پاشەکەوت کران ✅');
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'پاشەکەوتکردنی ڕێکخستنەکانی پسوولە سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('ڕێکخستنی پسوولەی فەرمی'),
        actions: [
          if (!_loading && auth.userRole == 'admin')
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('پاشەکەوت'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 48, color: Colors.orange),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        if (auth.userRole == 'admin')
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('دووبارە هەوڵ بدە'),
                          ),
                      ],
                    ),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppDarkColors.card : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.storefront_outlined, color: AppColors.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    auth.marketName.isEmpty ? 'مارکێت' : auth.marketName,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'ئەم زانیارییانە تەنها بۆ پسوولەی ئەم مارکێتە پاشەکەوت دەبن و لە پسوولەی مارکێتی تر جیاوازن.',
                              style: TextStyle(fontSize: 12.5, height: 1.6),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _titleController,
                        decoration: _decoration('ناونیشانی پسوولە', Icons.receipt_outlined),
                        validator: (value) => value == null || value.trim().isEmpty
                            ? 'ناونیشانی پسوولە بنووسە'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressController,
                        decoration: _decoration('ناونیشانی مارکێت', Icons.location_on_outlined),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: _decoration('ژمارەی مۆبایل', Icons.phone_outlined),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _secondaryPhoneController,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: _decoration('ژمارەی دووەم', Icons.phone_in_talk_outlined),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _registrationController,
                        textDirection: TextDirection.ltr,
                        decoration: _decoration(
                          'ژمارەی تۆمار / باج (ئارەزوومەندانە)',
                          Icons.badge_outlined,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _footerController,
                        decoration: _decoration('دەقی خوارەوەی پسوولە', Icons.notes_outlined),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _paperSize,
                        decoration: _decoration('قەبارەی کاغەز', Icons.print_outlined),
                        items: const [
                          DropdownMenuItem(value: 'a4', child: Text('A4 ـ پسوولەی فەرمی تەواو')),
                          DropdownMenuItem(value: 'thermal80', child: Text('80mm ـ پرینتەری حەراری')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _paperSize = value);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: _showCustomerPhone,
                        onChanged: (value) => setState(() => _showCustomerPhone = value),
                        title: const Text('ژمارەی مۆبایلی کڕیار لە پسوولە پیشان بدرێت'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      SwitchListTile(
                        value: _showAdminName,
                        onChanged: (value) => setState(() => _showAdminName = value),
                        title: const Text('ناوی بەڕێوەبەر لە پسوولە پیشان بدرێت'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('پاشەکەوتکردنی پسوولەی فەرمی'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
