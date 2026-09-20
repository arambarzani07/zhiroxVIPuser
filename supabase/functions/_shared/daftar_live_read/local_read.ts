import type { DaftarLiveReadOperation } from "./types.ts";
import { LiveReadError } from "./policy.ts";

const DEBT_SELECT = `
  *,
  customer_expand:profiles!debts_customer_id_fkey(*),
  debt_creator_expand:profiles!debts_created_by_fkey(*)
`;

const PAYMENT_SELECT = `
  *,
  debt_expand:debts!payments_debt_id_fkey(
    *,
    customer_expand:profiles!debts_customer_id_fkey(*),
    debt_creator_expand:profiles!debts_created_by_fkey(*)
  ),
  creator_expand:profiles!payments_created_by_fkey(*)
`;

function uuidParam(params: Record<string, unknown>, key: string): string {
  const value = String(params[key] ?? "").trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new LiveReadError({ kind: "unsupported" }, `invalid_${key}`);
  }
  return value;
}

function stringParam(params: Record<string, unknown>, key: string, fallback = ""): string {
  return params[key] == null ? fallback : String(params[key]).trim();
}

function nullableStringParam(params: Record<string, unknown>, key: string): string | null {
  const value = stringParam(params, key, "");
  return value.length === 0 ? null : value;
}

function intParam(params: Record<string, unknown>, key: string, fallback: number, min: number, max: number): number {
  const parsed = Number.parseInt(String(params[key] ?? fallback), 10);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
    throw new LiveReadError({ kind: "unsupported" }, `invalid_${key}`);
  }
  return parsed;
}

function nullableIsoParam(params: Record<string, unknown>, key: string): string | null {
  const value = nullableStringParam(params, key);
  if (value == null) return null;
  if (!Number.isFinite(Date.parse(value))) {
    throw new LiveReadError({ kind: "unsupported" }, `invalid_${key}`);
  }
  return new Date(value).toISOString();
}

function directoryCursorParams(raw: unknown): Record<string, unknown> {
  if (raw == null) return {};
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new LiveReadError({ kind: "unsupported" }, "invalid_cursor");
  }
  const cursor = raw as Record<string, unknown>;
  return {
    p_cursor_created_at: nullableIsoParam(cursor, "created_at"),
    p_cursor_id: uuidParam(cursor, "id"),
  };
}

function timelineCursorParams(raw: unknown): Record<string, unknown> {
  if (raw == null) return {};
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new LiveReadError({ kind: "unsupported" }, "invalid_cursor");
  }
  const cursor = raw as Record<string, unknown>;
  return {
    p_cursor_at: nullableIsoParam(cursor, "at"),
    p_cursor_kind: intParam(cursor, "kind_rank", 0, 1, 4),
    p_cursor_id: uuidParam(cursor, "id"),
  };
}

function unwrap<T>(result: { data: T | null; error: { message?: string } | null }): T {
  if (result.error) throw new Error(result.error.message ?? "local_read_failed");
  if (result.data == null) throw new Error("local_read_empty");
  return result.data;
}

function unwrapOne<T>(result: { data: T | null; error: { message?: string } | null }): T {
  return unwrap(result);
}

async function readAllPages(page: (from: number, to: number) => Promise<unknown[]>): Promise<unknown[]> {
  const all: unknown[] = [];
  const size = 500;
  for (let offset = 0;; offset += size) {
    const rows = await page(offset, offset + size - 1);
    all.push(...rows);
    if (rows.length < size) return all;
  }
}

async function assertEmployeeVisibleToViewer(
  userClient: any,
  viewer: { id: string; role: string; tenantId: string },
  employeeId: string,
): Promise<void> {
  if (viewer.role === "customer" || (viewer.role === "employee" && viewer.id !== employeeId)) {
    throw new LiveReadError({ kind: "authorization" }, "employee_stats_forbidden");
  }
  const employee = unwrapOne(await userClient.from("profiles")
    .select("id, admin_id, role").eq("id", employeeId).single());
  if (String((employee as any).role) !== "employee" || String((employee as any).admin_id) !== viewer.tenantId) {
    throw new LiveReadError({ kind: "authorization" }, "employee_stats_forbidden");
  }
}

async function readEmployeeStats(userClient: any, employeeId: string) {
  const [debts, payments] = await Promise.all([
    readAllPages(async (from, to) =>
      unwrap(await userClient.from("debts").select("amount").eq("created_by", employeeId)
        .is("deleted_at", null).range(from, to))),
    readAllPages(async (from, to) =>
      unwrap(await userClient.from("payments").select("amount").eq("created_by", employeeId)
        .range(from, to))),
  ]);
  return {
    total_debts_created: debts.reduce<number>(
      (sum, row: any) => sum + Number(row.amount ?? 0),
      0,
    ),
    total_payments_collected: payments.reduce<number>(
      (sum, row: any) => sum + Number(row.amount ?? 0),
      0,
    ),
  };
}

