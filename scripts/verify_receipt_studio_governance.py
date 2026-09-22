from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


root = Path(__file__).resolve().parents[1]
migration = (root / "supabase/migrations/20260922204314_receipt_studio_history_and_governance.sql").read_text()
settings = (root / "lib/services/receipt_settings_service.dart").read_text()
screen = (root / "lib/screens/admin/receipt_settings_screen.dart").read_text()
debt_pdf = (root / "lib/services/official_receipt_service.dart").read_text()
payment_pdf = (root / "lib/services/payment_receipt_service.dart").read_text()

require("create table if not exists public.receipt_template_versions" in migration,
        "receipt template history table is required")
require("enable row level security" in migration,
        "receipt template history must enable RLS")
require("admin_id = private.current_admin_id()" in migration,
        "receipt history must be tenant isolated")
require("revoke delete on table public.market_receipt_settings" in migration,
        "active receipt settings must not be deletable")
require("Always overwrite client input" in migration,
        "receipt number identity must remain database-owned")
require("ReceiptTemplateVersion" in settings and "restore(" in settings,
        "receipt version history and forward restore service are required")
require("_prefixController" in screen and "_showVersionHistory" in screen,
        "admin receipt studio must expose prefix and version history controls")
require("ReceiptBranding.lockedAttribution" in debt_pdf,
        "debt receipts must render locked ZHIROX attribution")
require("ReceiptBranding.lockedAttribution" in payment_pdf,
        "payment receipts must render locked ZHIROX attribution")
require("سیستەمی بەڕێوەبردنی قەرز (ژیرۆکس)" in settings,
        "locked Kurdish ZHIROX attribution text is missing")

print("Receipt Studio governance verification passed.")
