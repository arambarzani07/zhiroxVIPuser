from pathlib import Path
import re

path = Path('lib/screens/shared/add_debt_screen.dart')
text = path.read_text()

# Lifecycle hardening for async UI updates.
text = text.replace(
    "    setState(() => _loadingCustomers = false);\n",
    "    if (mounted) setState(() => _loadingCustomers = false);\n",
)
text = text.replace(
    "      setState(() {\n        _receiptImage = compressed ?? originalFile;\n      });\n",
    "      if (!mounted) return;\n      setState(() {\n        _receiptImage = compressed ?? originalFile;\n      });\n",
)
text = text.replace(
    "    setState(() => _isLoading = false);\n  }\n\n  @override\n  Widget build(BuildContext context)",
    "    if (mounted) setState(() => _isLoading = false);\n  }\n\n  @override\n  Widget build(BuildContext context)",
)

# Replace the tall gradient/scrolled-save layout with a compact form + sticky action bar.
start = text.index('  @override\n  Widget build(BuildContext context) {')
end = text.index('\n  Widget _buildCustomerSelector()', start)
new_build = r'''  @override
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
'''
text = text[:start] + new_build + text[end:]

# Normalize primary form cards: smaller radius/padding, borders instead of floating shadows.
card_pattern = re.compile(
    r"      decoration: BoxDecoration\(\n"
    r"        color: isDark \? AppDarkColors\.card : Colors\.white,\n"
    r"        borderRadius: BorderRadius\.circular\(20\),\n"
    r"        boxShadow: isDark\n"
    r"            \? \[\]\n"
    r"            : \[\n"
    r"                BoxShadow\([\s\S]*?\n"
    r"              \],\n"
    r"      \),\n"
    r"      padding: const EdgeInsets\.all\(20\),"
)
card_replacement = '''      decoration: BoxDecoration(
        color: isDark ? AppDarkColors.card : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppDarkColors.cardBorder
              : const Color(0xFFE9EDF3),
        ),
      ),
      padding: const EdgeInsets.all(14),'''
text = card_pattern.sub(card_replacement, text)

# Compact common section spacing/headers without changing form logic.
text = text.replace('          const SizedBox(height: 16),\n          _loadingCustomers', '          const SizedBox(height: 10),\n          _loadingCustomers')
text = text.replace('          const SizedBox(height: 16),\n          Container(\n            decoration: BoxDecoration(\n              color: isDark ? AppDarkColors.surface', '          const SizedBox(height: 10),\n          Container(\n            decoration: BoxDecoration(\n              color: isDark ? AppDarkColors.surface')
text = text.replace("                  const Text(\n                    'تێچوونەکان',\n                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),\n                  ),", "                  const Text(\n                    'قەرز / کاڵاکان',\n                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),\n                  ),")
text = text.replace('              padding: const EdgeInsets.symmetric(vertical: 30),', '              padding: const EdgeInsets.symmetric(vertical: 18),')
text = text.replace('                    size: 48,', '                    size: 34,', 1)

# Compact receipt uploader/preview.
text = text.replace('                    height: 200,\n                    fit: BoxFit.cover,', '                    height: 96,\n                    fit: BoxFit.cover,')
text = text.replace('                padding: const EdgeInsets.symmetric(vertical: 32),', '                padding: const EdgeInsets.symmetric(vertical: 18),')
text = text.replace('                      size: 36,', '                      size: 28,')
text = text.replace("                    const SizedBox(height: 10),\n                    Text(\n                      'وێنەی وەصڵ زیاد بکە',", "                    const SizedBox(height: 7),\n                    Text(\n                      'وێنەی وەصڵ زیاد بکە',")

# Replace the large in-scroll totals card with a sticky compact total + save bar.
bottom_start = text.index('  Widget _buildBottomAction() {')
bottom_end = text.index('\n}\n\nclass ThousandsSeparatorInputFormatter', bottom_start)
new_bottom = r'''  Widget _buildBottomAction() {
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
                  'کۆی گشتی',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark
                        ? AppDarkColors.textSecondary
                        : const Color(0xFF98A2B3),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppHelpers.formatCurrencyWithType(totalIQD, 'IQD'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF101828),
                  ),
                  textDirection: TextDirection.ltr,
                ),
                if (totalUSD > 0)
                  Text(
                    AppHelpers.formatCurrencyWithType(totalUSD, 'USD'),
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
'''
text = text[:bottom_start] + new_bottom + text[bottom_end:]

path.write_text(text)
