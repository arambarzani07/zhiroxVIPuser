from pathlib import Path

pb = Path('lib/services/pb_service.dart').read_text(encoding='utf-8')

for operation in (
    "'admin_dashboard'",
    "'admin_all_debts'",
    "'employee_stats'",
):
    assert operation in pb, f"missing {operation}"

assert "static Future<Map<String, dynamic>> getDashboardStats" in pb
assert "static Future<List<RecordModel>> getAllAdminDebts" in pb
assert "static Future<Map<String, double>> getEmployeeStats" in pb

print("Daftar admin live-read contract passed.")
