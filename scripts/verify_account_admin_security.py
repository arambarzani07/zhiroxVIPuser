from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source_path = ROOT / 'supabase/functions/account-admin/index.ts'
text = source_path.read_text(encoding='utf-8')
delete_text = (ROOT / 'supabase/functions/delete-account/index.ts').read_text(encoding='utf-8')
update_text = (ROOT / 'supabase/functions/update-account/index.ts').read_text(encoding='utf-8')
migration_text = (
    ROOT / 'supabase/migrations/20260911133708_enforce_operational_access_and_audit_privileges.sql'
).read_text(encoding='utf-8')

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
    'async function isOperational(',
    '.select("receipt_image_path")',
    'row.receipt_image_path',
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

if '.select("receipt_image")' in text or '.select("receipt_image")' in delete_text:
    raise SystemExit('stale receipt_image database column returned')
if 'async function isOperational(' not in update_text:
    raise SystemExit('update-account operational authorization missing')
for marker in (
    'p.active = true',
    'p.approved = true',
    'tenant.subscription_end >= now()',
    'revoke all privileges on table public.financial_events from authenticated;',
    'grant select on table public.financial_events to authenticated;',
):
    if marker not in migration_text:
        raise SystemExit(f'operational access migration marker missing: {marker}')

print('account-admin security boundaries verified')
