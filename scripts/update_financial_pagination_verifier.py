from pathlib import Path
import os

root = Path(os.environ.get('REPO_ROOT', Path.cwd())).resolve()
path = root / 'scripts/verify_online_only.py'
text = path.read_text(encoding='utf-8')
old_realtime = """for marker in (\n    'PBService.getFinancialEvents',\n    \"table: 'financial_events'\",\n    '_hasNewFinancialActivity',\n    '_jumpToLatest',\n    '_buildFinancialSystemMessage',\n):\n"""
new_realtime = """for marker in (\n    'PBService.getCustomerFinancialTimelinePage',\n    \"table: 'financial_events'\",\n    '_hasNewFinancialActivity',\n    '_jumpToLatest',\n    '_buildFinancialSystemMessage',\n):\n"""
if text.count(old_realtime) != 1:
    raise SystemExit(f'realtime verifier anchor count={text.count(old_realtime)}')
text = text.replace(old_realtime, new_realtime, 1)
old_currency = """for marker in (\n    'AppHelpers.debtSummaryInIqd(_debts)',\n    'AppHelpers.formatStoredFinancialAmount',\n    '_buildCurrencySummaryWarning',\n    '_showIncompleteCurrencySummaryMessage',\n):\n"""
new_currency = """for marker in (\n    '_financeTotalDebtIqd',\n    '_financeTotalRemainingIqd',\n    '_financeTotalPaidIqd',\n    '_financeSummaryComplete',\n    'AppHelpers.formatStoredFinancialAmount',\n    '_buildCurrencySummaryWarning',\n    '_showIncompleteCurrencySummaryMessage',\n):\n"""
if text.count(old_currency) != 1:
    raise SystemExit(f'currency verifier anchor count={text.count(old_currency)}')
text = text.replace(old_currency, new_currency, 1)
path.write_text(text, encoding='utf-8')
