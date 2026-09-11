from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
edge = (ROOT / 'supabase/functions/fib-subscription-payment/index.ts').read_text(encoding='utf-8')
migration = (ROOT / 'supabase/migrations/20260911170000_add_fib_subscription_payments.sql').read_text(encoding='utf-8')
config = (ROOT / 'supabase/config.toml').read_text(encoding='utf-8')

for marker in (
    'FIB_CLIENT_ID',
    'FIB_CLIENT_SECRET',
    'client_credentials',
    'admin.auth.getUser(token)',
    'profile.role !== "admin"',
    '/status`',
    'activate_fib_subscription_payment',
    'extraEmployees',
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
    if marker not in migration:
        raise SystemExit(f'FIB payment migration security marker missing: {marker}')

for marker in ('[functions.fib-subscription-payment]', 'verify_jwt = false'):
    if marker not in config:
        raise SystemExit(f'FIB callback configuration marker missing: {marker}')

print('FIB subscription payment security verified')
