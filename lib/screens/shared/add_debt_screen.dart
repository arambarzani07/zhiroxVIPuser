import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:provider/provider.dart';
import 'package:zhirox/providers/auth_provider.dart';

import 'package:zhirox/services/pb_service.dart';
import 'package:zhirox/services/notification_service.dart';
import 'package:zhirox/services/receipt_settings_service.dart';
import 'package:zhirox/utils/constants.dart';
import 'package:zhirox/utils/helpers.dart';
import 'package:zhirox/utils/image_utils.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:image_picker/image_picker.dart';

class AddDebtScreen extends StatefulWidget {
  final String? customerId;
  final RecordModel? debt;
  final String? referenceKind;
  final String? referenceId;

  const AddDebtScreen({
    super.key,
    this.customerId,
    this.debt,
    this.referenceKind,
    this.referenceId,
  });

  @override
  State<AddDebtScreen> createState() => _AddDebtScreenState();
}

class _AddDebtScreenState extends State<AddDebtScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _dollarRateController = TextEditingController();
  double _discountPercent = 0;
  bool _loadingPricingPolicy = true;
  String? _pricingPolicyError;
  DateTime? _dueDate;
  bool _hasDueDate = false;
  bool _hasCustomDebtDate = false;
  DateTime? _customDebtDate;
  File? _receiptImage;
  bool _isLoading = false;
  String _currency = 'IQD';

  // کاڵاکان
  final List<Map<String, dynamic>> _items = [];

  // کڕیار
  List<RecordModel> _customers = [];
  String? _selectedCustomerId;
  bool _loadingCustomers = true;
  String? _customerLoadError;

  @override
  void initState() {
    super.initState();
    if (widget.debt != null) {
      _selectedCustomerId = widget.debt!.getStringValue('customer');
      _descriptionController.text = widget.debt!.getStringValue('description');
      _currency = widget.debt!.getStringValue('currency');
      _dollarRateController.text = widget.debt!
          .getDoubleValue('dollar_rate')
          .toString();
      _discountPercent = widget.debt!
          .getDoubleValue('discount_percent')
          .clamp(0.0, 100.0)
          .toDouble();
      _loadingPricingPolicy = false;
      final dueDateStr = widget.debt!.getStringValue('due_date');
      if (dueDateStr.isNotEmpty) {
        _dueDate = DateTime.tryParse(dueDateStr);
        _hasDueDate = _dueDate != null;
      }

      final itemsJson = widget.debt!.getStringValue('items');
      if (itemsJson.isNotEmpty && itemsJson != '[]') {
        try {
          final List<dynamic> decoded = jsonDecode(itemsJson);
          _items.addAll(decoded.map((e) => Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    } else {
      _selectedCustomerId = widget.customerId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPricingPolicy();
      });
    }
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    if (mounted) {
      setState(() {
        _loadingCustomers = true;
        _customerLoadError = null;
      });
    }

    try {
      final auth = context.read<AuthProvider>();
      final customers = await PBService.getUsers(
        role: 'customer',
        adminId: auth.adminId,
        approved: true,
      );
      if (!mounted) return;

      setState(() {
        _customers = customers;
        _loadingCustomers = false;
        _customerLoadError = null;

        // If creating new debt and user can't set due date, ensure it's off.
        if (widget.debt == null && !auth.canSetDueDate) {
          _dueDate = null;
          _hasDueDate = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _customers = [];
        _loadingCustomers = false;
        _customerLoadError =
            'نەتوانرا لیستی کڕیاران لە سێرڤەر وەربگیرێت. ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.';
      });
    }
  }

  Future<void> _loadPricingPolicy() async {
    if (widget.debt != null) return;
    final auth = context.read<AuthProvider>();
    if (mounted) {
      setState(() {
        _loadingPricingPolicy = true;
        _pricingPolicyError = null;
      });
    }
    try {
      final settings = await ReceiptSettingsService.load(
        adminId: auth.adminId,
        fallbackMarketName: auth.marketName,
        fallbackPhone: auth.user?.getStringValue('phone') ?? '',
      );
      if (!mounted) return;
      setState(() {
        _discountPercent = settings.discountPercent.clamp(0.0, 100.0).toDouble();
        _loadingPricingPolicy = false;
        _pricingPolicyError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingPricingPolicy = false;
        _pricingPolicyError =
            'نەتوانرا ڕێکخستنی داشکاندنی مارکێت پشتڕاست بکرێتەوە.';
      });
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _dollarRateController.dispose();
    super.dispose();
  }

  void _addItem() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final qtyController = TextEditingController(text: '1');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (stfContext, setSheetState) {
            // Live total calculation
            final rawPrice = priceController.text.replaceAll(',', '').trim();
            final price = double.tryParse(rawPrice) ?? 0;
            final qty = int.tryParse(qtyController.text.trim()) ?? 1;
            final liveTotal = price * qty;

            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              decoration: BoxDecoration(
                color: isDark ? AppDarkColors.card : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppDarkColors.cardBorder
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Header with gradient
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.add_shopping_cart,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'زیادکردنی کاڵا',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'ناو و نرخ و دانە بنووسە',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Live total badge
                            if (liveTotal > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _currency == 'IQD'
                                      ? AppHelpers.formatCurrency(liveTotal)
                                      : '\$${liveTotal.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Item name field
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextFormField(
                          controller: nameController,
                          textInputAction: TextInputAction.next,
                          style: TextStyle(
                            color: isDark ? AppDarkColors.textPrimary : null,
                          ),
                          decoration: InputDecoration(
                            labelText: AppStrings.itemName,
                            hintText: 'ناوی کاڵا بنووسە...',
                            prefixIcon: const Icon(Icons.shopping_bag_outlined),
                            filled: true,
                            fillColor: isDark
                                ? AppDarkColors.inputFill
                                : Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: isDark
                                  ? BorderSide(color: AppDarkColors.cardBorder)
                                  : BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: (_) => setSheetState(() {}),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Price and quantity row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            // Price field
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: priceController,
                                keyboardType: TextInputType.number,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.center,
                                textInputAction: TextInputAction.next,
                                style: TextStyle(
                                  color: isDark
                                      ? AppDarkColors.textPrimary
                                      : null,
                                ),
                                inputFormatters: [
                                  if (_currency == 'IQD')
                                    ThousandsSeparatorInputFormatter(),
                                  if (_currency == 'USD')
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.]'),
                                    ),
                                ],
                                decoration: InputDecoration(
                                  labelText: AppStrings.itemPrice,
                                  prefixIcon: const Icon(
                                    Icons.attach_money,
                                    size: 20,
                                  ),
                                  suffixText: _currency == 'IQD' ? 'د.ع' : '\$',
                                  filled: true,
                                  fillColor: isDark
                                      ? AppDarkColors.inputFill
                                      : Colors.grey.shade50,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: isDark
                                        ? BorderSide(
                                            color: AppDarkColors.cardBorder,
                                          )
                                        : BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: const BorderSide(
                                      color: AppColors.primary,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                onChanged: (_) => setSheetState(() {}),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Quantity field with +/- buttons
                            Expanded(
                              flex: 2,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppDarkColors.surface
                                      : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    // Minus button
                                    InkWell(
                                      onTap: () {
                                        final current =
                                            int.tryParse(qtyController.text) ??
                                            1;
                                        if (current > 1) {
                                          qtyController.text = '${current - 1}';
                                          setSheetState(() {});
                                        }
                                      },
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(14),
                                        bottomRight: Radius.circular(14),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        child: Icon(
                                          Icons.remove,
                                          size: 18,
                                          color: isDark
                                              ? AppDarkColors.textSecondary
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    // Qty input
                                    Expanded(
                                      child: TextFormField(
                                        controller: qtyController,
                                        keyboardType: TextInputType.number,
                                        textDirection: TextDirection.ltr,
                                        textAlign: TextAlign.center,
                                        textInputAction: TextInputAction.done,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isDark
                                              ? AppDarkColors.textPrimary
                                              : null,
                                        ),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                          isDense: true,
                                        ),
                                        onChanged: (_) => setSheetState(() {}),
                                      ),
                                    ),
                                    // Plus button
                                    InkWell(
                                      onTap: () {
                                        final current =
                                            int.tryParse(qtyController.text) ??
                                            1;
                                        qtyController.text = '${current + 1}';
                                        setSheetState(() {});
                                      },
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(14),
                                        bottomLeft: Radius.circular(14),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        child: const Icon(
                                          Icons.add,
                                          size: 18,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Add button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              if (nameController.text.trim().isEmpty ||
                                  priceController.text.trim().isEmpty) {
                                return;
                              }
                              final parsedPrice =
                                  double.tryParse(
                                    priceController.text
                                        .replaceAll(',', '')
                                        .trim(),
                                  ) ??
                                  0;
                              final parsedQty =
                                  int.tryParse(qtyController.text.trim()) ?? 1;
                              setState(() {
                                _items.add({
                                  'name': nameController.text.trim(),
                                  'price': parsedPrice,
                                  'qty': parsedQty,
                                  'currency': _currency,
                                });
                              });
                              Navigator.pop(sheetContext);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'زیادکردن',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _pickImage() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppDarkColors.card : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppDarkColors.cardBorder : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'هەڵبژاردنی وێنە',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.blue),
                ),
                title: Text(
                  'کامێرا',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  'وێنەگرتن بە کامێرا',
                  style: TextStyle(
                    color: isDark ? AppDarkColors.textSecondary : Colors.grey,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.green),
                ),
                title: Text(
                  'ئەلبوم',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                  ),
                ),
                subtitle: Text(
                  'هەڵبژاردن لە ئەلبوم',
                  style: TextStyle(
                    color: isDark ? AppDarkColors.textSecondary : Colors.grey,
                  ),
                ),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    try {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked == null) return;

      // Compress
      final originalFile = File(picked.path);
      final compressed = await ImageUtils.compressImage(originalFile);

      if (!mounted) return;
      setState(() {
        _receiptImage = compressed ?? originalFile;
      });
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.backendErrorMessage(
            e,
            fallback: 'نەتوانرا وێنە هەڵبژێردرێت. دووبارە هەوڵ بدە.',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _save() async {
    if (widget.debt == null && _loadingPricingPolicy) {
      AppHelpers.showSnackBar(
        context,
        'چاوەڕێ بکە تا ڕێکخستنی داشکاندن پشتڕاست دەکرێتەوە.',
        isError: true,
      );
      return;
    }
    if (widget.debt == null && _pricingPolicyError != null) {
      AppHelpers.showSnackBar(context, _pricingPolicyError!, isError: true);
      return;
    }
    if (_loadingCustomers || _customerLoadError != null) {
      AppHelpers.showSnackBar(
        context,
        'سەرەتا زانیاریی کڕیاران بە سەرکەوتوویی بار بکە.',
        isError: true,
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      AppHelpers.showSnackBar(context, 'تکایە کڕیارێک هەڵبژێرە', isError: true);
      return;
    }
    if (_items.isEmpty) {
      AppHelpers.showSnackBar(context, 'تکایە کاڵایەک زیاد بکە', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      final dollarRate =
          double.tryParse(_dollarRateController.text.trim()) ?? 0;

      // Calculate the undiscounted subtotal in IQD, then apply the
      // market receipt discount once. The discounted result is the financial
      // debt amount used by limits, payments, reports, and receipts.
      double subtotalNewDebt = 0;
      double subtotalUsdAmount = 0;
      for (var item in _items) {
        final itemCurrency = item['currency'] as String? ?? _currency;
        final itemTotal = (item['price'] as double) * (item['qty'] as int);
        if (itemCurrency == 'USD') {
          subtotalUsdAmount += itemTotal;
          subtotalNewDebt += dollarRate > 0 ? itemTotal * dollarRate : itemTotal;
        } else {
          subtotalNewDebt += itemTotal;
        }
      }
      final discountPercent = _discountPercent.clamp(0.0, 100.0).toDouble();
      final discountAmount =
          ((subtotalNewDebt * discountPercent / 100) * 100).roundToDouble() / 100;
      final totalNewDebt = subtotalNewDebt - discountAmount;
      final totalUsdAmount = subtotalUsdAmount * (1 - discountPercent / 100);
      if (totalNewDebt <= 0) {
        if (!mounted) return;
        AppHelpers.showSnackBar(
          context,
          'داشکاندن ناتوانێت کۆی کۆتایی قەرز بکاتە سفر.',
          isError: true,
        );
        setState(() => _isLoading = false);
        return;
      }

      // Check Debt Limit. This is fail-closed: if the selected customer or
      // current server balance cannot be verified, do not create/update a debt.
      RecordModel? selectedCustomer;
      for (final customer in _customers) {
        if (customer.id == _selectedCustomerId) {
          selectedCustomer = customer;
          break;
        }
      }

      if (selectedCustomer == null) {
        if (!mounted) return;
        AppHelpers.showSnackBar(
          context,
          'نەتوانرا زانیاریی کڕیار پشتڕاست بکرێتەوە. دووبارە هەوڵ بدە.',
          isError: true,
        );
        setState(() => _isLoading = false);
        return;
      }

      final debtLimit = selectedCustomer.getDoubleValue('debt_limit');
      if (debtLimit > 0) {
        double currentBalance;
        try {
          currentBalance = await PBService.getCustomerBalance(
            _selectedCustomerId!,
          );
        } catch (_) {
          if (!mounted) return;
          AppHelpers.showSnackBar(
            context,
            'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. ئینتەرنێت بپشکنە و دووبارە هەوڵ بدە.',
            isError: true,
          );
          setState(() => _isLoading = false);
          return;
        }
        if (!mounted) return;

        final oldRemainingForProjection =
            widget.debt?.getDoubleValue('remaining') ?? 0;
        final oldAmountForProjection =
            widget.debt?.getDoubleValue('amount') ?? 0;
        final alreadyPaidForProjection = widget.debt == null
            ? 0.0
            : (oldAmountForProjection - oldRemainingForProjection)
                .clamp(0.0, double.infinity)
                .toDouble();
        final newRemainingForProjection = widget.debt == null
            ? totalNewDebt
            : (totalNewDebt - alreadyPaidForProjection)
                .clamp(0.0, double.infinity)
                .toDouble();
        final sameCustomer = widget.debt != null &&
            widget.debt!.getStringValue('customer') == _selectedCustomerId;
        final projectedBalance = currentBalance +
            newRemainingForProjection -
            (sameCustomer ? oldRemainingForProjection : 0);

        if (projectedBalance > debtLimit) {
          final canOverride = auth.canSetDebtLimit;

          if (canOverride) {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('سنووری قەرز تێپەڕیوە'),
                content: Text(
                  'بەکارهێنەر سنووری قەرزی تێپەڕاندووە.\n'
                  'سنور: ${AppHelpers.formatCurrency(debtLimit)}\n'
                  'کۆی گشتی: ${AppHelpers.formatCurrency(projectedBalance)}\n\n'
                  'ئایا دەتەوێت بەردەوام بیت؟',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('نەخێر'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('بەڵێ، بەردەوام بە'),
                  ),
                ],
              ),
            );
            if (!mounted) return;
            if (confirm != true) {
              setState(() => _isLoading = false);
              return;
            }
          } else {
            AppHelpers.showSnackBar(
              context,
              'ناتوانیت ئەم قەرزە زیاد بکەیت! بەکارهێنەر سنووری قەرزی تێپەڕاندووە.\n'
              'سنور: ${AppHelpers.formatCurrency(debtLimit)}\n'
              'کۆی گشتی دوای زیادکردن: ${AppHelpers.formatCurrency(projectedBalance)}',
              isError: true,
            );
            setState(() => _isLoading = false);
            return;
          }
        }
      }

      if (widget.debt != null) {
        // Update Logic
        final oldAmount = widget.debt!.getDoubleValue('amount');
        final oldRemaining = widget.debt!.getDoubleValue('remaining');
        final paid = (oldAmount - oldRemaining)
            .clamp(0.0, double.infinity)
            .toDouble();
        if (totalNewDebt + 0.009 < paid) {
          if (!mounted) return;
          AppHelpers.showSnackBar(
            context,
            'کۆی کۆتایی دوای داشکاندن نابێت کەمتر بێت لە پارەی پێشتر وەرگیراو.',
            isError: true,
          );
          setState(() => _isLoading = false);
          return;
        }
        final newRemaining = (totalNewDebt - paid)
            .clamp(0.0, double.infinity)
            .toDouble();
        final newStatus = newRemaining <= 0
            ? 'paid'
            : paid > 0
                ? 'partial'
                : 'pending';

        // Check if due_date changed → notify customer
        final oldDueDate = widget.debt!.getStringValue('due_date');
        final newDueDate = _dueDate != null
            ? DateFormat('yyyy-MM-dd').format(_dueDate!)
            : '';

        await PBService.updateDebt(widget.debt!.id, {
          'customer': _selectedCustomerId,
          'description': _descriptionController.text.trim(),
          'subtotal': subtotalNewDebt,
          'discount_percent': discountPercent,
          'discount_amount': discountAmount,
          'amount': totalNewDebt,
          'remaining': newRemaining,
          'status': newStatus,
          'due_date': newDueDate,
          'currency': 'IQD',
          'dollar_rate': dollarRate,
          'amount_usd': totalUsdAmount,
          'items': jsonEncode(_items),
        });

        // If due_date changed, send a notification to the customer
        if (oldDueDate != newDueDate && _selectedCustomerId != null) {
          try {
            // Always use admin name in notification
            String notifSenderName = auth.userName;
            if (auth.userRole != 'admin') {
              try {
                final adminRecord = await PBService.pb
                    .collection('users')
                    .getOne(auth.adminId);
                notifSenderName = adminRecord.getStringValue('name');
              } catch (_) {}
            }
            await PBService.createNotification(
              customerId: _selectedCustomerId!,
              message:
                  'بەرواری کۆتایی قەرزەکەت گۆڕدرا.\n'
                  'بەروارێکی نوێ: ${newDueDate.replaceAll('-', '/')}\n'
                  'لەلایەن $notifSenderName',
              senderId: auth.userId,
              type: 'due_date_changed',
            );
          } catch (_) {}
        }

        if (mounted) {
          AppHelpers.showSnackBar(context, 'قەرز نوێکرایەوە');
          Navigator.pop(context, true);
        }
      } else {
        // Create Logic
        await PBService.createDebt(
          customerId: _selectedCustomerId!,
          description: _descriptionController.text.trim(),
          amount: totalNewDebt,
          subtotal: subtotalNewDebt,
          discountPercent: discountPercent,
          dueDate: _dueDate != null
              ? DateFormat('yyyy-MM-dd').format(_dueDate!)
              : '',
          createdBy: auth.userId,
          currency: 'IQD',
          dollarRate: dollarRate,
          amountUsd: totalUsdAmount,
          items: _items,
          createdByName: auth.userName,
          marketName: auth.marketName,
          customCreatedDate: _hasCustomDebtDate && _customDebtDate != null
              ? _customDebtDate!.toUtc().toIso8601String()
              : null,
          receiptImagePath: _receiptImage?.path,
          referenceKind: widget.referenceKind,
          referenceId: widget.referenceId,
        );

        // Local push notification for new debt
        try {
          String customerName = '';
          try {
            final customer = _customers.firstWhere(
              (c) => c.id == _selectedCustomerId,
            );
            customerName = customer.getStringValue('name');
          } catch (_) {}

          final formattedAmount = AppHelpers.formatCurrency(totalNewDebt);
          await NotificationService.showDebtCreated(
            customerName: customerName.isNotEmpty ? customerName : 'کڕیار',
            amount: formattedAmount,
            employeeName: auth.userName,
          );
        } catch (_) {}

        if (mounted) {
          AppHelpers.showSnackBar(context, 'قەرز پێدان تۆمار کرا ✅');
          Navigator.pop(context, true); // Return true to indicate success
        }
      }
    } catch (e) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          AppHelpers.backendErrorMessage(
            e,
            fallback: 'نەتوانرا قەرزەکە پاشەکەوت بکرێت. دووبارە هەوڵ بدە.',
          ),
          isError: true,
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? AppDarkColors.background
        : const Color(0xFFF7F8FA);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: Text(
          widget.debt != null ? 'دەستکاریکردنی قەرز' : AppStrings.addDebt,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: isDark ? AppDarkColors.textPrimary : const Color(0xFF101828),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor:
            isDark ? AppDarkColors.textPrimary : const Color(0xFF344054),
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _buildCustomerSelector(),
                const SizedBox(height: 10),
                _buildCurrencyCard(),
                const SizedBox(height: 10),
                _buildItemsCard(),
                const SizedBox(height: 10),
                _buildDetailsCard(),
                if (widget.debt == null) ...[
                  const SizedBox(height: 10),
                  _buildReceiptCard(),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.18),
                alignment: Alignment.center,
                child: Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: isDark ? AppDarkColors.card : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildBottomAction(),
      ),
    );
  }

  Widget _buildCustomerSelector() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Text(
                'کڕیار هەڵبژێرە',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppDarkColors.textPrimary : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildCustomerPicker(isDark),
          // Show limit warning if selected
          if (_selectedCustomerId != null) _buildLimitWarning(),
        ],
      ),
    );
  }

  Widget _buildCustomerPicker(bool isDark) {
    if (_loadingCustomers) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }

    if (_customerLoadError != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _customerLoadError!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark
                          ? AppDarkColors.textPrimary
                          : const Color(0xFF344054),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loadCustomers,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('دووبارە هەوڵ بدە'),
              ),
            ),
          ],
        ),
      );
    }

    if (_customers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.surface : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 20,
              color: isDark ? AppDarkColors.textSecondary : Colors.grey.shade600,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'هیچ کڕیارێکی پەسەندکراو بەردەست نییە.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : const Color(0xFF667085),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final selectedValue = _customers.any((c) => c.id == _selectedCustomerId)
        ? _selectedCustomerId
        : null;

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark ? AppDarkColors.inputFill : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: isDark
              ? BorderSide(color: AppDarkColors.cardBorder)
              : BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      dropdownColor: isDark ? AppDarkColors.card : Colors.white,
      hint: Text(
        'کڕیارێک دیاری بکە',
        style: TextStyle(
          color: isDark ? AppDarkColors.textSecondary : Colors.black54,
        ),
      ),
      items: _customers.map((c) {
        final isOverLimit = _isOverLimit(c);
        return DropdownMenuItem<String>(
          value: c.id,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${c.getStringValue('name')} ${c.getStringValue('father_name')}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isOverLimit
                        ? Colors.red
                        : (isDark ? AppDarkColors.textPrimary : Colors.black87),
                  ),
                ),
              ),
              if (isOverLimit) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.red,
                ),
              ],
            ],
          ),
        );
      }).toList(),
      onChanged: widget.debt == null
          ? (v) => setState(() => _selectedCustomerId = v)
          : null,
      validator: (v) => v == null ? 'کڕیارێک هەڵبژێرە' : null,
    );
  }

  // Helper to check if customer is already over limit (just for UI indication in dropdown)
  bool _isOverLimit(RecordModel customer) {
    // This is just a visual hint. Actual enforcement happens on save.
    // For now, return false as we don't have balance for all customers yet.
    return false;
  }

  Widget _buildLimitWarning() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<double>(
      future: PBService.getCustomerBalance(_selectedCustomerId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'باڵانسی کڕیار دەپشکنرێت...',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'نەتوانرا باڵانسی کڕیار پشتڕاست بکرێتەوە. پاشەکەوتکردن تا پشتڕاستکردنەوە ڕادەوەستێت.',
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                ),
                IconButton(
                  tooltip: 'دووبارە هەوڵ بدە',
                  onPressed: () => setState(() {}),
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData) return const SizedBox.shrink();

        RecordModel? selectedCustomer;
        for (final customer in _customers) {
          if (customer.id == _selectedCustomerId) {
            selectedCustomer = customer;
            break;
          }
        }
        if (selectedCustomer == null) {
          return Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'زانیاری کڕیار بەردەست نییە. دووبارە کڕیار هەڵبژێرە.',
              style: TextStyle(fontSize: 11.5),
            ),
          );
        }

        final limit = selectedCustomer.getDoubleValue('debt_limit');
        final currentBalance = snapshot.data!;
        if (limit <= 0) return const SizedBox.shrink();

        final remainingLimit = limit - currentBalance;
        final isOver = remainingLimit < 0;
        final usagePercent = (currentBalance / limit).clamp(0.0, 1.0).toDouble();

        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isOver
                ? Colors.red.withValues(alpha: 0.05)
                : Colors.green.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOver
                  ? Colors.red.withValues(alpha: 0.3)
                  : Colors.green.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    isOver
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline,
                    color: isOver ? Colors.red : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سنووری قەرز: ${AppHelpers.formatCurrency(limit)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppDarkColors.textSecondary
                                : Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'قەرزی ئێستا: ${AppHelpers.formatCurrency(currentBalance)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isOver
                                ? Colors.red
                                : (isDark
                                    ? AppDarkColors.textPrimary
                                    : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isOver ? 'تێپەڕیوە' : 'بەردەستە',
                        style: TextStyle(
                          fontSize: 11,
                          color: isOver ? Colors.red : Colors.green,
                        ),
                      ),
                      Text(
                        AppHelpers.formatCurrency(remainingLimit.abs()),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isOver ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: usagePercent,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isOver
                        ? Colors.red
                        : usagePercent > 0.8
                            ? Colors.orange
                            : Colors.green,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrencyCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.monetization_on, color: Colors.orange),
              ),
              const SizedBox(width: 12),
              Text(
                'دراو و نرخ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppDarkColors.textPrimary : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppDarkColors.surface : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currency = 'IQD'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _currency == 'IQD'
                            ? (isDark ? AppDarkColors.card : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _currency == 'IQD'
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                ),
                              ]
                            : [],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        AppStrings.iqd,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _currency == 'IQD'
                              ? (isDark
                                    ? AppDarkColors.textPrimary
                                    : Colors.black)
                              : (isDark
                                    ? AppDarkColors.textSecondary
                                    : Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _currency = 'USD'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _currency == 'USD'
                            ? (isDark ? AppDarkColors.card : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: _currency == 'USD'
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                ),
                              ]
                            : [],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        AppStrings.usd,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _currency == 'USD'
                              ? (isDark
                                    ? AppDarkColors.textPrimary
                                    : Colors.black)
                              : (isDark
                                    ? AppDarkColors.textSecondary
                                    : Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Dollar Rate Input
          if (_currency == 'USD') ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _dollarRateController,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: AppStrings.dollarRate,
                prefixIcon: const Icon(Icons.currency_exchange),
                hintText: '1500',
                suffixText: 'د.ع',
                filled: true,
                fillColor: isDark
                    ? AppDarkColors.inputFill
                    : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (v) {
                if (_currency == 'USD' && (v == null || v.isEmpty)) {
                  return 'نرخی دۆلار بنووسە';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.shopping_bag, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'قەرز / کاڵاکان',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              IconButton(
                onPressed: _addItem,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quick Amount Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit,
                          size: 16,
                          color: isDark
                              ? AppDarkColors.textPrimary
                              : Colors.black87,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'نرخی بەدەست',
                          style: TextStyle(
                            color: isDark
                                ? AppDarkColors.textPrimary
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: isDark ? AppDarkColors.card : Colors.white,
                    side: BorderSide(
                      color: isDark
                          ? AppDarkColors.cardBorder
                          : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onPressed: _showCustomAmountDialog,
                  ),
                ),
                ...(_currency == 'IQD'
                        ? [5000, 10000, 15000, 25000, 50000, 100000]
                        : [5, 10, 25, 50, 100, 500])
                    .map(
                      (amount) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildQuickAmountChip(amount.toDouble()),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (widget.debt == null && _loadingPricingPolicy)
            const LinearProgressIndicator(minHeight: 2),
          if (widget.debt == null && _pricingPolicyError != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.22)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync_problem_rounded, color: Colors.orange, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pricingPolicyError!,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  IconButton(
                    tooltip: 'دووبارە هەوڵ بدە',
                    onPressed: _loadPricingPolicy,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                ],
              ),
            ),
          if (!_loadingPricingPolicy &&
              _pricingPolicyError == null &&
              _discountPercent > 0)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.discount_outlined, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'داشکاندنی مارکێت: ${_discountPercent.toStringAsFixed(2)}% • خۆکارانە لە کۆی کۆتایی کەم دەکرێتەوە',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(
                    Icons.add_shopping_cart,
                    size: 34,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'هیچ کاڵایەک زیاد نەکراوە',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                  TextButton(
                    onPressed: _addItem,
                    child: const Text('زیادکردنی کاڵا +'),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              itemBuilder: (context, index) {
                final item = _items[index];
                final itemCurrency = item['currency'] as String? ?? _currency;
                final itemTotal =
                    (item['price'] as double) * (item['qty'] as int);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppDarkColors.surface
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : Colors.black87,
                      ),
                    ),
                  ),
                  title: Text(
                    item['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${item['qty']} x ${AppHelpers.formatCurrencyWithType(item['price'], itemCurrency)}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppHelpers.formatCurrencyWithType(
                          itemTotal,
                          itemCurrency,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => setState(() => _items.removeAt(index)),
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildQuickAmountChip(double amount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ActionChip(
      label: Text(AppHelpers.formatCurrencyWithType(amount, _currency)),
      backgroundColor: isDark ? AppDarkColors.card : Colors.white,
      side: BorderSide(
        color: isDark ? AppDarkColors.cardBorder : Colors.grey.shade300,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () {
        setState(() {
          _items.add({
            'name': 'قەرز',
            'price': amount,
            'qty': 1,
            'currency': _currency,
          });
        });
      },
    );
  }

  Future<void> _showCustomAmountDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController();

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? AppDarkColors.card : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'بڕی قەرز بنووسە',
            style: TextStyle(
              color: isDark ? AppDarkColors.textPrimary : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            autofocus: true,
            style: TextStyle(
              color: isDark ? AppDarkColors.textPrimary : Colors.black87,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            inputFormatters: [
              if (_currency == 'IQD') ThousandsSeparatorInputFormatter(),
              if (_currency == 'USD')
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: TextStyle(
                color: isDark
                    ? AppDarkColors.textSecondary
                    : Colors.grey.shade500,
              ),
              suffixText: _currency == 'IQD' ? 'د.ع' : '\$',
              suffixStyle: TextStyle(
                color: isDark
                    ? AppDarkColors.textSecondary
                    : Colors.grey.shade600,
              ),
              filled: true,
              fillColor: isDark ? AppDarkColors.surface : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'پاشگەزبوونەوە',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.replaceAll(',', '').trim();
                final val = double.tryParse(text);
                Navigator.pop(ctx, val);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('زیادکردن'),
            ),
          ],
        );
      },
    );

    if (result != null && result > 0) {
      setState(() {
        _items.add({
          'name': 'قەرز',
          'price': result,
          'qty': 1,
          'currency': _currency,
        });
      });
    }
  }

  Widget _buildDetailsCard() {
    // Check permission for due date
    final canSetDueDate = context.watch<AuthProvider>().canSetDueDate;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.note_alt_outlined,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'وردەکاری',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppDarkColors.textPrimary : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            maxLines: 2,
            style: TextStyle(color: isDark ? AppDarkColors.textPrimary : null),
            decoration: InputDecoration(
              labelText: AppStrings.description,
              labelStyle: TextStyle(
                color: isDark ? AppDarkColors.textSecondary : null,
              ),
              hintText: 'تێبینی یان وەسفی قەرز...',
              hintStyle: TextStyle(
                color: isDark ? AppDarkColors.textSecondary : null,
              ),
              filled: true,
              fillColor: isDark ? AppDarkColors.inputFill : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: isDark
                    ? BorderSide(color: AppDarkColors.cardBorder)
                    : BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: isDark
                    ? BorderSide(color: AppDarkColors.cardBorder)
                    : BorderSide.none,
              ),
            ),
            validator: (v) => null,
          ),
          // Custom debt date toggle (for backdating)
          if (widget.debt == null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _hasCustomDebtDate
                    ? Colors.orange.withValues(alpha: 0.06)
                    : (isDark ? AppDarkColors.surface : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasCustomDebtDate
                      ? Colors.orange.withValues(alpha: 0.2)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_calendar_rounded,
                    color: _hasCustomDebtDate
                        ? Colors.orange.shade700
                        : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '\u0628\u06d5\u0631\u0648\u0627\u0631\u06cc \u062a\u06c6\u0645\u0627\u0631\u06a9\u0631\u062f\u0646\u06cc \u0642\u06d5\u0631\u0632',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _hasCustomDebtDate
                            ? Colors.orange.shade700
                            : (isDark
                                  ? AppDarkColors.textSecondary
                                  : Colors.grey.shade700),
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: _hasCustomDebtDate,
                      onChanged: (val) {
                        setState(() {
                          _hasCustomDebtDate = val;
                          if (val) {
                            _customDebtDate = DateTime.now();
                          } else {
                            _customDebtDate = null;
                          }
                        });
                      },
                      activeThumbColor: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _hasCustomDebtDate
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _customDebtDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            final now = DateTime.now();
                            setState(
                              () => _customDebtDate = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                                now.hour,
                                now.minute,
                                now.second,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppDarkColors.surface
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_month,
                                color: Colors.orange.shade700,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '\u0628\u06d5\u0631\u0648\u0627\u0631\u06cc \u0642\u06d5\u0631\u0632',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'yyyy/MM/dd',
                                      ).format(_customDebtDate!),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.orange.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                color: Colors.orange.shade700,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
          if (canSetDueDate) ...[
            const SizedBox(height: 16),
            // Toggle for due date
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _hasDueDate
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : (isDark ? AppDarkColors.surface : Colors.grey.shade50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasDueDate
                      ? AppColors.primary.withValues(alpha: 0.2)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    color: _hasDueDate ? AppColors.primary : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'بەرواری دانەوە',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _hasDueDate
                            ? AppColors.primary
                            : (isDark
                                  ? AppDarkColors.textSecondary
                                  : Colors.grey.shade700),
                      ),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: _hasDueDate,
                      onChanged: (val) {
                        setState(() {
                          _hasDueDate = val;
                          if (val) {
                            _dueDate = DateTime.now().add(
                              const Duration(days: 30),
                            );
                          } else {
                            _dueDate = null;
                          }
                        });
                      },
                      activeThumbColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            // Animated date picker
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _hasDueDate
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: InkWell(
                        onTap: _selectDate,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppDarkColors.surface
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                color: AppColors.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AppStrings.dueDate,
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'yyyy/MM/dd',
                                      ).format(_dueDate!),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReceiptCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: Colors.teal.shade600,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'وێنەی وەصڵ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppDarkColors.textPrimary : null,
                ),
              ),
              const Spacer(),
              Text(
                '(ئیختیاری)',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppDarkColors.textSecondary
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_receiptImage != null) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    _receiptImage!,
                    width: double.infinity,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: GestureDetector(
                    onTap: () => setState(() => _receiptImage = null),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                // Compressed size badge
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.compress,
                          color: Colors.greenAccent,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ImageUtils.formatFileSize(
                            _receiptImage!.lengthSync(),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isDark
                        ? AppDarkColors.cardBorder
                        : Colors.grey.shade300,
                    width: 1.5,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  color: isDark ? AppDarkColors.inputFill : Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.add_a_photo_rounded,
                      size: 28,
                      color: isDark
                          ? AppDarkColors.textSecondary
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'وێنەی وەصڵ زیاد بکە',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'کامێرا یان ئەلبوم',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppDarkColors.textSecondary.withValues(alpha: 0.6)
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomAction() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    double totalIQD = 0;
    double totalUSD = 0;
    final dollarRate = double.tryParse(_dollarRateController.text.trim()) ?? 0;
    for (final item in _items) {
      final itemCurrency = item['currency'] as String? ?? _currency;
      final itemTotal = (item['price'] as double) * (item['qty'] as int);
      if (itemCurrency == 'USD') {
        totalUSD += itemTotal;
        if (dollarRate > 0) totalIQD += itemTotal * dollarRate;
      } else {
        totalIQD += itemTotal;
        if (dollarRate > 0) totalUSD += itemTotal / dollarRate;
      }
    }
    final discountIQD =
        ((totalIQD * _discountPercent / 100) * 100).roundToDouble() / 100;
    final grandTotalIQD =
        (totalIQD - discountIQD).clamp(0.0, double.infinity).toDouble();
    final discountUSD = totalUSD * _discountPercent / 100;
    final grandTotalUSD =
        (totalUSD - discountUSD).clamp(0.0, double.infinity).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark
                ? AppDarkColors.cardBorder
                : const Color(0xFFE9EDF3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'کۆی کۆتایی',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppHelpers.formatCurrencyWithType(grandTotalIQD, 'IQD'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF101828),
                  ),
                  textDirection: TextDirection.ltr,
                ),
                if (_discountPercent > 0 && totalIQD > 0)
                  Text(
                    'پێش داشکاندن: ${AppHelpers.formatCurrencyWithType(totalIQD, 'IQD')} • -${AppHelpers.formatCurrencyWithType(discountIQD, 'IQD')}',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                if (grandTotalUSD > 0)
                  Text(
                    AppHelpers.formatCurrencyWithType(grandTotalUSD, 'USD'),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            width: 142,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                widget.debt != null ? 'نوێکردنەوە' : AppStrings.save,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String newText = newValue.text.replaceAll(',', '');

    // Check if it's a valid integer
    if (int.tryParse(newText) == null) {
      return oldValue;
    }

    final formatter = NumberFormat('#,###');
    String formatted = formatter.format(int.parse(newText));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
