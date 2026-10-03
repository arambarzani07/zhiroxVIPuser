part of 'add_debt_screen.dart';

extension _AddDebtCustomerSection on _AddDebtScreenState {
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
          if (_selectedCustomerId != null) _buildLimitWarning(),
          if (widget.debt == null) ...[
            const SizedBox(height: 12),
            _buildVisionOcrAction(isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildVisionOcrAction(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppDarkColors.surface
            : AppColors.primary.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.document_scanner_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Google Vision OCR',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppDarkColors.textPrimary
                            : const Color(0xFF344054),
                      ),
                    ),
                    Text(
                      'وەسڵ بخوێنەوە و بڕ و بەروار وەک پێشنیار وەربگرە',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.45,
                        color: isDark
                            ? AppDarkColors.textSecondary
                            : const Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _scanReceiptWithVision,
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('سکانی وەسڵ بە Google Vision'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'OCR هیچ قەرزێک خۆکار تۆمار ناکات؛ پێشنیارەکان دەبێت پەسند بکرێن.',
            style: TextStyle(
              fontSize: 9.5,
              color: isDark
                  ? AppDarkColors.textSecondary
                  : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scanReceiptWithVision() async {
    if (_isLoading) return;

    final previousImage = _receiptImage;
    await _pickImage();
    if (!mounted || _receiptImage == null) return;

    final scanFile = _receiptImage!;
    final size = await scanFile.length();
    if (size <= 0 || size > 8 * 1024 * 1024) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'قەبارەی وێنە بۆ OCR گونجاو نییە. وێنەیەکی بچووکتر هەڵبژێرە.',
          isError: true,
        );
      }
      return;
    }

    final path = scanFile.path.toLowerCase();
    final mimeType = path.endsWith('.png')
        ? 'image/png'
        : path.endsWith('.webp')
            ? 'image/webp'
            : (path.endsWith('.jpg') || path.endsWith('.jpeg'))
                ? 'image/jpeg'
                : null;
    if (mimeType == null) {
      if (mounted) {
        AppHelpers.showSnackBar(
          context,
          'جۆری وێنە بۆ Google Vision پشتگیری ناکرێت. JPG، PNG یان WebP بەکاربهێنە.',
          isError: true,
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final bytes = await scanFile.readAsBytes();
      final response = await PBService.client.functions.invoke(
        'google-vision-ocr',
        body: {
          'imageBase64': base64Encode(bytes),
          'mimeType': mimeType,
          'languageHints': const ['ar', 'en', 'ckb'],
        },
      );

      dynamic raw = response.data;
      if (raw is String && raw.isNotEmpty) {
        try {
          raw = jsonDecode(raw);
        } catch (_) {}
      }
      if (raw is! Map) {
        throw StateError('invalid_ocr_response');
      }
      final result = Map<String, dynamic>.from(raw);
      if (result['error'] != null) {
        throw StateError(result['error'].toString());
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      final accepted = await _showVisionOcrPreview(result);
      if (!mounted) return;
      if (accepted != true && previousImage != null && _receiptImage == null) {
        setState(() => _receiptImage = previousImage);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppHelpers.showSnackBar(
        context,
        _visionOcrErrorMessage(e),
        isError: true,
      );
    }
  }

  String _visionOcrErrorMessage(Object error) {
    final value = error.toString().toLowerCase();
    if (value.contains('google_vision_not_configured')) {
      return 'Google Vision هێشتا لە سێرڤەر چالاک نەکراوە.';
    }
    if (value.contains('unauthorized') || value.contains('401')) {
      return 'دانیشتنت بەسەرچووە. دووبارە بچۆ ژوورەوە.';
    }
    if (value.contains('rate_limited') || value.contains('429')) {
      return 'داواکاری OCR زۆر بووە. کەمێک دواتر دووبارە هەوڵ بدە.';
    }
    if (value.contains('timeout') || value.contains('504')) {
      return 'Google Vision وەڵامی نەدایەوە. دووبارە هەوڵ بدە.';
    }
    if (value.contains('image_too_large') || value.contains('413')) {
      return 'وێنەکە زۆر گەورەیە بۆ OCR.';
    }
    return 'نەتوانرا وێنەکە بە Google Vision بخوێندرێتەوە.';
  }

  Future<bool?> _showVisionOcrPreview(Map<String, dynamic> result) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = (result['text'] ?? '').toString().trim();
    final suggestedRaw = result['suggested'];
    final suggested = suggestedRaw is Map
        ? Map<String, dynamic>.from(suggestedRaw)
        : <String, dynamic>{};
    final amountRaw = suggested['amount'];
    final amountMap = amountRaw is Map
        ? Map<String, dynamic>.from(amountRaw)
        : <String, dynamic>{};
    final amount = (amountMap['value'] as num?)?.toDouble();
    final currency = amountMap['currency']?.toString();
    final dateText = suggested['date']?.toString();
    final parsedDate = dateText == null ? null : DateTime.tryParse(dateText);
    final confidence = (result['confidence'] as num?)?.toDouble();

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? AppDarkColors.card : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.document_scanner_rounded, color: AppColors.primary),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'پێشبینینی OCR',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          amount != null && amount > 0
                              ? 'بڕی پێشنیارکراو: ${AppHelpers.formatCurrencyWithType(amount, currency == 'USD' ? 'USD' : _currency)}'
                              : 'بڕێکی دڵنیابوونەوەی پێکراو نەدۆزرایەوە',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (dateText != null && dateText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('بەرواری دۆزراوە: $dateText'),
                        ],
                        if (confidence != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'دڵنیایی OCR: ${(confidence * 100).clamp(0, 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'دەقی خوێندراوە',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppDarkColors.inputFill
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      text.isEmpty
                          ? 'هیچ دەقێک نەخوێندرایەوە.'
                          : (text.length > 1800
                              ? '${text.substring(0, 1800)}…'
                              : text),
                      style: const TextStyle(fontSize: 11.5, height: 1.55),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'تێبینی: ئەمانە تەنها پێشنیارن؛ پێش پاشەکەوتکردن بڕ و بەروار بپشکنە.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.orange,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('تەنها وێنەکە بهێڵەوە'),
            ),
            ElevatedButton.icon(
              onPressed: amount == null || amount <= 0
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.check_rounded, size: 17),
              label: const Text('پێشنیارەکان بەکاربهێنە'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (accepted == true && amount != null && amount > 0 && mounted) {
      if (currency == 'USD' || currency == 'IQD') {
        setState(() => _currency = currency!);
      }
      _setSimpleAmount(amount);
      if (parsedDate != null && !parsedDate.isAfter(DateTime.now())) {
        final now = DateTime.now();
        setState(() {
          _hasCustomDebtDate = true;
          _customDebtDate = DateTime(
            parsedDate.year,
            parsedDate.month,
            parsedDate.day,
            now.hour,
            now.minute,
            now.second,
          );
          _showAdvancedDetails = true;
        });
      }
      AppHelpers.showSnackBar(
        context,
        'پێشنیارەکانی OCR دانران؛ پێش پاشەکەوتکردن بپشکنە.',
      );
    }
    return accepted;
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

    if (selectedValue != null &&
        (widget.customerId != null || widget.debt != null)) {
      final customer = _customers.firstWhere((c) => c.id == selectedValue);
      final fullName = [
        customer.getStringValue('name'),
        customer.getStringValue('father_name'),
      ].where((part) => part.trim().isNotEmpty).join(' ');
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: isDark ? AppDarkColors.inputFill : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE4E7EC),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

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
          ? (v) => _setDebtEntryState(() => _selectedCustomerId = v)
          : null,
      validator: (v) => v == null ? 'کڕیارێک هەڵبژێرە' : null,
    );
  }

  bool _isOverLimit(RecordModel customer) {
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
                  onPressed: () => _setDebtEntryState(() {}),
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
}
