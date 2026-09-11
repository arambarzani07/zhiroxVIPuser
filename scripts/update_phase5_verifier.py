from pathlib import Path

path = Path('scripts/verify_online_only.py')
text = path.read_text(encoding='utf-8')
old = """# Financial Chat Phase 7: ledger intelligence, overdue visibility, targeted
# quick-pay and filter-aware PDF export must stay integrated in the customer chat.
for marker in (
    '_financialRunningBalances',
    '_timelineAmountInIqd',
    '_overdueDebtLabel',
    'ماوەی هەژمار',
    'پارەدانەوەی خێرا',
    'initialDebtId',
    '_generateFilteredFinancialChatStatement',
    'PdfService.generateFinancialChatStatement',
):
"""
new = """# Financial Chat ledger intelligence, overdue visibility, targeted payment
# and filter-aware PDF export must stay integrated in the customer chat.
for marker in (
    '_financialRunningBalances',
    '_timelineAmountInIqd',
    '_overdueDebtLabel',
    'ماوەی هەژمار',
    'پارەدانەوەی تەواو',
    'initialDebtId',
    'initialAmount',
    "const Text('25%')",
    "const Text('50%')",
    "const Text('تەواو')",
    "case 'pay_full':",
    '_generateFilteredFinancialChatStatement',
    'PdfService.generateFinancialChatStatement',
):
"""
assert old in text, 'Financial Chat verifier block not found'
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Phase 5 verifier updated')
