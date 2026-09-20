from pathlib import Path

pb = Path('lib/services/pb_service.dart').read_text()

required_operations = (
    "'customer_directory'",
    "'customer_finance_snapshot'",
    "'customer_timeline'",
    "'customer_debts_page'",
    "'debt_detail'",
    "'debt_payments'",
    "'customer_all_debts'",
)

assert "DaftarLiveReadService" in pb
for operation in required_operations:
    assert operation in pb, f"missing live-read operation {operation}"

print("Daftar customer live-read integration verified.")
