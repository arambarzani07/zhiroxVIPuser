export type DaftarWriteRequest = {
  method: "POST" | "PUT" | "DELETE";
  path:
    | "contacts"
    | "transactions"
    | `contacts/${number}`
    | `transactions/${number}`;
  body?: Record<string, unknown>;
  remoteId?: string;
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

export type ContactUpdateInput = ContactCreateInput & { remoteId: number };
export type TransactionUpdateInput = TransactionCreateInput & {
  remoteId: number;
};

function positiveInteger(value: number, name: string): number {
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`invalid_${name}`);
  }
  return value;
}

function nonNegativeAmount(value: number): number {
  if (!Number.isFinite(value) || value < 0) throw new Error("invalid_amount");
  return Math.round(value * 100) / 100;
}

function pad2(value: number): string {
  return String(value).padStart(2, "0");
}

function pad3(value: number): string {
  return String(value).padStart(3, "0");
}

// Daftar Qarz 0.2.7 sends local Iraq wall-clock timestamps rather than
// ISO-8601 strings with a timezone suffix. Its backend treats these values as
// Asia/Baghdad time; sending T...Z causes a server-side 5xx on writes.
export function toDaftarLocalTimestamp(value: string): string {
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) throw new Error("invalid_daftar_timestamp");
  const baghdad = new Date(parsed + 3 * 60 * 60 * 1000);
  return [
    baghdad.getUTCFullYear(),
    "-",
    pad2(baghdad.getUTCMonth() + 1),
    "-",
    pad2(baghdad.getUTCDate()),
    " ",
    pad2(baghdad.getUTCHours()),
    ":",
    pad2(baghdad.getUTCMinutes()),
    ":",
    pad2(baghdad.getUTCSeconds()),
    ".",
    pad3(baghdad.getUTCMilliseconds()),
    "000",
  ].join("");
}

export function buildContactCreate(
  input: ContactCreateInput,
): DaftarWriteRequest {
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
      created_at: toDaftarLocalTimestamp(new Date(createdAt).toISOString()),
      updated_at: toDaftarLocalTimestamp(new Date(updatedAt).toISOString()),
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
      transaction_date: toDaftarLocalTimestamp(
        new Date(parsedDate).toISOString(),
      ),
      note: String(input.note ?? ""),
    },
  };
}

export function buildContactUpdate(
  input: ContactUpdateInput,
): DaftarWriteRequest {
  const createdAt = Date.parse(input.createdAt);
  const updatedAt = Date.parse(input.updatedAt);
  if (!Number.isFinite(createdAt)) throw new Error("invalid_created_at");
  if (!Number.isFinite(updatedAt)) throw new Error("invalid_updated_at");
  const remoteId = positiveInteger(input.remoteId, "remote_id");
  return {
    method: "PUT",
    path: `contacts/${remoteId}`,
    remoteId: String(remoteId),
    body: {
      user_id: positiveInteger(input.userId, "user_id"),
      name: String(input.name ?? "").trim(),
      phone: String(input.phone ?? "").trim(),
      created_at: toDaftarLocalTimestamp(new Date(createdAt).toISOString()),
      updated_at: toDaftarLocalTimestamp(new Date(updatedAt).toISOString()),
    },
  };
}

export function buildTransactionUpdate(
  input: TransactionUpdateInput,
): DaftarWriteRequest {
  const create = buildTransactionCreate(input);
  const remoteId = positiveInteger(input.remoteId, "remote_id");
  return {
    method: "PUT",
    path: `transactions/${remoteId}`,
    remoteId: String(remoteId),
    body: create.body,
  };
}

export function buildDaftarDelete(
  kind: "customer" | "debt" | "payment",
  remoteIdValue: number,
): DaftarWriteRequest {
  const remoteId = positiveInteger(remoteIdValue, "remote_id");
  return {
    method: "DELETE",
    path: kind === "customer"
      ? `contacts/${remoteId}`
      : `transactions/${remoteId}`,
    remoteId: String(remoteId),
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

export function fixedDaftarUrl(
  baseUrl: string,
  path: DaftarWriteRequest["path"],
): URL {
  const base = new URL(baseUrl);
  if (
    base.protocol !== "https:" ||
    base.hostname !== "api-daftar-qarz.kasbkar.net"
  ) {
    throw new Error("invalid_daftar_write_host");
  }
  if (!base.pathname.startsWith("/api/v1")) {
    throw new Error("invalid_daftar_write_base");
  }
  if (!/^(contacts|transactions)(\/\d+)?$/.test(path)) {
    throw new Error("invalid_daftar_write_path");
  }
  return new URL(path, baseUrl.endsWith("/") ? baseUrl : baseUrl + "/");
}
