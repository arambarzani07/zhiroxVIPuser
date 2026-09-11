from pathlib import Path

path = Path('lib/screens/shared/user_profile_screen.dart')
text = path.read_text(encoding='utf-8')
original = text

old = """  Future<void> _showFinancialPaymentSheet(\n    AuthProvider auth, {\n    String? initialDebtId,\n  }) async {\n"""
new = """  Future<void> _showFinancialPaymentSheet(\n    AuthProvider auth, {\n    String? initialDebtId,\n    double? initialAmount,\n  }) async {\n"""
assert old in text, 'payment sheet signature marker missing'
text = text.replace(old, new, 1)

old = """    final amountController = TextEditingController();\n    final noteController = TextEditingController();\n    String selectedDebtId = openDebts.first.id;\n    if (initialDebtId != null &&\n        openDebts.any((debt) => debt.id == initialDebtId)) {\n      selectedDebtId = initialDebtId;\n    }\n    var saving = false;\n"""
new = """    String inputAmountText(double value) {\n      if (value == value.roundToDouble()) return value.toInt().toString();\n      return value.toStringAsFixed(2);\n    }\n\n    final amountController = TextEditingController();\n    final noteController = TextEditingController();\n    String selectedDebtId = openDebts.first.id;\n    if (initialDebtId != null &&\n        openDebts.any((debt) => debt.id == initialDebtId)) {\n      selectedDebtId = initialDebtId;\n    }\n    if (initialAmount != null && initialAmount > 0) {\n      final selectedDebt = openDebts.firstWhere(\n        (debt) => debt.id == selectedDebtId,\n        orElse: () => openDebts.first,\n      );\n      final remaining = selectedDebt.getDoubleValue('remaining');\n      final safeAmount = initialAmount.clamp(0.0, remaining).toDouble();\n      if (safeAmount > 0) amountController.text = inputAmountText(safeAmount);\n    }\n    var saving = false;\n"""
assert old in text, 'payment setup marker missing'
text = text.replace(old, new, 1)

old = """              final remaining = selectedDebt.getDoubleValue('remaining');\n              return Container(\n"""
new = """              final remaining = selectedDebt.getDoubleValue('remaining');\n\n              void applyQuickAmount(double value) {\n                final safeValue = value.clamp(0.0, remaining).toDouble();\n                amountController.text = inputAmountText(safeValue);\n                amountController.selection = TextSelection.collapsed(\n                  offset: amountController.text.length,\n                );\n                setSheetState(() => localError = null);\n              }\n\n              return Container(\n"""
assert old in text, 'remaining marker missing'
text = text.replace(old, new, 1)

old = """                                setSheetState(() {\n                                  selectedDebtId = value;\n                                  localError = null;\n                                });\n"""
new = """                                amountController.clear();\n                                setSheetState(() {\n                                  selectedDebtId = value;\n                                  localError = null;\n                                });\n"""
assert old in text, 'debt dropdown marker missing'
text = text.replace(old, new, 1)

old = """                      const SizedBox(height: 12),\n                      TextField(\n                        controller: noteController,\n"""
new = """                      const SizedBox(height: 9),\n                      Row(\n                        children: [\n                          Expanded(\n                            child: OutlinedButton(\n                              onPressed: saving\n                                  ? null\n                                  : () => applyQuickAmount(remaining * 0.25),\n                              style: OutlinedButton.styleFrom(\n                                visualDensity: VisualDensity.compact,\n                                padding: const EdgeInsets.symmetric(vertical: 10),\n                              ),\n                              child: const Text('25%'),\n                            ),\n                          ),\n                          const SizedBox(width: 7),\n                          Expanded(\n                            child: OutlinedButton(\n                              onPressed: saving\n                                  ? null\n                                  : () => applyQuickAmount(remaining * 0.50),\n                              style: OutlinedButton.styleFrom(\n                                visualDensity: VisualDensity.compact,\n                                padding: const EdgeInsets.symmetric(vertical: 10),\n                              ),\n                              child: const Text('50%'),\n                            ),\n                          ),\n                          const SizedBox(width: 7),\n                          Expanded(\n                            child: FilledButton.tonal(\n                              onPressed: saving\n                                  ? null\n                                  : () => applyQuickAmount(remaining),\n                              style: FilledButton.styleFrom(\n                                visualDensity: VisualDensity.compact,\n                                padding: const EdgeInsets.symmetric(vertical: 10),\n                              ),\n                              child: const Text('تەواو'),\n                            ),\n                          ),\n                        ],\n                      ),\n                      const SizedBox(height: 12),\n                      TextField(\n                        controller: noteController,\n"""
assert old in text, 'note field marker missing'
text = text.replace(old, new, 1)

old = """                            _showFinancialPaymentSheet(\n                              auth,\n                              initialDebtId: record.id,\n                            ),\n"""
new = """                            _showFinancialPaymentSheet(\n                              auth,\n                              initialDebtId: record.id,\n                              initialAmount: record.getDoubleValue('remaining'),\n                            ),\n"""
assert old in text, 'quick pay bubble marker missing'
text = text.replace(old, new, 1)

old = """                          label: const Text('پارەدانەوەی خێرا'),\n"""
new = """                          label: const Text('پارەدانەوەی تەواو'),\n"""
assert old in text, 'quick pay label marker missing'
text = text.replace(old, new, 1)

old = """              if (auth.userRole != 'customer')\n                ListTile(\n                  leading: const Icon(Icons.reply_rounded),\n                  title: const Text('وەک وەڵام / پەیوەستکردن'),\n                  subtitle: const Text('مامەڵەی نوێ بە ئەم مامەڵەیەوە ببەستە'),\n                  onTap: () => Navigator.pop(sheetContext, 'reference'),\n                ),\n"""
new = """              if (auth.userRole != 'customer')\n                ListTile(\n                  leading: const Icon(Icons.reply_rounded),\n                  title: const Text('وەک وەڵام / پەیوەستکردن'),\n                  subtitle: const Text('مامەڵەی نوێ بە ئەم مامەڵەیەوە ببەستە'),\n                  onTap: () => Navigator.pop(sheetContext, 'reference'),\n                ),\n              if (auth.userRole != 'customer' &&\n                  debt != null &&\n                  debt.getDoubleValue('remaining') > 0)\n                ListTile(\n                  leading: Icon(\n                    Icons.done_all_rounded,\n                    color: Colors.green.shade700,\n                  ),\n                  title: const Text('پارەدانەوەی تەواوی ماوە'),\n                  subtitle: Text(\n                    AppHelpers.formatCurrencyWithType(\n                      debt.getDoubleValue('remaining'),\n                      currency,\n                    ),\n                    textDirection: TextDirection.ltr,\n                  ),\n                  onTap: () => Navigator.pop(sheetContext, 'pay_full'),\n                ),\n"""
assert old in text, 'transaction action marker missing'
text = text.replace(old, new, 1)

old = """      case 'details':\n        await _openTimelineItem(item);\n        break;\n      case 'receipt':\n"""
new = """      case 'details':\n        await _openTimelineItem(item);\n        break;\n      case 'pay_full':\n        if (debt != null && debt.getDoubleValue('remaining') > 0) {\n          await _showFinancialPaymentSheet(\n            auth,\n            initialDebtId: debt.id,\n            initialAmount: debt.getDoubleValue('remaining'),\n          );\n        }\n        break;\n      case 'receipt':\n"""
assert old in text, 'transaction action switch marker missing'
text = text.replace(old, new, 1)

assert text != original
path.write_text(text, encoding='utf-8')
print('Financial Chat Phase 5 applied')