async function readAdminDebts(
  userClient: any,
  adminId: string,
  range: { from: string | null; to: string | null },
): Promise<unknown[]> {
  const customerIds: string[] = [];
  for (let offset = 0;; offset += 500) {
    const rows = unwrap(await userClient.from("profiles").select("id")
      .eq("admin_id", adminId).eq("role", "customer").order("id", { ascending: true })
      .range(offset, offset + 499)) as any[];
    for (const row of rows) customerIds.push(String(row.id));
    if (rows.length < 500) break;
  }
  const all: any[] = [];
  for (let start = 0; start < customerIds.length; start += 50) {
    const ids = customerIds.slice(start, start + 50);
    for (let offset = 0;; offset += 500) {
      let query = userClient.from("debts").select(DEBT_SELECT).in("customer_id", ids).is("deleted_at", null);
      if (range.from) query = query.gte("created_at", range.from);
      if (range.to) query = query.lt("created_at", range.to);
      const rows = unwrap(await query.order("created_at", { ascending: false })
        .order("id", { ascending: false }).range(offset, offset + 499)) as any[];
      all.push(...rows);
      if (rows.length < 500) break;
    }
  }
  all.sort((left, right) => {
    const byTime = String(right.created_at).localeCompare(String(left.created_at));
    return byTime !== 0 ? byTime : String(right.id).localeCompare(String(left.id));
  });
  return all;
}

export async function executeLocalRead(
  userClient: any,
  operation: DaftarLiveReadOperation,
  params: Record<string, unknown>,
  viewer: { id: string; role: string; tenantId: string },
): Promise<unknown> {
  switch (operation) {
    case "customer_directory":
      return unwrap(await userClient.rpc("get_customer_directory_page", {
        p_search: stringParam(params, "search", ""),
        p_limit: intParam(params, "limit", 60, 1, 100),
        ...directoryCursorParams(params.cursor),
      }));
    case "customer_finance_snapshot":
      return unwrap(await userClient.rpc("get_customer_finance_snapshot", {
        p_customer_id: uuidParam(params, "customer_id"),
      }));
    case "customer_timeline":
      return unwrap(await userClient.rpc("get_customer_financial_timeline_page", {
        p_customer_id: uuidParam(params, "customer_id"),
        p_limit: intParam(params, "limit", 50, 1, 100),
        ...timelineCursorParams(params.cursor),
      }));
    case "customer_debts_page":
      return unwrap(await userClient.rpc("get_customer_debts_page", {
        p_customer_id: uuidParam(params, "customer_id"),
        p_status: nullableStringParam(params, "status"),
        p_page: intParam(params, "page", 1, 1, 1000000),
        p_limit: intParam(params, "limit", 20, 1, 100),
      }));
    case "debt_detail":
      return unwrapOne(await userClient.from("debts").select(DEBT_SELECT)
        .eq("id", uuidParam(params, "debt_id")).single());
    case "debt_payments":
      return unwrap(await userClient.from("payments").select(PAYMENT_SELECT)
        .eq("debt_id", uuidParam(params, "debt_id"))
        .order("created_at", { ascending: false }).order("id", { ascending: false }).range(0, 499));
    case "customer_all_debts":
      return readAllPages(async (from, to) =>
        unwrap(await userClient.from("debts").select(DEBT_SELECT)
          .eq("customer_id", uuidParam(params, "customer_id")).is("deleted_at", null)
          .order("created_at", { ascending: false }).order("id", { ascending: false }).range(from, to)));
    case "admin_dashboard":
      return unwrap(await userClient.rpc("get_admin_dashboard_snapshot"));
    case "admin_all_debts": {
      const requestedAdmin = uuidParam(params, "admin_id");
      if (requestedAdmin !== viewer.tenantId) {
        throw new LiveReadError({ kind: "authorization" }, "wrong_tenant");
      }
      return readAdminDebts(userClient, requestedAdmin, {
        from: nullableIsoParam(params, "from"),
        to: nullableIsoParam(params, "to"),
      });
    }
    case "employee_stats": {
      const employeeId = uuidParam(params, "employee_id");
      await assertEmployeeVisibleToViewer(userClient, viewer, employeeId);
      return readEmployeeStats(userClient, employeeId);
    }
  }
}
