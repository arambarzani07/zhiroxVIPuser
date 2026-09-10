from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')
path = root / 'lib/screens/shared/add_debt_screen.dart'
text = path.read_text()
replacements = {
    "'بەکارهێنەر سنوری قەرزی تێپەڕاندووە.\n'": "'بەکارهێنەر سنوری قەرزی تێپەڕاندووە.\\n'",
    "'سنور: ${AppHelpers.formatCurrency(debtLimit)}\n'": "'سنور: ${AppHelpers.formatCurrency(debtLimit)}\\n'",
    "'کۆی گشتی: ${AppHelpers.formatCurrency(currentBalance + totalNewDebt)}\n\n'": "'کۆی گشتی: ${AppHelpers.formatCurrency(currentBalance + totalNewDebt)}\\n\\n'",
    "'ناتوانیت ئەم قەرزە زیاد بکەیت! بەکارهێنەر سنوری قەرزی تێپەڕاندووە.\n'": "'ناتوانیت ئەم قەرزە زیاد بکەیت! بەکارهێنەر سنوری قەرزی تێپەڕاندووە.\\n'",
}
changed = 0
for old, new in replacements.items():
    count = text.count(old)
    if count:
        text = text.replace(old, new)
        changed += count
if changed < 4:
    raise RuntimeError(f'Expected malformed debt-limit strings, fixed {changed}')
path.write_text(text)
