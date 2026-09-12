import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';
import 'package:zhirox/services/official_receipt_service.dart';
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
  final _colorController = TextEditingController();
  final _prefixController = TextEditingController();
  final _discountController = TextEditingController();
  final _customFieldsController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _paperSize = 'a4';
  bool _showCustomerPhone = true;
  bool _showAdminName = true;
  String _templateStyle = 'modern';
  String _debtTemplate = 'modern';
  String _paymentTemplate = 'classic';
  String _purchaseTemplate = 'modern';
  String _logoPath = '';
  String _stampPath = '';
  String _signaturePath = '';
  double _fontScale = 1;
  String _headerAlignment = 'center';
  bool _showQr = true;
  bool _showBarcode = false;
  String _defaultPaymentMethod = 'debt';
  double _marginMm = 8;
  String _languageMode = 'ku';
  int _templateVersion = 1;
  String? _uploadingKind;

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
    _colorController.dispose();
    _prefixController.dispose();
    _discountController.dispose();
    _customFieldsController.dispose();
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
        _colorController.text = settings.primaryColor;
        _prefixController.text = settings.receiptPrefix;
        _discountController.text = settings.discountPercent.toStringAsFixed(2);
        _customFieldsController.text = settings.customFields
            .map((field) => '${field['label'] ?? ''}=${field['value'] ?? ''}')
            .join('\n');
        _paperSize = settings.paperSize;
        _showCustomerPhone = settings.showCustomerPhone;
        _showAdminName = settings.showAdminName;
        _templateStyle = settings.templateStyle;
        _debtTemplate = settings.debtTemplate;
        _paymentTemplate = settings.paymentTemplate;
        _purchaseTemplate = settings.purchaseTemplate;
        _logoPath = settings.logoPath;
        _stampPath = settings.stampPath;
        _signaturePath = settings.signaturePath;
        _fontScale = settings.fontScale;
        _headerAlignment = settings.headerAlignment;
        _showQr = settings.showQr;
        _showBarcode = settings.showBarcode;
        _defaultPaymentMethod = settings.defaultPaymentMethod;
        _marginMm = settings.marginMm;
        _languageMode = settings.languageMode;
        _templateVersion = settings.templateVersion;
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

  List<Map<String, String>> _parseCustomFields() {
    final result = <Map<String, String>>[];
    for (final line in _customFieldsController.text.split('\n')) {
      final clean = line.trim();
      if (clean.isEmpty) continue;
      final separator = clean.indexOf('=');
      if (separator <= 0) continue;
      final label = clean.substring(0, separator).trim();
      final value = clean.substring(separator + 1).trim();
      if (label.isEmpty) continue;
      result.add({'label': label, 'value': value});
      if (result.length == 12) break;
    }
    return result;
  }

  MarketReceiptSettings _draftSettings() {
    final auth = context.read<AuthProvider>();
    return MarketReceiptSettings(
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
      templateStyle: _templateStyle,
      debtTemplate: _debtTemplate,
      paymentTemplate: _paymentTemplate,
      purchaseTemplate: _purchaseTemplate,
      logoPath: _logoPath,
      stampPath: _stampPath,
      signaturePath: _signaturePath,
      primaryColor: _colorController.text.trim().toUpperCase(),
      fontScale: _fontScale,
      headerAlignment: _headerAlignment,
      showQr: _showQr,
      showBarcode: _showBarcode,
      receiptPrefix: _prefixController.text.trim().toUpperCase(),
      vatPercent: 0,
      discountPercent: double.tryParse(_discountController.text.trim()) ?? 0,
      defaultPaymentMethod: _defaultPaymentMethod,
      customFields: _parseCustomFields(),
      marginMm: _marginMm,
      languageMode: _languageMode,
      templateVersion: _templateVersion,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final auth = context.read<AuthProvider>();
    if (auth.userRole != 'admin') return;

    setState(() => _saving = true);
    try {
      final saved = await ReceiptSettingsService.save(_draftSettings());
      if (!mounted) return;
      setState(() => _templateVersion = saved.templateVersion);
      AppHelpers.showSnackBar(
        context,
        'ڕێکخستنەکانی پسوولە پاشەکەوت کران ✅  •  v${saved.templateVersion}',
      );
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

  Future<void> _pickAsset(String kind) async {
    if (_uploadingKind != null) return;
    final auth = context.read<AuthProvider>();
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2200,
    );
    if (file == null || !mounted) return;

    setState(() => _uploadingKind = kind);
    try {
      final path = await ReceiptSettingsService.uploadBrandAsset(
        adminId: auth.userId,
        kind: kind,
        bytes: await file.readAsBytes(),
        fileName: file.name,
        contentType: file.mimeType,
      );
      if (!mounted) return;
      setState(() {
        switch (kind) {
          case 'logo':
            _logoPath = path;
            break;
          case 'stamp':
            _stampPath = path;
            break;
          case 'signature':
            _signaturePath = path;
            break;
        }
      });
      AppHelpers.showSnackBar(context, 'وێنەکە بارکرا ✅');
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'بارکردنی وێنەکە سەرکەوتوو نەبوو.',
        ),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _uploadingKind = null);
    }
  }

  Future<void> _showPreview() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final settings = _draftSettings();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Live Preview ـی پسوولە')),
          body: PdfPreview(
            pdfFileName: 'ZHIROX_Receipt_Preview.pdf',
            build: (_) => OfficialReceiptService.buildSettingsPreview(
              marketName: auth.marketName,
              adminName: auth.userName,
              fallbackPhone: auth.user?.getStringValue('phone') ?? '',
              settings: settings,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE9EDF3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _gap() => const SizedBox(height: 12);

  Widget _assetButton({
    required String kind,
    required String label,
    required IconData icon,
    required String path,
  }) {
    final busy = _uploadingKind == kind;
    return OutlinedButton.icon(
      onPressed: _uploadingKind == null ? () => _pickAsset(kind) : null,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(path.isEmpty ? icon : Icons.check_circle_rounded),
      label: Text(path.isEmpty ? label : '$label ✓'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor:
          isDark ? AppDarkColors.background : const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('ڕێکخستنی پسوولەی فەرمی'),
        actions: [
          if (!_loading && auth.userRole == 'admin')
            IconButton(
              tooltip: 'Live Preview',
              onPressed: _showPreview,
              icon: const Icon(Icons.preview_outlined),
            ),
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
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: Colors.orange,
                        ),
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
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.14),
                              AppColors.primary.withValues(alpha: 0.04),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.storefront_outlined,
                              color: AppColors.primary,
                              size: 30,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    auth.marketName.isEmpty
                                        ? 'مارکێت'
                                        : auth.marketName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Template v$_templateVersion • ڕێکخستنەکان تەنها بۆ ئەم مارکێتە',
                                    style: const TextStyle(fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _section('زانیاری فەرمی', Icons.receipt_long_outlined, [
                        TextFormField(
                          controller: _titleController,
                          decoration: _decoration(
                            'ناونیشانی پسوولە',
                            Icons.receipt_outlined,
                          ),
                          validator: (value) => value == null || value.trim().isEmpty
                              ? 'ناونیشانی پسوولە بنووسە'
                              : null,
                        ),
                        _gap(),
                        TextFormField(
                          controller: _addressController,
                          decoration: _decoration(
                            'ناونیشانی مارکێت',
                            Icons.location_on_outlined,
                          ),
                          maxLines: 2,
                        ),
                        _gap(),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          decoration: _decoration(
                            'ژمارەی مۆبایل',
                            Icons.phone_outlined,
                          ),
                        ),
                        _gap(),
                        TextFormField(
                          controller: _secondaryPhoneController,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          decoration: _decoration(
                            'ژمارەی دووەم',
                            Icons.phone_in_talk_outlined,
                          ),
                        ),
                        _gap(),
                        TextFormField(
                          controller: _registrationController,
                          textDirection: TextDirection.ltr,
                          decoration: _decoration(
                            'ژمارەی تۆمار',
                            Icons.badge_outlined,
                          ),
                        ),
                        _gap(),
                        TextFormField(
                          controller: _footerController,
                          decoration: _decoration(
                            'دەقی خوارەوەی پسوولە',
                            Icons.notes_outlined,
                          ),
                          maxLines: 2,
                        ),
                      ]),
                      _section('براندینگ: لۆگۆ، مۆر و واژۆ', Icons.palette_outlined, [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _assetButton(
                              kind: 'logo',
                              label: 'لۆگۆی مارکێت',
                              icon: Icons.image_outlined,
                              path: _logoPath,
                            ),
                            _assetButton(
                              kind: 'stamp',
                              label: 'مۆری مارکێت',
                              icon: Icons.approval_outlined,
                              path: _stampPath,
                            ),
                            _assetButton(
                              kind: 'signature',
                              label: 'واژۆ',
                              icon: Icons.draw_outlined,
                              path: _signaturePath,
                            ),
                          ],
                        ),
                        _gap(),
                        TextFormField(
                          controller: _colorController,
                          textDirection: TextDirection.ltr,
                          decoration: _decoration(
                            'ڕەنگی سەرەکی HEX',
                            Icons.color_lens_outlined,
                            hint: '#0F766E',
                          ),
                          validator: (value) {
                            final clean = value?.trim() ?? '';
                            if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(clean)) {
                              return 'نمونە: #0F766E';
                            }
                            return null;
                          },
                        ),
                        _gap(),
                        Text('قەبارەی فۆنت: ${_fontScale.toStringAsFixed(2)}x'),
                        Slider(
                          value: _fontScale,
                          min: 0.75,
                          max: 1.5,
                          divisions: 15,
                          onChanged: (value) => setState(() => _fontScale = value),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _headerAlignment,
                          decoration: _decoration(
                            'شوێنی سەرپەڕە',
                            Icons.format_align_center,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'start', child: Text('ڕاست')), 
                            DropdownMenuItem(value: 'center', child: Text('ناوەڕاست')),
                            DropdownMenuItem(value: 'end', child: Text('چەپ')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _headerAlignment = value);
                          },
                        ),
                      ]),
                      _section('Template و قەبارەی چاپ', Icons.dashboard_customize_outlined, [
                        DropdownButtonFormField<String>(
                          initialValue: _templateStyle,
                          decoration: _decoration('Template ـی گشتی', Icons.style_outlined),
                          items: const [
                            DropdownMenuItem(value: 'classic', child: Text('Classic')),
                            DropdownMenuItem(value: 'modern', child: Text('Modern')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _templateStyle = value);
                          },
                        ),
                        _gap(),
                        DropdownButtonFormField<String>(
                          initialValue: _debtTemplate,
                          decoration: _decoration('Template ـی قەرز', Icons.request_quote_outlined),
                          items: const [
                            DropdownMenuItem(value: 'classic', child: Text('Classic')),
                            DropdownMenuItem(value: 'modern', child: Text('Modern')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _debtTemplate = value);
                          },
                        ),
                        _gap(),
                        DropdownButtonFormField<String>(
                          initialValue: _paymentTemplate,
                          decoration: _decoration('Template ـی پارەدانەوە', Icons.payments_outlined),
                          items: const [
                            DropdownMenuItem(value: 'classic', child: Text('Classic')),
                            DropdownMenuItem(value: 'modern', child: Text('Modern')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _paymentTemplate = value);
                          },
                        ),
                        _gap(),
                        DropdownButtonFormField<String>(
                          initialValue: _purchaseTemplate,
                          decoration: _decoration('Template ـی کڕین', Icons.shopping_cart_outlined),
                          items: const [
                            DropdownMenuItem(value: 'classic', child: Text('Classic')),
                            DropdownMenuItem(value: 'modern', child: Text('Modern')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _purchaseTemplate = value);
                          },
                        ),
                        _gap(),
                        DropdownButtonFormField<String>(
                          initialValue: _paperSize,
                          decoration: _decoration('قەبارەی کاغەز', Icons.print_outlined),
                          items: const [
                            DropdownMenuItem(value: 'a4', child: Text('A4 ـ فەرمی')),
                            DropdownMenuItem(value: 'thermal80', child: Text('80mm ـ Thermal/POS')),
                            DropdownMenuItem(value: 'thermal58', child: Text('58mm ـ Thermal/POS')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _paperSize = value);
                          },
                        ),
                        _gap(),
                        Text('حاشیەی چاپ: ${_marginMm.toStringAsFixed(0)}mm'),
                        Slider(
                          value: _marginMm,
                          min: 0,
                          max: 30,
                          divisions: 30,
                          onChanged: (value) => setState(() => _marginMm = value),
                        ),
                      ]),
                      _section('ژمارە، QR و Barcode', Icons.qr_code_2_outlined, [
                        TextFormField(
                          controller: _prefixController,
                          textDirection: TextDirection.ltr,
                          textCapitalization: TextCapitalization.characters,
                          decoration: _decoration(
                            'Prefix ـی ژمارەی پسوولە',
                            Icons.confirmation_number_outlined,
                            hint: 'INV',
                          ),
                          validator: (value) {
                            final clean = value?.trim() ?? '';
                            if (!RegExp(r'^[A-Za-z0-9_-]{1,12}$').hasMatch(clean)) {
                              return '١ تا ١٢ پیت/ژمارە؛ وەک INV';
                            }
                            return null;
                          },
                        ),
                        SwitchListTile(
                          value: _showQr,
                          onChanged: (value) => setState(() => _showQr = value),
                          title: const Text('QR Code پیشان بدرێت'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _showBarcode,
                          onChanged: (value) => setState(() => _showBarcode = value),
                          title: const Text('Barcode پیشان بدرێت'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ]),
                      _section('داشکاندن و پارەدان', Icons.calculate_outlined, [
                        TextFormField(
                          controller: _discountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textDirection: TextDirection.ltr,
                          decoration: _decoration('داشکاندن %', Icons.discount_outlined),
                          validator: (value) {
                            final number = double.tryParse(value?.trim() ?? '');
                            if (number == null || number < 0 || number > 100) {
                              return 'لە 0 تا 100';
                            }
                            return null;
                          },
                        ),
                        _gap(),
                        DropdownButtonFormField<String>(
                          initialValue: _defaultPaymentMethod,
                          decoration: _decoration('جۆری پارەدانی بنەڕەت', Icons.account_balance_wallet_outlined),
                          items: const [
                            DropdownMenuItem(value: 'cash', child: Text('نەقد')),
                            DropdownMenuItem(value: 'fib', child: Text('FIB')),
                            DropdownMenuItem(value: 'transfer', child: Text('حەواڵە')),
                            DropdownMenuItem(value: 'card', child: Text('کارت')),
                            DropdownMenuItem(value: 'debt', child: Text('قەرز')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _defaultPaymentMethod = value);
                          },
                        ),
                      ]),
                      _section('زمان و Custom Fields', Icons.translate_outlined, [
                        DropdownButtonFormField<String>(
                          initialValue: _languageMode,
                          decoration: _decoration('زمانی پسوولە', Icons.language_outlined),
                          items: const [
                            DropdownMenuItem(value: 'ku', child: Text('کوردی')),
                            DropdownMenuItem(value: 'ar', child: Text('عەرەبی')),
                            DropdownMenuItem(value: 'en', child: Text('English')),
                            DropdownMenuItem(value: 'ku_ar', child: Text('کوردی + عەرەبی')),
                            DropdownMenuItem(value: 'ku_en', child: Text('کوردی + English')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _languageMode = value);
                          },
                        ),
                        _gap(),
                        TextFormField(
                          controller: _customFieldsController,
                          maxLines: 5,
                          decoration: _decoration(
                            'Custom Fields',
                            Icons.dynamic_form_outlined,
                            hint: 'لق=دۆرێ\nکۆدی فرۆشگا=12345',
                          ).copyWith(
                            helperText: 'هەر دێڕێک: ناوی خانە=بەها  •  تا ١٢ خانە',
                          ),
                        ),
                        SwitchListTile(
                          value: _showCustomerPhone,
                          onChanged: (value) => setState(() => _showCustomerPhone = value),
                          title: const Text('ژمارەی مۆبایلی کڕیار پیشان بدرێت'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        SwitchListTile(
                          value: _showAdminName,
                          onChanged: (value) => setState(() => _showAdminName = value),
                          title: const Text('ناوی بەڕێوەبەر پیشان بدرێت'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ]),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _showPreview,
                          icon: const Icon(Icons.preview_outlined),
                          label: const Text('Live Preview ـی پسوولە'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('پاشەکەوتکردنی Template ـی فەرمی'),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }
}
