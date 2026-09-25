#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = (
    ROOT / "supabase/migrations/20260925191214_general_payment_outbound_sync.sql"
).read_text(errors="ignore")
outbound = (
    ROOT / "supabase/functions/daftar-outbound-sync/index.ts"
).read_text(errors="ignore")
inbound = (
    ROOT / "supabase/functions/daftar-sync/index.ts"
).read_text(errors="ignore")

for marker in (
    "tg_table_name = 'customer_general_payments'",
    "'payment_scope', 'general'",
    "'source_table', 'customer_general_payments'",
    "daftar_outbound_general_payment_mutation",
    "after insert or update or delete on public.customer_general_payments",
    "apply_daftar_inbound_general_payment_update",
    "join public.customer_general_payments g on g.id = l.target_id",
    "set_config('zhirox.daftar_inbound', 'on', true)",
    "from public.customer_general_payments g",
):
    assert marker in migration, marker

for marker in (
    "isGeneralPaymentSnapshot",
    '"customer_general_payments"',
    'payment_scope ?? ""',
    'transactionType: "PAYMENT"',
    'customer_mapping_pending',
):
    assert marker in outbound, marker

for marker in (
    "mappedGeneralPaymentTarget",
    '"apply_daftar_inbound_general_payment_update"',
    "general_payment_update_failed",
    '"payment_allocation"',
    "generalPaymentTargetId",
):
    assert marker in inbound, marker

print("Daftar general-payment outbound/inbound contract verified")
