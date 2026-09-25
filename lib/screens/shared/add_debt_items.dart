part of 'add_debt_screen.dart';

extension _AddDebtItemsSection on _AddDebtScreenState {
  Widget _buildItemsCard() {
    if (widget.debt == null) return _buildSimpleAmountCard();
    if (!_useItemDetails) return _buildSimpleAmountCard();
    return _buildDetailedItemsCard();
  }

  Widget _buildSimpleAmountCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final presets = _currency == 'IQD'
        ? const <double>[5000, 10000, 25000, 50000, 100000]
        : const <double>[5, 10, 25, 50, 100];
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppDarkColors.cardBorder : const Color(0xFFE9EDF3),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'بڕی قەرز',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'تەنها بڕەکە بنووسە؛ ئەوانی تر ئارەزوومەندانەن',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _amountController,
            focusNode: _amountFocusNode,
            autofocus: widget.customerId != null && widget.debt == null,
            enabled: !_isLoading,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            inputFormatters: [
              if (_currency == 'IQD') ThousandsSeparatorInputFormatter(),
              if (_currency == 'USD')
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              hintText: '0',
              suffixText: _currency == 'IQD' ? 'د.ع' : '\$',
              prefixIcon: const Icon(Icons.payments_outlined),
              filled: true,
              fillColor: isDark ? AppDarkColors.inputFill : const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            validator: (value) {
              if (_useItemDetails) return null;
              final amount = double.tryParse(
                    (value ?? '').replaceAll(',', '').trim(),
                  ) ??
                  0;
              return amount <= 0 ? 'بڕێکی دروست بنووسە' : null;
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: presets
                .map(
                  (amount) => ActionChip(
                    label: Text(
                      AppHelpers.formatCurrencyWithType(amount, _currency),
                    ),
                    onPressed: _isLoading ? null : () => _setSimpleAmount(amount),
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.22),
                    ),
                    backgroundColor: AppColors.primary.withValues(alpha: 0.06),
                  ),
                )
                .toList(),
          ),
          if (widget.debt != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _setDebtEntryState(() {
                      _useItemDetails = true;
                      _items.clear();
                    }),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('وردەکاری کاڵاکان'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedItemsCard() {
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _items.isEmpty
                        ? () => _setDebtEntryState(() => _useItemDetails = false)
                        : null,
                    child: const Text('بڕی تەنها'),
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
                        onPressed: () => _setDebtEntryState(() => _items.removeAt(index)),
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
        _setDebtEntryState(() {
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
      _setDebtEntryState(() {
        _items.add({
          'name': 'قەرز',
          'price': result,
          'qty': 1,
          'currency': _currency,
        });
      });
    }
  }
}
