from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
migration = ROOT / "supabase/migrations/20260923143704_fix_financial_events_tenant_isolation.sql"
sql = migration.read_text(errors="ignore")

required = (
    "drop policy if exists financial_events_permission_read",
    "create policy financial_events_permission_read",
    "for select",
    "to authenticated",
    "(select private.\"current_role\"()) = 'customer'",
    "customer_id = (select auth.uid())",
    "(select private.\"current_role\"()) = 'admin'",
    "private.profile_tenant_id(customer_id)",
    "(select private.current_admin_id())",
    "(select private.\"current_role\"()) = 'employee'",
    "private.employee_has_permission('view_financial_reports')",
)
for marker in required:
    assert marker in sql, f"financial-events tenant isolation missing: {marker}"

admin_clause = sql.split("(select private.\"current_role\"()) = 'admin'", 1)[1]
assert "private.profile_tenant_id(customer_id)" in admin_clause
assert "(select private.current_admin_id())" in admin_clause

employee_clause = sql.split("(select private.\"current_role\"()) = 'employee'", 1)[1]
assert "private.profile_tenant_id(customer_id)" in employee_clause
assert "(select private.current_admin_id())" in employee_clause

print("financial_events tenant isolation verified")
