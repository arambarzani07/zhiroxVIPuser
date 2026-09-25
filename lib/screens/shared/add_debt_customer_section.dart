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
}
