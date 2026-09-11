from pathlib import Path

path = Path('scripts/verify_online_only.py')
text = path.read_text(encoding='utf-8')
marker = "\n\nif violations:\n"
block = """

# Financial Chat payment confirmation: destructive/full-balance payment actions
# must show a confirmation summary before the live transaction is submitted.
for marker_name in (
    '_confirmFinancialPayment',
    '_buildPaymentConfirmationRow',
    'ماوەی پێش پارەدان',
    'ماوەی دوای پارەدان',
    'پشتڕاستە — تۆمار بکە',
):
    if marker_name not in profile:
        fail(f'Financial Chat payment confirmation marker missing: {marker_name}')
"""
assert marker in text, 'verifier final marker missing'
if '_confirmFinancialPayment' not in text:
    text = text.replace(marker, block + marker, 1)
path.write_text(text, encoding='utf-8')
print('Payment confirmation verifier updated')
