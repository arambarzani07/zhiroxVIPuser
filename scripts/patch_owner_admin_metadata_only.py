#!/usr/bin/env python3
from pathlib import Path

path = Path('supabase/functions/account-admin/index.ts')
text = path.read_text(encoding='utf-8')

old = '''      const adminIds = (admins ?? []).map((row: any) => row.id);
      const counts = new Map<string, { employee: number; customer: number }>();
      if (adminIds.length > 0) {
        const { data: members, error: membersError } = await admin
          .from("profiles")
          .select("admin_id,role")
          .in("admin_id", adminIds)
          .in("role", ["employee", "customer"]);
        if (membersError) return json({ error: membersError.message }, 400);
        for (const member of members ?? []) {
          const current = counts.get(member.admin_id) ?? { employee: 0, customer: 0 };
          if (member.role === "employee") current.employee += 1;
          if (member.role === "customer") current.customer += 1;
          counts.set(member.admin_id, current);
        }
      }

      const totalItems = count ?? 0;
      return json({
        admins: (admins ?? []).map((row: any) => ({
          admin: row,
          employee_count: counts.get(row.id)?.employee ?? 0,
          customer_count: counts.get(row.id)?.customer ?? 0,
        })),
        total_items: totalItems,
'''
new = '''      // System Owner admin management is platform/account metadata only.
      // Do not inspect tenant members or business content while listing markets.
      const totalItems = count ?? 0;
      return json({
        admins: (admins ?? []).map((row: any) => ({ admin: row })),
        total_items: totalItems,
'''

if old not in text:
    if 'platform/account metadata only' in text and 'employee_count' not in text and 'customer_count' not in text:
        print('Owner admin listing already privacy-safe')
    else:
        raise SystemExit('expected owner admin count block not found')
else:
    text = text.replace(old, new, 1)

path.write_text(text, encoding='utf-8')
print('Owner admin listing limited to platform/account metadata only')
