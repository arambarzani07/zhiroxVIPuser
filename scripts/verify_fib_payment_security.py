from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
edge = (ROOT / 'supabase/functions/fib-subscription-payment/index.ts').read_text(encoding='utf-8')
base_migration = (ROOT / 'supabase/migrations/20260911170000_add_fib_subscription_payments.sql').read_text(encoding='utf-8')
completion_migration = (ROOT / 'supabase/migrations/20260911203000_complete_fib_subscription_payment_flow.sql').read_text(encoding='utf-8')
config = (ROOT / 'supabase/config.toml').read_text(encoding='utf-8')
screen = (ROOT / 'lib/screens/admin/subscription_payment_screen.dart').read_text(encoding='utf-8')

for marker in (
    'FIB_CLIENT_ID',
    'FIB_CLIENT_SECRET',
    'client_credentials',
    'admin.auth.getUser(token)',
    'profile.role !== "admin"',
    'verifyProviderPayment',
    'fib_payment_id_mismatch',
    'fib_amount_mismatch',
    'PAYMENT_EXPIRATION',
    'PAYMENT_CANCELLATION',
    'activate_fib_subscription_payment',
    'subscription_activation_failed',
    'extraEmployees',
    '/status`',
):
    if marker not in edge:
        raise SystemExit(f'FIB payment security marker missing: {marker}')

if 'normalizedStatus(callback.status)' in edge:
    raise SystemExit('FIB callback status must be verified with FIB, never trusted directly')

for marker in (
    'create table if not exists public.subscription_payments',
    'enable row level security',
    'admin_id = auth.uid()',
    'security definer',
    'revoke all on function public.activate_fib_subscription_payment',
    'grant execute on function public.activate_fib_subscription_payment(uuid, text) to service_role',
):
    if marker not in base_migration:
        raise SystemExit(f'FIB payment migration security marker missing: {marker}')

for marker in (
    'provider_status',
    'declining_reason',
    'provider_paid_at',
    'last_verified_at',
    'revoke insert, update, delete on public.subscription_payments from authenticated',
):
    if marker not in completion_migration:
        raise SystemExit(f'FIB completion migration marker missing: {marker}')

for marker in (
    'WidgetsBindingObserver',
    '_checkPayment(silent: true)',
    "payment['qr_code']",
    'base64Decode',
    'Clipboard.setData',
):
    if marker not in screen:
        raise SystemExit(f'FIB payment UI completion marker missing: {marker}')

for marker in ('[functions.fib-subscription-payment]', 'verify_jwt = false'):
    if marker not in config:
        raise SystemExit(f'FIB callback configuration marker missing: {marker}')

print('FIB subscription payment security verified')
