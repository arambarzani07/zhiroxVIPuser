import { assertEquals } from "jsr:@std/assert@1";
import { executeLocalRead } from "./local_read.ts";

function paymentQueryClient(rows: Array<Record<string, unknown>>) {
  const terminal = {
    order: () => terminal,
    range: async () => ({ data: rows, error: null }),
  };
  return {
    from: (table: string) => {
      assertEquals(table, "payments");
      return {
        select: () => ({
          eq: () => terminal,
        }),
      };
    },
  };
}

Deno.test("one Daftar payment can materialize as multiple ZHIROX allocations", async () => {
  const fakeClient = paymentQueryClient([
    { id: "p1", amount: 60000 },
    { id: "p2", amount: 40000 },
  ]);
  const data = await executeLocalRead(
    fakeClient,
    "debt_payments",
    { debt_id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd" },
    {
      id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      role: "admin",
      tenantId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    },
  ) as Array<{ id: string; amount: number }>;

  assertEquals(data.length, 2);
  assertEquals(data.reduce((sum, row) => sum + row.amount, 0), 100000);
});
