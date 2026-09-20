import {
  buildContactCreate,
  buildTransactionCreate,
  parseCreatedId,
} from "./client.ts";

Deno.test("builds Daftar contact create from fixed write contract", () => {
  const request = buildContactCreate({
    userId: 28,
    name: "Test Customer",
    phone: "07500000000",
    createdAt: "2026-09-20T15:00:00.000Z",
    updatedAt: "2026-09-20T15:00:00.000Z",
  });
  if (request.path !== "contacts") throw new Error("wrong contacts path");
  if (request.method !== "POST") throw new Error("wrong contacts method");
  const body = request.body as Record<string, unknown>;
  if (body.user_id !== 28) throw new Error("wrong user id");
  if (body.name !== "Test Customer") throw new Error("wrong name");
  if (body.phone !== "07500000000") throw new Error("wrong phone");
  if (body.created_at !== "2026-09-20 18:00:00.000000") throw new Error("wrong created_at");
  if (body.updated_at !== "2026-09-20 18:00:00.000000") throw new Error("wrong updated_at");
});

Deno.test("builds Daftar LOAN transaction create", () => {
  const request = buildTransactionCreate({
    userId: 28,
    contactId: 50667,
    transactionType: "LOAN",
    amount: 6500,
    currency: "IQD",
    transactionDate: "2026-09-20T15:00:00.000Z",
    note: "test",
  });
  if (request.path !== "transactions") throw new Error("wrong transactions path");
  if (request.method !== "POST") throw new Error("wrong transactions method");
  const body = request.body as Record<string, unknown>;
  if (body.transaction_type !== "LOAN") throw new Error("wrong type");
  if (body.contact_id !== 50667) throw new Error("wrong contact");
  if (body.amount !== 6500) throw new Error("wrong amount");\n  if (body.transaction_date !== "2026-09-20 18:00:00.000000") throw new Error("wrong transaction date");
});

Deno.test("builds Daftar PAYMENT transaction create", () => {
  const request = buildTransactionCreate({
    userId: 28,
    contactId: 50667,
    transactionType: "PAYMENT",
    amount: 20000,
    currency: "IQD",
    transactionDate: "2026-09-20T15:00:00.000Z",
    note: "",
  });
  const body = request.body as Record<string, unknown>;
  if (body.transaction_type !== "PAYMENT") throw new Error("wrong type");
});

Deno.test("parses created id without accepting malformed success", () => {
  if (parseCreatedId({ success: true, data: { id: 307700 } }) !== "307700") {
    throw new Error("failed nested id");
  }
  if (parseCreatedId({ id: 307701 }) !== "307701") {
    throw new Error("failed top-level id");
  }
  let rejected = false;
  try {
    parseCreatedId({ success: true, data: {} });
  } catch (_) {
    rejected = true;
  }
  if (!rejected) throw new Error("missing id must reject");
});
\nDeno.test("formats UTC instants as Daftar Iraq wall-clock timestamps", () => {\n  const formatted = toDaftarLocalTimestamp("2026-09-20T21:02:37.066Z");\n  if (formatted !== "2026-09-21 00:02:37.066000") {\n    throw new Error("wrong Daftar timestamp: " + formatted);\n  }\n});\n