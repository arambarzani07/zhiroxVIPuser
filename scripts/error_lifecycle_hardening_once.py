from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')

# ---- Add Debt ----
add_path = root / 'lib/screens/shared/add_debt_screen.dart'
add = add_path.read_text(encoding='utf-8')

add = add.replace(
    "          'هەڵە لە کردنەوەی کامێرا: $e',\n",
    "          AppHelpers.backendErrorMessage(\n            e,\n            fallback: 'نەتوانرا وێنە هەڵبژێردرێت. دووبارە هەوڵ بدە.',\n          ),\n",
    1,
)
add = add.replace(
    "        AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);\n",
    "        AppHelpers.showSnackBar(\n          context,\n          AppHelpers.backendErrorMessage(\n            e,\n            fallback: 'نەتوانرا قەرزەکە پاشەکەوت بکرێت. دووبارە هەوڵ بدە.',\n          ),\n          isError: true,\n        );\n",
    1,
)
add_path.write_text(add, encoding='utf-8')

# ---- Debt Detail ----
detail_path = root / 'lib/screens/shared/debt_detail_screen.dart'
detail = detail_path.read_text(encoding='utf-8')

detail = detail.replace(
    "  bool _isLoading = true;\n  bool _isSaving = false;\n",
    "  bool _isLoading = true;\n  String? _loadError;\n",
    1,
)

old_load = '''  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _debt = await PBService.getDebt(widget.debtId);
      _payments = await PBService.getPayments(debtId: widget.debtId);
    } catch (_) {}
    setState(() => _isLoading = false);
    _animController.forward(from: 0);
  }
'''
new_load = '''  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final debt = await PBService.getDebt(widget.debtId);
      final payments = await PBService.getPayments(debtId: widget.debtId);
      if (!mounted) return;

      setState(() {
        _debt = debt;
        _payments = payments;
        _isLoading = false;
        _loadError = null;
      });
      _animController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _debt = null;
        _payments = [];
        _isLoading = false;
        _loadError = AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا وردەکاری قەرز لە سێرڤەر وەربگیرێت. دووبارە هەوڵ بدە.',
        );
      });
    }
  }
'''
if old_load not in detail:
    raise RuntimeError('DebtDetail _loadData marker not found')
detail = detail.replace(old_load, new_load, 1)

old_action = '''  Future<void> _handleDebtAction(String action) async {
    switch (action) {
      case 'print':
        await _printDebtInvoice();
        break;
      case 'edit':
        await _editCurrentDebt();
        break;
      case 'delete':
        if (mounted) _confirmDelete();
        break;
    }
  }
'''
new_action = '''  Future<void> _handleDebtAction(String action) async {
    try {
      switch (action) {
        case 'print':
          await _printDebtInvoice();
          break;
        case 'edit':
          await _editCurrentDebt();
          break;
        case 'delete':
          await _confirmDelete();
          break;
      }
    } catch (e) {
      if (!mounted) return;
      AppHelpers.showSnackBar(
        context,
        AppHelpers.backendErrorMessage(
          e,
          fallback: 'نەتوانرا کردارەکە ئەنجام بدرێت. دووبارە هەوڵ بدە.',
        ),
        isError: true,
      );
    }
  }
'''
if old_action not in detail:
    raise RuntimeError('DebtDetail action marker not found')
detail = detail.replace(old_action, new_action, 1)

load_error_ui = '''
    if (_loadError != null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppDarkColors.background
            : const Color(0xFFF5F7FA),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42, color: Colors.orange),
                const SizedBox(height: 12),
                Text(
                  _loadError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.6,
                    color: isDark
                        ? AppDarkColors.textPrimary
                        : const Color(0xFF344054),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('دووبارە هەوڵ بدە'),
                ),
              ],
            ),
          ),
        ),
      );
    }

'''
needle = "    if (_debt == null) {\n"
if needle not in detail:
    raise RuntimeError('DebtDetail missing debt UI marker')
detail = detail.replace(needle, load_error_ui + needle, 1)

detail = detail.replace(
    "  void _confirmDelete() async {\n",
    "  Future<void> _confirmDelete() async {\n",
    1,
)
detail = detail.replace(
    "    if (confirm) {\n      try {\n        await context.read<DebtProvider>().removeDebt(widget.debtId);\n",
    "    if (!mounted || !confirm) return;\n    try {\n      await context.read<DebtProvider>().removeDebt(widget.debtId);\n",
    1,
)
detail = detail.replace(
    "        if (mounted) Navigator.pop(context);\n      } catch (e) {\n        if (mounted) {\n          AppHelpers.showSnackBar(context, 'هەڵە: $e', isError: true);\n        }\n      }\n    }\n  }\n\n  void _showAddPaymentDialog() {\n",
    "      if (mounted) Navigator.pop(context);\n    } catch (e) {\n      if (!mounted) return;\n      AppHelpers.showSnackBar(\n        context,\n        AppHelpers.backendErrorMessage(\n          e,\n          fallback: 'نەتوانرا قەرزەکە بسڕدرێتەوە. دووبارە هەوڵ بدە.',\n        ),\n        isError: true,\n      );\n    }\n  }\n\n  Future<void> _showAddPaymentDialog() async {\n",
    1,
)

