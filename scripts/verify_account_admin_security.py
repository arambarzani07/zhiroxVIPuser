from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source_path = ROOT / 'supabase/functions/account-admin/index.ts'
text = source_path.read_text(encoding='utf-8')

required = (
    'let debtLimit = 0;',
    'const debtDuration = 30;',
    'let canAddCustomers = false;',
    'let canSetDebtLimit = false;',
    'let canSetDueDate = false;',
    'let canEditDebts = false;',
    'let canSendNotifications = false;',
    'requesterProfile.can_set_debt_limit === true',
    'debt_limit: debtLimit,',
    'debt_duration: debtDuration,',
    'can_add_customers: canAddCustomers,',
    'can_set_debt_limit: canSetDebtLimit,',
    'can_set_due_date: canSetDueDate,',
    'can_edit_debts: canEditDebts,',
    'can_send_notifications: canSendNotifications,',
)
for marker in required:
    if marker not in text:
        raise SystemExit(f'account-admin security marker missing: {marker}')

forbidden = (
    'debt_limit: Number(body.debt_limit',
    'debt_duration: Number(body.debt_duration',
    'can_add_customers: Boolean(body.can_add_customers',
    'can_set_debt_limit: Boolean(body.can_set_debt_limit',
    'can_set_due_date: Boolean(body.can_set_due_date',
    'can_edit_debts: Boolean(body.can_edit_debts',
    'can_send_notifications: Boolean(body.can_send_notifications',
)
for marker in forbidden:
    if marker in text:
        raise SystemExit(f'account-admin raw sensitive-field mapping returned: {marker}')

print('account-admin security boundaries verified')
