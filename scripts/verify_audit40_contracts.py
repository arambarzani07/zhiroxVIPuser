#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

pb = (ROOT / "lib/services/pb_service.dart").read_text(errors="ignore")
profile = (ROOT / "lib/screens/shared/user_profile_screen.dart").read_text(errors="ignore")
compat = (ROOT / "lib/services/supabase_compat.dart").read_text(errors="ignore")
gateway = (ROOT / "supabase/functions/debt-restore-admin/index.ts").read_text(errors="ignore")
migrations = "\n".join(
    p.read_text(errors="ignore")
    for p in sorted((ROOT / "supabase/migrations").glob("*audit40*.sql"))
)

assert "deleteGeneralPayment(String id)" in pb
assert "'delete_general_payment'" in pb
assert "'general_payment_id': id" in pb

assert "if (action === 'delete_general_payment')" in gateway
assert "'delete_general_payment_service'" in gateway
assert "p_general_payment_id: generalPaymentId" in gateway

assert "_deleteFinancialPayment" in profile
assert "PBService.deleteGeneralPayment(item.record.id)" in profile
assert "auth.userRole == 'admin' && item.isPayment" in profile

assert "receipt_url_not_signed" in compat
assert "getPublicUrl(filename)" not in compat
assert "receipt_image_unavailable" in compat

assert "delete_general_payment_service" in migrations
assert "get_customer_virtual_debt_balances" in migrations
assert "get_effective_installment_remaining" in migrations
assert "audit40" not in profile.lower(), "debug audit marker leaked into customer UI"

print("audit40 source contracts verified")