detail = detail.replace(
    "    final dollarRate = _debt!.getDoubleValue('dollar_rate');\n\n    showModalBottomSheet(\n",
    "    final dollarRate = _debt!.getDoubleValue('dollar_rate');\n    bool isSubmitting = false;\n\n    await showModalBottomSheet(\n",
    1,
)
detail = detail.replace(
    "                      onPressed: _isSaving\n                          ? null\n                          : () async {\n                              if (!formKey.currentState!.validate()) return;\n                              setState(() => _isSaving = true);\n",
    "                      onPressed: isSubmitting\n                          ? null\n                          : () async {\n                              if (!formKey.currentState!.validate()) return;\n                              setSheetState(() => isSubmitting = true);\n",
    1,
)
detail = detail.replace(
    "                                // Close dialog IMMEDIATELY\n                                if (mounted) {\n                                  Navigator.pop(sheetCtx);\n                                  AppHelpers.showSnackBar(\n                                    context,\n                                    'پارەدانەوە تۆمارکرا',\n                                  );\n                                  _loadData();\n                                }\n                              } catch (e) {\n                                _isSaving = false;\n                                if (mounted) {\n                                  AppHelpers.showSnackBar(\n                                    context,\n                                    'هەڵە: $e',\n                                    isError: true,\n                                  );\n                                }\n                              }\n",
    "                                if (!mounted) return;\n                                if (sheetCtx.mounted) {\n                                  Navigator.pop(sheetCtx);\n                                }\n                                AppHelpers.showSnackBar(\n                                  context,\n                                  'پارەدانەوە تۆمارکرا',\n                                );\n                                await _loadData();\n                              } catch (e) {\n                                if (sheetCtx.mounted) {\n                                  setSheetState(() => isSubmitting = false);\n                                }\n                                if (!mounted) return;\n                                AppHelpers.showSnackBar(\n                                  context,\n                                  AppHelpers.backendErrorMessage(\n                                    e,\n                                    fallback: 'نەتوانرا پارەدانەوە تۆمار بکرێت. دووبارە هەوڵ بدە.',\n                                  ),\n                                  isError: true,\n                                );\n                              }\n",
    1,
)
# Dispose temporary field controllers when the sheet is actually closed.
detail = detail.replace(
    "      ),\n    );\n  }\n\n  Widget _buildQuickPayBtn(\n",
    "      ),\n    );\n    amountController.dispose();\n    noteController.dispose();\n  }\n\n  Widget _buildQuickPayBtn(\n",
    1,
)

detail_path.write_text(detail, encoding='utf-8')

# ---- Permanent online-only verifier ----
verify_path = root / 'scripts/verify_online_only.py'
verify = verify_path.read_text(encoding='utf-8')
verify = verify.replace(
    "r'Future<void>\\s+_loadCustomers\\(\\)\\s+async\\s*\\{(.*?)(?=\n\\s*@override\n\\s*void dispose)'",
    "r'Future<void>\\s+_loadCustomers\\(\\)\\s+async\\s*\\{(.*?)(?=\\s*@override\\s*void dispose)'",
)
verify = verify.replace(
    "r'Future<_RelationContext>\\s+_contextFor\\([^)]*\\)\\s+async\\s*\\{(.*?)(?=\n\\s*Map<String, dynamic>\\s+_writeMap)'",
    "r'Future<_RelationContext>\\s+_contextFor\\([^)]*\\)\\s+async\\s*\\{(.*?)(?=\\s*Map<String, dynamic>\\s+_writeMap)'",
)

extra = '''

# User-facing screens must not expose raw backend exception text, and debt detail
# must preserve an explicit retryable load-error state.
detail = (LIB / 'screens/shared/debt_detail_screen.dart').read_text(encoding='utf-8')
for rel, source in (
    ('lib/screens/shared/add_debt_screen.dart', add_debt),
    ('lib/screens/shared/debt_detail_screen.dart', detail),
):
    for raw_marker in ("'هەڵە: $e'", "هەڵە لە کردنەوەی کامێرا: $e"):
        if raw_marker in source:
            fail(f'{rel}: raw backend exception text must not be shown to users')
for marker in ('String? _loadError', 'AppHelpers.backendErrorMessage', 'دووبارە هەوڵ بدە'):
    if marker not in detail:
        fail(f'lib/screens/shared/debt_detail_screen.dart: lifecycle/error marker missing: {marker}')
'''
marker = "\n\nif violations:\n"
if extra.strip() not in verify:
    if marker not in verify:
        raise RuntimeError('Verifier final marker not found')
    verify = verify.replace(marker, extra + marker, 1)
verify_path.write_text(verify, encoding='utf-8')

print('Error normalization, lifecycle hardening, and verifier repair applied.')
