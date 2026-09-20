export type DaftarWriteRequest = {
  method: "POST";
  path: "contacts" | "transactions";
  body: Record<string, unknown>;
};

export type ContactCreateInput = {
  userId: number;
  name: string;
  phone: string;
  createdAt: string;
  updatedAt: string;
};

export type TransactionCreateInput = {
  userId: number;
  contactId: number;
  transactionType: "LOAN" | "PAYMENT";
  amount: number;
  currency: string;
  transactionDate: string;
  note: string;
};

function positiveInteger(value: number, name: string): number {
  if (!Number.isInteger(value) || value <= 0) throw new Error(`invalid_${name}`);
  return value;
}

function nonNegativeAmount(value: number): number {
  if (!Number.isFinite(value) || value < 0) throw new Error("invalid_amount");
  return Math.round(value * 100) / 100;
}

export function buildContactCreate(input: ContactCreateInput): DaftarWriteRequest {
  const createdAt = Date.parse(input.createdAt);
  const updatedAt = Date.parse(input.updatedAt);
  if (!Number.isFinite(createdAt)) throw new Error("invalid_created_at");
  if (!Number.isFinite(updatedAt)) throw new Error("invalid_updated_at");
  return {
    method: "POST",
    path: "contacts",
    body: {
      user_id: positiveInteger(input.userId, "user_id"),
      name: String(input.name ?? "").trim(),
      phone: String(input.phone ?? "").trim(),
      created_at: new Date(createdAt).toISOString(),
      updated_at: new Date(updatedAt).toISOString(),
    },
  };
}

export function buildTransactionCreate(
  input: TransactionCreateInput,
): DaftarWriteRequest {
  if (input.transactionType !== "LOAN" && input.transactionType !== "PAYMENT") {
    throw new Error("invalid_transaction_type");
  }
  const parsedDate = Date.parse(input.transactionDate);
  if (!Number.isFinite(parsedDate)) throw new Error("invalid_transaction_date");
  const currency = String(input.currency || "IQD").trim().toUpperCase();
  if (!currency) throw new Error("invalid_currency");
  return {
    method: "POST",
    path: "transactions",
    body: {
      user_id: positiveInteger(input.userId, "user_id"),
      contact_id: positiveInteger(input.contactId, "contact_id"),
      transaction_type: input.transactionType,
      amount: nonNegativeAmount(input.amount),
      currency,
      transaction_date: new Date(parsedDate).toISOString(),
      note: String(input.note ?? ""),
    },
  };
}

export function parseCreatedId(payload: unknown): string {
  const body = payload as Record<string, unknown> | null;
  const topLevel = body?.id;
  if (typeof topLevel === "number" || typeof topLevel === "string") {
    const value = String(topLevel).trim();
    if (value) return value;
  }
  const data = body?.data as Record<string, unknown> | null;
  const nested = data?.id;
  if (typeof nested === "number" || typeof nested === "string") {
    const value = String(nested).trim();
    if (value) return value;
  }
  throw new Error("daftar_write_missing_id");
}

export function fixedDaftarUrl(baseUrl: string, path: "contacts" | "transactions"): URL {
  const base = new URL(baseUrl);
  if (base.protocol !== "https:" || base.hostname !== "api-daftar-qarz.kasbkar.net") {
    throw new Error("invalid_daftar_write_host");
  }
  if (!base.pathname.startsWith("/api/v1")) {
    throw new Error("invalid_daftar_write_base");
  }
  return new URL(path, baseUrl.endsWith("/") ? baseUrl : baseUrl + "/");
}
