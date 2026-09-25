import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { authorizeDaftarSyncRequest } from "../_shared/daftar_sync_auth.ts";
import {
  buildContactCreate,
  buildContactUpdate,
  buildDaftarDelete,
  buildTransactionCreate,
  buildTransactionUpdate,
  type DaftarWriteRequest,
  fixedDaftarUrl,
  parseCreatedId,
} from "../_shared/daftar_outbound/client.ts";

const daftarCompatibilityUserAgent = "Dart/3.9 (dart:io)";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type, x-daftar-sync-secret",
};

type Source = {
  id: string;
  admin_id: string;
  legacy_user_id: number;
  source_fingerprint: string;
  api_base_url: string;
  trigger_secret_hash: string;
  enabled: boolean;
  sync_mode: string;
  outbound_sync_enabled: boolean;
  outbound_write_contract_status: string;
};

type OutboxEvent = {
  id: string;
  entity_kind: "customer" | "debt" | "payment";
  entity_id: string;
  operation: "create" | "update" | "delete";
  status: "pending" | "failed" | "blocked";
  attempts: number;
  payload_snapshot?: Record<string, unknown> | null;
  remote_id_snapshot?: string | null;
  created_at?: string;
  last_error?: string | null;
};

function isGeneralPaymentSnapshot(
  snapshot: Record<string, unknown>,
): boolean {
  return String(snapshot.payment_scope ?? "").trim().toLowerCase() === "general" ||
    String(snapshot.source_table ?? "").trim() === "customer_general_payments";
}

function isCreditLimitRollback(event: OutboxEvent): boolean {
  const snapshot = event.payload_snapshot ?? {};
  return event.entity_kind === "debt" &&
    (event.operation === "delete" || event.operation === "update") &&
    snapshot.source === "daftar_official_app_inbound_guard" &&
    snapshot.rejection_reason === "credit_limit_exceeded";
}

function isOfficialDaftarSource(source: Source): boolean {
  if (!source.enabled) return false;
  if (!Number.isInteger(Number(source.legacy_user_id)) ||
      Number(source.legacy_user_id) <= 0) {
    return false;
  }
  if (!String(source.source_fingerprint ?? "").trim()) return false;

  try {
    const url = new URL(String(source.api_base_url));
    const normalizedPath = url.pathname.replace(/\/+$/, "");
    return url.protocol === "https:" &&
      url.hostname === "api-daftar-qarz.kasbkar.net" &&
      normalizedPath === "/api/v1";
  } catch (_) {
    return false;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    const value = parsed.default ?? Object.values(parsed)[0];
    return typeof value === "string" ? value : null;
  } catch (_) {
    return raw;
  }
}

function normalizeContactName(value: unknown): string {
  return String(value ?? "").trim().replace(/\s+/g, " ").toLowerCase();
}

function normalizeContactPhone(value: unknown): string {
  return String(value ?? "").replace(/\D/g, "");
}

function datesAreClose(
  left: unknown,
  right: unknown,
  toleranceMs: number,
): boolean {
  const a = Date.parse(String(left ?? ""));
  const b = Date.parse(String(right ?? ""));
  return Number.isFinite(a) && Number.isFinite(b) &&
    Math.abs(a - b) <= toleranceMs;
}

async function probeEndpoint(
  url: URL,
  method: "OPTIONS" | "POST" | "PUT" | "PATCH" | "DELETE" = "OPTIONS",
  probeBody?: Record<string, unknown>,
) {
  try {
    const response = await fetch(url, {
      method,
      redirect: "manual",
      signal: AbortSignal.timeout(8_000),
      headers: {
        accept: "application/json",
        ...((method === "PATCH" || method === "PUT" || method === "POST")
          ? { "content-type": "application/json" }
          : {}),
      },
      ...((method === "PATCH" || method === "PUT" || method === "POST")
        ? { body: JSON.stringify(probeBody ?? {}) }
        : {}),
    });
    const responseText = method === "OPTIONS"
      ? ""
      : (await response.text()).slice(0, 2000);
    return {
      url: url.toString(),
      method,
      status: response.status,
      allow: response.headers.get("allow"),
      cors_allow_methods: response.headers.get("access-control-allow-methods"),
      www_authenticate: response.headers.get("www-authenticate"),
      location: response.headers.get("location"),
      body: responseText,
    };
  } catch (error) {
    return {
      url: url.toString(),
      method,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

type RemoteContactRow = {
  id: number | string;
  user_id?: number | string;
  name?: string | null;
  phone?: string | null;
  contact_name?: string | null;
  contact_phone?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

function remoteContactName(row: RemoteContactRow): string {
  return normalizeContactName(row.name ?? row.contact_name);
}

function remoteContactPhone(row: RemoteContactRow): string {
  return normalizeContactPhone(row.phone ?? row.contact_phone);
}

async function fetchRemoteContactsLive(
  source: Source,
): Promise<RemoteContactRow[]> {
  const endpoint = fixedDaftarUrl(source.api_base_url, "contacts");
  endpoint.searchParams.set("user_id", String(source.legacy_user_id));
  const response = await fetch(endpoint, {
    method: "GET",
    redirect: "manual",
    signal: AbortSignal.timeout(15_000),
    headers: {
      accept: "application/json",
      "user-agent": daftarCompatibilityUserAgent,
    },
  });
  if (!response.ok) {
    throw new Error(`remote_contact_lookup_http_${response.status}`);
  }
  const payload = await response.json();
  if (payload?.success !== true || !Array.isArray(payload?.data)) {
    throw new Error("remote_contact_lookup_invalid_response");
  }
  return (payload.data as RemoteContactRow[]).filter((row) =>
    Number(row.user_id) === Number(source.legacy_user_id)
  );
}

type RemoteTransactionRow = {
  id: number | string;
  user_id?: number | string;
};

async function fetchRemoteTransactionsLive(
  source: Source,
): Promise<RemoteTransactionRow[]> {
  const endpoint = fixedDaftarUrl(source.api_base_url, "transactions");
  endpoint.searchParams.set("user_id", String(source.legacy_user_id));
  const response = await fetch(endpoint, {
    method: "GET",
    redirect: "manual",
    signal: AbortSignal.timeout(20_000),
    headers: {
      accept: "application/json",
      "user-agent": daftarCompatibilityUserAgent,
    },
  });
  if (!response.ok) {
    throw new Error(`remote_transaction_lookup_http_${response.status}`);
  }
  const payload = await response.json();
  if (payload?.success !== true || !Array.isArray(payload?.data)) {
    throw new Error("remote_transaction_lookup_invalid_response");
  }
  return (payload.data as RemoteTransactionRow[]).filter((row) =>
    Number(row.user_id) === Number(source.legacy_user_id)
  );
}

async function finalizeRemoteTransactionDelete(
  admin: any,
  source: Source,
  event: OutboxEvent,
  remoteId: string,
) {
  const { data: existingSeen, error: seenReadError } = await admin
    .from("daftar_sync_seen")
    .select("target_id")
    .eq("sync_source_id", source.id)
    .eq("entity_kind", event.entity_kind)
    .eq("source_id", remoteId)
    .maybeSingle();
  if (seenReadError) throw seenReadError;

  const tombstoneHash =
    event.payload_snapshot?.rejection_reason === "credit_limit_exceeded"
      ? "__credit_limit_rejected__"
      : "__deleted__";

  const { error: tombstoneError } = await admin.from("daftar_sync_seen").upsert({
    sync_source_id: source.id,
    entity_kind: event.entity_kind,
    source_id: remoteId,
    target_id: existingSeen?.target_id ?? null,
    payload_hash: tombstoneHash,
  }, {
    onConflict: "sync_source_id,entity_kind,source_id",
  });
  if (tombstoneError) throw tombstoneError;

  // Mirror tables are cache/read-model state, not the financial ledger.
  // Once live Daftar absence is confirmed, remove the stale cached row
  // immediately instead of waiting for the next full inbound snapshot.
  const { error: mirrorDeleteError } = await admin
    .from("daftar_mirror_transactions")
    .delete()
    .eq("sync_source_id", source.id)
    .eq("source_id", remoteId);
  if (mirrorDeleteError) throw mirrorDeleteError;
}

async function reconcileAmbiguousTransactionDelete(
  admin: any,
  source: Source,
  event: OutboxEvent,
  request: DaftarWriteRequest,
): Promise<Record<string, unknown> | null> {
  if (
    request.method !== "DELETE" ||
    (event.entity_kind !== "debt" && event.entity_kind !== "payment")
  ) {
    return null;
  }

  const remoteId = String(request.remoteId ?? "").trim();
  if (!/^\d+$/.test(remoteId)) return null;

  const rows = await fetchRemoteTransactionsLive(source);
  const stillExists = rows.some((row) => String(row.id) === remoteId);
  if (stillExists) return null;

  await finalizeRemoteTransactionDelete(admin, source, event, remoteId);

  await markEvent(admin, event.id, {
    status: "sent",
    remote_id: remoteId,
    last_error: "reconciled_after_ambiguous_delete:live_absence",
    sent_at: new Date().toISOString(),
  });

  return {
    id: event.id,
    status: "sent",
    remote_id: remoteId,
    reconciliation: "live_absence",
  };
}

async function findRemoteCustomerLive(
  source: Source,
  profile: { name?: unknown; phone?: unknown; created_at?: unknown },
): Promise<string | null> {
  const rows = await fetchRemoteContactsLive(source);
  const phone = normalizeContactPhone(profile.phone);
  const name = normalizeContactName(profile.name);

  let matches = phone
    ? rows.filter((row) => remoteContactPhone(row) === phone)
    : [];

  if (matches.length === 0 && name) {
    const named = rows.filter((row) => remoteContactName(row) === name);
    const recentNamed = named.filter((row) =>
      datesAreClose(row.created_at, profile.created_at, 30 * 60_000)
    );
    matches = recentNamed.length > 0 ? recentNamed : named;
  }

  if (matches.length > 1) {
    throw new Error("ambiguous_remote_multiple_live_customer_matches");
  }
  if (matches.length === 0) return null;

  const id = String(matches[0].id ?? "").trim();
  if (!/^\d+$/.test(id)) throw new Error("invalid_remote_customer_id");
  return id;
}

async function loadCustomerForOutbound(
  admin: any,
  source: Source,
  customerId: string,
) {
  const { data, error } = await admin.from("profiles")
    .select("id, name, phone, role, admin_id, created_at, updated_at")
    .eq("id", customerId)
    .maybeSingle();
  if (error) throw error;
  if (!data || data.role !== "customer" || data.admin_id !== source.admin_id) {
    return null;
  }
  return data;
}

async function recoverAmbiguousCustomerCreate(
  admin: any,
  source: Source,
  event: OutboxEvent,
  _request: DaftarWriteRequest,
): Promise<Record<string, unknown> | null> {
  if (event.entity_kind !== "customer") return null;
  const profile = await loadCustomerForOutbound(admin, source, event.entity_id);
  if (!profile) return null;

  // Daftar can commit a contact insert and still return HTTP 500. A second
  // POST is therefore unsafe because it can create a duplicate customer.
  // Re-read the live source a few times, then leave the event blocked for the
  // inbound mirror/reconciliation path to resolve without another write.
  const delaysMs = [0, 1500, 3000, 5000];
  for (const delayMs of delaysMs) {
    if (delayMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
    const existing = await findRemoteCustomerLive(source, profile);
    if (!existing) continue;

    await recordMapping(admin, source, event, existing);
    await markEvent(admin, event.id, {
      status: "sent",
      remote_id: existing,
      last_error: "reconciled_after_ambiguous_write:live_lookup",
      sent_at: new Date().toISOString(),
    });
    return {
      id: event.id,
      status: "sent",
      remote_id: existing,
      reconciliation: "live_lookup",
    };
  }

  await markEvent(admin, event.id, {
    status: "blocked",
    last_error: "ambiguous_remote_write_waiting_for_inbound_reconciliation",
    next_attempt_at: new Date(Date.now() + 10 * 60_000).toISOString(),
  });
  return {
    id: event.id,
    status: "blocked",
    error: "ambiguous_remote_write_waiting_for_inbound_reconciliation",
  };
}

async function remoteLink(
  admin: any,
  source: Source,
  entityKind: string,
  targetId: string,
): Promise<string | null> {
  const { data, error } = await admin.from("legacy_import_links")
    .select("source_id")
    .eq("admin_id", source.admin_id)
    .eq("source_fingerprint", source.source_fingerprint)
    .eq("entity_kind", entityKind)
    .eq("target_id", targetId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  const value = data?.source_id == null ? "" : String(data.source_id);
  return value ? value.split(":")[0] : null;
}

async function ensureCustomerOutbox(
  admin: any,
  source: Source,
  customerId: string,
) {
  const { error } = await admin.from("daftar_outbound_events").upsert({
    sync_source_id: source.id,
    entity_kind: "customer",
    entity_id: customerId,
    operation: "create",
    idempotency_key: `zhirox:customer:${customerId}:create`,
    status: "pending",
    next_attempt_at: new Date(Date.now() + 10_000).toISOString(),
    updated_at: new Date().toISOString(),
  }, { onConflict: "idempotency_key", ignoreDuplicates: true });
  if (error) throw error;
}

async function deferEvent(admin: any, event: OutboxEvent, reason: string) {
  const { error } = await admin.from("daftar_outbound_events").update({
    status: "pending",
    next_attempt_at: new Date(Date.now() + 60_000).toISOString(),
    last_error: reason,
    updated_at: new Date().toISOString(),
  }).eq("id", event.id);
  if (error) throw error;
}

async function markEvent(
  admin: any,
  eventId: string,
  values: Record<string, unknown>,
) {
  const { error } = await admin.from("daftar_outbound_events").update({
    ...values,
    updated_at: new Date().toISOString(),
  }).eq("id", eventId);
  if (error) throw error;
}

async function claimEvent(admin: any, event: OutboxEvent): Promise<boolean> {
  const { data, error } = await admin.from("daftar_outbound_events").update({
    status: "processing",
    attempts: Number(event.attempts ?? 0) + 1,
    updated_at: new Date().toISOString(),
  })
    .eq("id", event.id)
    .in("status", ["pending", "failed"])
    .select("id")
    .maybeSingle();
  if (error) throw error;
  return Boolean(data?.id);
}

async function sendWrite(
  source: Source,
  request: DaftarWriteRequest,
): Promise<{ remoteId: string; status: number }> {
  const endpoint = fixedDaftarUrl(source.api_base_url, request.path);
  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: request.method,
      redirect: "manual",
      signal: AbortSignal.timeout(15_000),
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        "user-agent": daftarCompatibilityUserAgent,
      },
      ...(request.body ? { body: JSON.stringify(request.body) } : {}),
    });
  } catch (error) {
    throw new Error(
      `ambiguous_remote_write:${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  const text = await response.text();
  let payload: unknown = null;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch (_) {
    payload = null;
  }

  if (!response.ok) {
    // DELETE is idempotent. A missing row already represents the requested
    // final state and must not poison the queue forever.
    if (request.method === "DELETE" && response.status === 404) {
      return {
        remoteId: String(request.remoteId ?? ""),
        status: response.status,
      };
    }
    if (response.status === 429) throw new Error("remote_rate_limited");
    if (response.status >= 500) {
      throw new Error(`ambiguous_remote_http_${response.status}`);
    }
    throw new Error(
      `remote_rejected_${response.status}:${text.slice(0, 500)}`,
    );
  }

  let remoteId = String(request.remoteId ?? "");
  if (request.method === "POST") {
    try {
      remoteId = parseCreatedId(payload);
    } catch (error) {
      throw new Error(
        `ambiguous_remote_missing_id:${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
  if (!/^\d+$/.test(remoteId)) throw new Error("invalid_remote_id");
  return { remoteId, status: response.status };
}

async function assertRemoteIdAvailable(
  admin: any,
  source: Source,
  entityKind: string,
  sourceId: string,
  targetId: string | null,
) {
  const { data, error } = await admin.from("legacy_import_links")
    .select("target_id")
    .eq("admin_id", source.admin_id)
    .eq("source_fingerprint", source.source_fingerprint)
    .eq("entity_kind", entityKind)
    .eq("source_id", sourceId)
    .maybeSingle();
  if (error) throw error;
  if (data && targetId && String(data.target_id) !== targetId) {
    throw new Error("ambiguous_remote_id_collision");
  }
}

async function recordMapping(
  admin: any,
  source: Source,
  event: OutboxEvent,
  remoteId: string,
) {
  if (!/^\d+$/.test(remoteId)) throw new Error("invalid_remote_id");

  if (event.entity_kind === "payment") {
    const allocationSourceId = `${remoteId}:1`;
    await assertRemoteIdAvailable(
      admin,
      source,
      "payment",
      allocationSourceId,
      event.entity_id,
    );

    const { error: linkError } = await admin.from("legacy_import_links").upsert(
      {
        admin_id: source.admin_id,
        source_fingerprint: source.source_fingerprint,
        entity_kind: "payment",
        source_id: allocationSourceId,
        target_id: event.entity_id,
      },
      {
        onConflict: "admin_id,source_fingerprint,entity_kind,source_id",
        ignoreDuplicates: true,
      },
    );
    if (linkError) throw linkError;

    const { error: seenPaymentError } = await admin.from("daftar_sync_seen")
      .upsert({
        sync_source_id: source.id,
        entity_kind: "payment",
        source_id: remoteId,
        target_id: null,
        payload_hash: null,
      }, {
        onConflict: "sync_source_id,entity_kind,source_id",
        ignoreDuplicates: true,
      });
    if (seenPaymentError) throw seenPaymentError;

    const { error: seenAllocationError } = await admin.from("daftar_sync_seen")
      .upsert({
        sync_source_id: source.id,
        entity_kind: "payment_allocation",
        source_id: allocationSourceId,
        target_id: event.entity_id,
        payload_hash: null,
      }, {
        onConflict: "sync_source_id,entity_kind,source_id",
        ignoreDuplicates: true,
      });
    if (seenAllocationError) throw seenAllocationError;
    return;
  }

  await assertRemoteIdAvailable(
    admin,
    source,
    event.entity_kind,
    remoteId,
    event.entity_id,
  );

  const { error: linkError } = await admin.from("legacy_import_links").upsert({
    admin_id: source.admin_id,
    source_fingerprint: source.source_fingerprint,
    entity_kind: event.entity_kind,
    source_id: remoteId,
    target_id: event.entity_id,
  }, {
    onConflict: "admin_id,source_fingerprint,entity_kind,source_id",
    ignoreDuplicates: true,
  });
  if (linkError) throw linkError;

  const { error: seenError } = await admin.from("daftar_sync_seen").upsert({
    sync_source_id: source.id,
    entity_kind: event.entity_kind,
    source_id: remoteId,
    target_id: event.entity_id,
    payload_hash: null,
  }, {
    onConflict: "sync_source_id,entity_kind,source_id",
    ignoreDuplicates: true,
  });
  if (seenError) throw seenError;
}

async function reconcileBlockedCustomerEvents(
  admin: any,
  source: Source,
): Promise<Record<string, unknown>[]> {
  const { data: blockedRows, error: blockedError } = await admin
    .from("daftar_outbound_events")
    .select(
      "id, entity_kind, entity_id, operation, status, attempts, created_at, last_error",
    )
    .eq("sync_source_id", source.id)
    .eq("entity_kind", "customer")
    .eq("status", "blocked")
    .like("last_error", "ambiguous_remote_%")
    .order("created_at", { ascending: true })
    .limit(10);
  if (blockedError) throw blockedError;
  if (!blockedRows?.length) return [];

  const { data: mirrorRows, error: mirrorError } = await admin
    .from("daftar_mirror_contacts")
    .select("source_id, payload")
    .eq("sync_source_id", source.id);
  if (mirrorError) throw mirrorError;

  const mirror = (mirrorRows ?? []) as Array<{
    source_id: string;
    payload: Record<string, unknown> | null;
  }>;
  const results: Record<string, unknown>[] = [];

  for (const raw of blockedRows) {
    const event = raw as unknown as OutboxEvent;
    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("id, name, phone, role, admin_id, created_at")
      .eq("id", event.entity_id)
      .maybeSingle();
    if (profileError) throw profileError;
    if (
      !profile || profile.role !== "customer" ||
      profile.admin_id !== source.admin_id
    ) {
      continue;
    }

    const phone = normalizeContactPhone(profile.phone);
    const name = normalizeContactName(profile.name);

    let strategy = "phone";
    let candidates = phone
      ? mirror.filter((row) =>
        normalizeContactPhone(row.payload?.phone) === phone
      )
      : [];

    if (candidates.length === 0 && name) {
      strategy = "name_recent";
      candidates = mirror.filter((row) =>
        normalizeContactName(row.payload?.name) === name &&
        datesAreClose(row.payload?.created_at, profile.created_at, 15 * 60_000)
      );
    }

    if (candidates.length !== 1) {
      if (candidates.length > 1) {
        await markEvent(admin, event.id, {
          last_error: "ambiguous_remote_multiple_mirror_matches",
        });
      }
      results.push({
        id: event.id,
        status: "blocked",
        reconciliation: candidates.length === 0
          ? "no_match"
          : "multiple_matches",
      });
      continue;
    }

    const remoteId = String(candidates[0].source_id ?? "").trim();
    if (!/^\d+$/.test(remoteId)) {
      results.push({
        id: event.id,
        status: "blocked",
        reconciliation: "invalid_remote_id",
      });
      continue;
    }

    try {
      await recordMapping(admin, source, event, remoteId);
      await markEvent(admin, event.id, {
        status: "sent",
        remote_id: remoteId,
        last_error: `reconciled_after_ambiguous_write:${strategy}`,
        sent_at: new Date().toISOString(),
      });
      results.push({
        id: event.id,
        status: "sent",
        reconciliation: strategy,
        remote_id: remoteId,
      });
    } catch (error) {
      await markEvent(admin, event.id, {
        last_error: `ambiguous_reconciliation_failed:${
          error instanceof Error ? error.message : String(error)
        }`.slice(0, 1000),
      });
      results.push({
        id: event.id,
        status: "blocked",
        reconciliation: "mapping_failed",
      });
    }
  }

  return results;
}

async function buildEventWrite(
  admin: any,
  source: Source,
  event: OutboxEvent,
): Promise<
  { request: DaftarWriteRequest } | { skip: string } | { defer: string }
> {
  const existingRemoteId = event.remote_id_snapshot ?? await remoteLink(
    admin,
    source,
    event.entity_kind,
    event.entity_id,
  );
  if (event.operation === "delete") {
    if (!existingRemoteId) return { skip: "remote_mapping_missing" };
    return {
      request: buildDaftarDelete(event.entity_kind, Number(existingRemoteId)),
    };
  }

  if (event.operation === "update" && !existingRemoteId) {
    return { defer: "remote_mapping_pending" };
  }

  if (event.operation === "create" && existingRemoteId) {
    return { skip: existingRemoteId };
  }

  const snapshot = event.payload_snapshot ?? {};

  if (event.entity_kind === "customer") {
    const { data, error } = await admin.from("profiles")
      .select("id, name, phone, role, admin_id, created_at, updated_at")
      .eq("id", event.entity_id)
      .maybeSingle();
    if (error) throw error;
    if (
      !data || data.role !== "customer" || data.admin_id !== source.admin_id
    ) {
      return { skip: "entity_missing" };
    }
    const effective = Object.keys(snapshot).length > 0 ? snapshot : data;
    const createdAt = String(
      effective.created_at ?? data.created_at ?? new Date().toISOString(),
    );
    const updatedAt = String(data.updated_at ?? data.created_at ?? createdAt);
    return {
      request: event.operation === "update"
        ? buildContactUpdate({
          remoteId: Number(existingRemoteId),
          userId: Number(source.legacy_user_id),
          name: String(effective.name ?? data.name ?? "").trim(),
          phone: String(effective.phone ?? data.phone ?? "").trim(),
          createdAt,
          updatedAt: String(effective.updated_at ?? updatedAt),
        })
        : buildContactCreate({
          userId: Number(source.legacy_user_id),
          name: String(effective.name ?? data.name ?? "").trim(),
          phone: String(effective.phone ?? data.phone ?? "").trim(),
          createdAt,
          updatedAt: String(effective.updated_at ?? updatedAt),
        }),
    };
  }

  if (event.entity_kind === "debt") {
    const { data, error } = await admin.from("debts")
      .select(
        "id, customer_id, amount, currency, description, custom_date, created_at, is_deleted",
      )
      .eq("id", event.entity_id)
      .maybeSingle();
    if (error) throw error;
    if (!data || data.is_deleted === true) return { skip: "entity_missing" };
    const effective = Object.keys(snapshot).length > 0 ? snapshot : data;

    const contactId = await remoteLink(
      admin,
      source,
      "customer",
      String(effective.customer_id ?? data.customer_id),
    );
    if (!contactId) {
      await ensureCustomerOutbox(
        admin,
        source,
        String(effective.customer_id ?? data.customer_id),
      );
      return { defer: "customer_mapping_pending" };
    }

    return {
      request: event.operation === "update"
        ? buildTransactionUpdate({
          remoteId: Number(existingRemoteId),
          userId: Number(source.legacy_user_id),
          contactId: Number(contactId),
          transactionType: "LOAN",
          amount: Number(effective.amount ?? data.amount ?? 0),
          currency: String(effective.currency ?? data.currency ?? "IQD"),
          transactionDate: String(
            effective.transaction_date ?? data.custom_date ?? data.created_at ??
              new Date().toISOString(),
          ),
          note: String(effective.description ?? data.description ?? ""),
        })
        : buildTransactionCreate({
          userId: Number(source.legacy_user_id),
          contactId: Number(contactId),
          transactionType: "LOAN",
          amount: Number(effective.amount ?? data.amount ?? 0),
          currency: String(effective.currency ?? data.currency ?? "IQD"),
          transactionDate: String(
            effective.transaction_date ?? data.custom_date ?? data.created_at ??
              new Date().toISOString(),
          ),
          note: String(effective.description ?? data.description ?? ""),
        }),
    };
  }

  if (event.entity_kind === "payment" && isGeneralPaymentSnapshot(snapshot)) {
    const { data: generalPayment, error: generalPaymentError } = await admin
      .from("customer_general_payments")
      .select("id, admin_id, customer_id, amount, note, created_at")
      .eq("id", event.entity_id)
      .maybeSingle();
    if (generalPaymentError) throw generalPaymentError;

    const effective = Object.keys(snapshot).length > 0
      ? snapshot
      : (generalPayment ?? {});

    if (
      event.operation !== "delete" &&
      (!generalPayment || String(generalPayment.admin_id) !== source.admin_id)
    ) {
      return { skip: "entity_missing" };
    }

    const customerId = String(
      effective.customer_id ?? generalPayment?.customer_id ?? "",
    ).trim();
    if (!customerId) return { skip: "customer_missing" };

    const contactId = await remoteLink(
      admin,
      source,
      "customer",
      customerId,
    );
    if (!contactId) {
      await ensureCustomerOutbox(admin, source, customerId);
      return { defer: "customer_mapping_pending" };
    }

    const transactionDate = String(
      effective.transaction_date ??
        generalPayment?.created_at ??
        effective.created_at ??
        new Date().toISOString(),
    );
    const amountValue = Number(
      effective.amount ?? generalPayment?.amount ?? 0,
    );
    const note = String(effective.note ?? generalPayment?.note ?? "");

    return {
      request: event.operation === "update"
        ? buildTransactionUpdate({
          remoteId: Number(existingRemoteId),
          userId: Number(source.legacy_user_id),
          contactId: Number(contactId),
          transactionType: "PAYMENT",
          amount: amountValue,
          currency: "IQD",
          transactionDate,
          note,
        })
        : buildTransactionCreate({
          userId: Number(source.legacy_user_id),
          contactId: Number(contactId),
          transactionType: "PAYMENT",
          amount: amountValue,
          currency: "IQD",
          transactionDate,
          note,
        }),
    };
  }

  const { data: payment, error: paymentError } = await admin.from("payments")
    .select("id, debt_id, amount, note, created_at")
    .eq("id", event.entity_id)
    .maybeSingle();
  if (paymentError) throw paymentError;
  if (!payment) return { skip: "entity_missing" };
  const effective = Object.keys(snapshot).length > 0 ? snapshot : payment;

  const { data: debt, error: debtError } = await admin.from("debts")
    .select("id, customer_id, currency")
    .eq("id", payment.debt_id)
    .maybeSingle();
  if (debtError) throw debtError;
  if (!debt) return { skip: "parent_debt_missing" };

  const contactId = await remoteLink(
    admin,
    source,
    "customer",
    String(effective.customer_id ?? debt.customer_id),
  );
  if (!contactId) {
    await ensureCustomerOutbox(
      admin,
      source,
      String(effective.customer_id ?? debt.customer_id),
    );
    return { defer: "customer_mapping_pending" };
  }

  return {
    request: event.operation === "update"
      ? buildTransactionUpdate({
        remoteId: Number(existingRemoteId),
        userId: Number(source.legacy_user_id),
        contactId: Number(contactId),
        transactionType: "PAYMENT",
        amount: Number(effective.amount ?? payment.amount ?? 0),
        currency: String(effective.currency ?? debt.currency ?? "IQD"),
        transactionDate: String(
          effective.transaction_date ?? payment.created_at ??
            new Date().toISOString(),
        ),
        note: String(effective.note ?? payment.note ?? ""),
      })
      : buildTransactionCreate({
        userId: Number(source.legacy_user_id),
        contactId: Number(contactId),
        transactionType: "PAYMENT",
        amount: Number(effective.amount ?? payment.amount ?? 0),
        currency: String(effective.currency ?? debt.currency ?? "IQD"),
        transactionDate: String(
          effective.transaction_date ?? payment.created_at ??
            new Date().toISOString(),
        ),
        note: String(effective.note ?? payment.note ?? ""),
      }),
  };
}

async function processEvent(
  admin: any,
  source: Source,
  event: OutboxEvent,
): Promise<Record<string, unknown>> {
  if (!(await claimEvent(admin, event))) {
    return { id: event.id, status: "not_claimed" };
  }

  let outboundRequest: DaftarWriteRequest | null = null;
  try {
    const built = await buildEventWrite(admin, source, event);
    if ("skip" in built) {
      await markEvent(admin, event.id, {
        status: "skipped",
        remote_id: /^\d+$/.test(built.skip) ? built.skip : null,
        last_error: built.skip,
      });
      return { id: event.id, status: "skipped", reason: built.skip };
    }
    if ("defer" in built) {
      await deferEvent(admin, event, built.defer);
      return { id: event.id, status: "deferred", reason: built.defer };
    }

    outboundRequest = built.request;

    // Before retrying a customer create, reconcile against Daftar live state.
    // This makes retrying an earlier ambiguous 5xx idempotent: if Daftar
    // committed the previous request but lost the response, we map it instead
    // of creating a duplicate contact.
    if (event.operation === "create" && event.entity_kind === "customer") {
      const profile = await loadCustomerForOutbound(
        admin,
        source,
        event.entity_id,
      );
      if (profile) {
        const existingRemoteCustomer = await findRemoteCustomerLive(
          source,
          profile,
        );
        if (existingRemoteCustomer) {
          await recordMapping(admin, source, event, existingRemoteCustomer);
          await markEvent(admin, event.id, {
            status: "sent",
            remote_id: existingRemoteCustomer,
            last_error: "reconciled_before_retry:live_lookup",
            sent_at: new Date().toISOString(),
          });
          return {
            id: event.id,
            status: "sent",
            remote_id: existingRemoteCustomer,
            reconciliation: "live_lookup_before_retry",
          };
        }
      }
    }

    const sent = await sendWrite(source, built.request);
    try {
      if (event.operation === "create") {
        await recordMapping(admin, source, event, sent.remoteId);
      } else if (
        event.operation === "delete" &&
        (event.entity_kind === "debt" || event.entity_kind === "payment")
      ) {
        await finalizeRemoteTransactionDelete(
          admin,
          source,
          event,
          sent.remoteId,
        );
      }
    } catch (error) {
      throw new Error(
        `ambiguous_mapping_failed:${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
    await markEvent(admin, event.id, {
      status: "sent",
      remote_id: sent.remoteId,
      last_error: null,
      sent_at: new Date().toISOString(),
    });
    return {
      id: event.id,
      status: "sent",
      remote_id: sent.remoteId,
      http_status: sent.status,
    };
  } catch (error) {
    let message = error instanceof Error ? error.message : String(error);
    const ambiguous = message.startsWith("ambiguous_remote_");

    if (
      ambiguous && outboundRequest && event.operation === "create" &&
      event.entity_kind === "customer"
    ) {
      try {
        const recovered = await recoverAmbiguousCustomerCreate(
          admin,
          source,
          event,
          outboundRequest,
        );
        if (recovered) return recovered;
      } catch (recoveryError) {
        const recoveryMessage = recoveryError instanceof Error
          ? recoveryError.message
          : String(recoveryError);
        const retryableRecovery =
          recoveryMessage.startsWith("ambiguous_remote_http_") ||
          recoveryMessage.startsWith("remote_rate_limited") ||
          recoveryMessage.startsWith("remote_contact_lookup_http_");
        const nextStatus = retryableRecovery ? "failed" : "blocked";
        const retryMinutes = Math.min(
          30,
          Math.max(2, Math.pow(2, Math.min(Number(event.attempts ?? 0), 4))),
        );
        await markEvent(admin, event.id, {
          status: nextStatus,
          last_error: `customer_recovery_failed:${recoveryMessage}`.slice(
            0,
            1000,
          ),
          next_attempt_at: new Date(Date.now() + retryMinutes * 60_000)
            .toISOString(),
        });
        return {
          id: event.id,
          status: nextStatus,
          retry_in_minutes: retryableRecovery ? retryMinutes : null,
          error: `customer_recovery_failed:${recoveryMessage}`,
        };
      }
    }

    if (
      ambiguous && outboundRequest?.method === "DELETE" &&
      (event.entity_kind === "debt" || event.entity_kind === "payment")
    ) {
      try {
        const recoveredDelete = await reconcileAmbiguousTransactionDelete(
          admin,
          source,
          event,
          outboundRequest,
        );
        if (recoveredDelete) return recoveredDelete;
      } catch (verificationError) {
        const verificationMessage = verificationError instanceof Error
          ? verificationError.message
          : String(verificationError);
        // Verification failure must never convert an uncertain DELETE into
        // success. Fall through to the idempotent retry path below.
        message = `${message};delete_verification_failed:${verificationMessage}`;
      }
    }

    const rejected = message.startsWith("remote_rejected_");
    // DELETE is idempotent. Credit-limit rollback UPDATE is also idempotent:
    // it repeatedly restores the same known-good debt snapshot. Therefore an
    // ambiguous network/5xx outcome must be retried instead of becoming a
    // permanent blocked event.
    const retryableAmbiguousDelete =
      ambiguous && outboundRequest?.method === "DELETE";
    const retryableAmbiguousCreditRollback =
      ambiguous && isCreditLimitRollback(event) &&
      (outboundRequest?.method === "PUT" ||
        outboundRequest?.method === "DELETE");
    const retryableAmbiguous =
      retryableAmbiguousDelete || retryableAmbiguousCreditRollback;
    const nextStatus = retryableAmbiguous
      ? "failed"
      : (ambiguous || rejected ? "blocked" : "failed");
    const retryMinutes = retryableAmbiguous
      ? Math.min(
        30,
        Math.max(1, Math.pow(2, Math.min(Number(event.attempts ?? 0), 4))),
      )
      : 5;
    await markEvent(admin, event.id, {
      status: nextStatus,
      last_error: message.slice(0, 1000),
      next_attempt_at: new Date(Date.now() + retryMinutes * 60_000).toISOString(),
    });
    return {
      id: event.id,
      status: nextStatus,
      retry_in_minutes: retryableAmbiguous ? retryMinutes : null,
      error: message,
    };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceCredential = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    envJsonKey("SUPABASE_SECRET_KEYS") ?? "";
  if (!url || !serviceCredential) {
    return json({ error: "server_not_configured" }, 500);
  }

  const admin = createClient(url, serviceCredential, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const body = await req.json().catch(() => ({}));
  const sourceId = String(body?.source_id ?? "").trim();
  const action = String(body?.action ?? "drain");
  if (!sourceId) return json({ error: "unauthorized" }, 401);

  const { data: sourceRow, error } = await admin.from("daftar_sync_sources")
    .select(
      "id, admin_id, legacy_user_id, source_fingerprint, api_base_url, trigger_secret_hash, " +
        "enabled, sync_mode, outbound_sync_enabled, outbound_write_contract_status",
    )
    .eq("id", sourceId)
    .maybeSingle();

  if (error || !sourceRow) return json({ error: "sync_source_not_found" }, 404);
  const source = sourceRow as unknown as Source;
  if (!isOfficialDaftarSource(source)) {
    return json({ error: "sync_source_not_allowed" }, 403);
  }

  const authorized = await authorizeDaftarSyncRequest({
    authorizationHeader: req.headers.get("authorization"),
    providedSecret: req.headers.get("x-daftar-sync-secret") ?? "",
    serviceCredential,
    expectedSecretHash: String(source.trigger_secret_hash ?? ""),
  });
  if (!authorized) return json({ error: "unauthorized" }, 401);

  if (action === "probe") {
    const base = String(source.api_base_url);
    const rootContacts = fixedDaftarUrl(base, "contacts");
    const rootTransactions = fixedDaftarUrl(base, "transactions");
    const missingContact = new URL(
      "contacts/0",
      base.endsWith("/") ? base : base + "/",
    );
    const missingTransaction = new URL(
      "transactions/0",
      base.endsWith("/") ? base : base + "/",
    );
    const results = await Promise.all([
      probeEndpoint(rootContacts),
      probeEndpoint(rootTransactions),
      probeEndpoint(missingContact),
      probeEndpoint(missingTransaction),
      probeEndpoint(missingContact, "PUT", {
        user_id: 28,
        name: { invalid: true },
        phone: { invalid: true },
        created_at: { invalid: true },
        updated_at: { invalid: true },
      }),
      probeEndpoint(missingContact, "PATCH"),
      probeEndpoint(missingContact, "DELETE"),
      probeEndpoint(missingTransaction, "PUT", {
        user_id: 28,
        contact_id: "invalid",
        transaction_type: "INVALID",
        amount: "invalid",
        currency: { invalid: true },
        transaction_date: { invalid: true },
        note: { invalid: true },
      }),
      probeEndpoint(missingTransaction, "PATCH"),
      probeEndpoint(missingTransaction, "DELETE"),
      probeEndpoint(rootContacts, "POST", {
        user_id: 28,
        name: { invalid: true },
        phone: { invalid: true },
      }),
      probeEndpoint(rootTransactions, "POST", {
        user_id: 28,
        contact_id: "invalid",
        transaction_type: "INVALID",
        amount: "invalid",
        currency: "IQD",
        transaction_date: "invalid",
        note: { invalid: true },
      }),
      probeEndpoint(rootContacts, "POST", {
        user_id: "invalid",
        name: "ZHIROX contract probe",
        phone: "",
        created_at: "2026-09-20T00:00:00.000Z",
        updated_at: "2026-09-20T00:00:00.000Z",
      }),
      probeEndpoint(rootTransactions, "POST", {
        user_id: "invalid",
        contact_id: 1,
        transaction_type: "LOAN",
        amount: 1,
        currency: "IQD",
        transaction_date: "2026-09-20T00:00:00.000Z",
        note: "contract probe",
      }),
      // Exact shapes used by the recovered 0.2.7 client. The intentionally
      // invalid user_id guarantees these probes cannot create production data.
      probeEndpoint(rootContacts, "POST", {
        user_id: "invalid",
        contact_name: "ZHIROX contract probe",
        contact_phone: "",
      }),
      probeEndpoint(rootTransactions, "POST", {
        user_id: "invalid",
        contact_id: 1,
        transaction_type: "LOAN",
        amount_iqd: 1,
        amount_usd: 0,
        transaction_date: "2026-09-20T00:00:00.000Z",
        note: "contract probe",
      }),
      // Non-existent IDs make the PUT probes non-mutating while validating
      // the legacy update routes and request shapes.
      probeEndpoint(missingContact, "PUT", {
        user_id: 28,
        contact_name: "ZHIROX contract probe",
        contact_phone: "",
      }),
      probeEndpoint(missingTransaction, "PUT", {
        note: "ZHIROX contract probe",
      }),
      // Current backend shape against non-existent ID 0. This validates a
      // real PUT path without mutating any production record.
      probeEndpoint(missingContact, "PUT", {
        user_id: 28,
        name: "ZHIROX non-mutating contract probe",
        phone: "",
        created_at: "2026-09-20T00:00:00.000Z",
        updated_at: "2026-09-20T00:00:00.000Z",
      }),
    ]);
    return json({
      ok: true,
      action: "probe",
      source_id: source.id,
      contract_status: source.outbound_write_contract_status,
      results,
    });
  }

  if (action !== "drain") return json({ error: "unsupported_action" }, 400);
  if (source.sync_mode !== "zhirox_primary") {
    return json({ error: "outbound_requires_zhirox_primary" }, 409);
  }
  if (source.outbound_sync_enabled !== true) {
    return json({ error: "outbound_sync_disabled" }, 409);
  }
  if (source.outbound_write_contract_status !== "verified") {
    return json({ error: "write_contract_unverified" }, 409);
  }

  const staleCutoff = new Date(Date.now() - 2 * 60_000).toISOString();

  // Credit-limit rollback writes are idempotent and must never be stranded by
  // a worker interruption. Put stale processing rows back into the retry path.
  await admin.from("daftar_outbound_events").update({
    status: "failed",
    last_error: "ambiguous_worker_interruption_retryable_credit_rollback",
    next_attempt_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  })
    .eq("sync_source_id", source.id)
    .eq("status", "processing")
    .contains("payload_snapshot", {
      source: "daftar_official_app_inbound_guard",
      rejection_reason: "credit_limit_exceeded",
    })
    .lt("updated_at", staleCutoff);

  // If an older worker already stranded an ambiguous credit-limit rollback as
  // blocked, recover only ambiguity/interruption cases; real remote 4xx
  // rejections remain blocked for investigation.
  await admin.from("daftar_outbound_events").update({
    status: "failed",
    next_attempt_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  })
    .eq("sync_source_id", source.id)
    .eq("status", "blocked")
    .contains("payload_snapshot", {
      source: "daftar_official_app_inbound_guard",
      rejection_reason: "credit_limit_exceeded",
    })
    .or(
      "last_error.like.ambiguous_remote_%,last_error.eq.ambiguous_worker_interruption",
    );

  await admin.from("daftar_outbound_events").update({
    status: "blocked",
    last_error: "ambiguous_worker_interruption",
    updated_at: new Date().toISOString(),
  })
    .eq("sync_source_id", source.id)
    .eq("status", "processing")
    .lt("updated_at", staleCutoff);

  const reconciled = await reconcileBlockedCustomerEvents(admin, source);

  const dueAt = new Date().toISOString();
  const selectColumns =
    "id, entity_kind, entity_id, operation, status, attempts, payload_snapshot, remote_id_snapshot, created_at";

  // Credit-limit rollback writes are financial safety actions. Fetch them
  // separately so a busy ordinary outbox can never delay restoring/removing
  // an over-limit Daftar transaction.
  const { data: rollbackEvents, error: rollbackEventsError } = await admin
    .from("daftar_outbound_events")
    .select(selectColumns)
    .eq("sync_source_id", source.id)
    .in("status", ["pending", "failed"])
    .lte("next_attempt_at", dueAt)
    .contains("payload_snapshot", {
      source: "daftar_official_app_inbound_guard",
      rejection_reason: "credit_limit_exceeded",
    })
    .order("created_at", { ascending: true })
    .limit(10);
  if (rollbackEventsError) {
    return json({ error: "credit_rollback_outbox_read_failed" }, 500);
  }

  const priorityIds = new Set(
    (rollbackEvents ?? []).map((event: any) => String(event.id)),
  );
  const remainingSlots = Math.max(0, 10 - priorityIds.size);
  let normalEvents: any[] = [];

  if (remainingSlots > 0) {
    const { data, error: eventsError } = await admin
      .from("daftar_outbound_events")
      .select(selectColumns)
      .eq("sync_source_id", source.id)
      .in("status", ["pending", "failed"])
      .lte("next_attempt_at", dueAt)
      .order("created_at", { ascending: true })
      .limit(20);
    if (eventsError) return json({ error: "outbox_read_failed" }, 500);
    normalEvents = (data ?? [])
      .filter((event: any) => !priorityIds.has(String(event.id)))
      .slice(0, remainingSlots);
  }

  const orderedEvents = [
    ...(rollbackEvents ?? []),
    ...normalEvents,
  ].sort((left: any, right: any) => {
    const leftRollback = isCreditLimitRollback(left as OutboxEvent);
    const rightRollback = isCreditLimitRollback(right as OutboxEvent);
    if (leftRollback !== rightRollback) return leftRollback ? -1 : 1;

    const byCreated = Date.parse(String(left.created_at ?? "")) -
      Date.parse(String(right.created_at ?? ""));
    if (byCreated) return byCreated;
    if (left.operation === "delete" && right.operation === "delete") {
      const priority: Record<string, number> = {
        payment: 0,
        debt: 1,
        customer: 2,
      };
      return (priority[left.entity_kind] ?? 3) -
        (priority[right.entity_kind] ?? 3);
    }
    return 0;
  });
  const results: Record<string, unknown>[] = [];
  for (const raw of orderedEvents) {
    results.push(await processEvent(admin, source, raw as OutboxEvent));
  }

  return json({
    ok: true,
    action: "drain",
    processed: results.length,
    reconciled,
    results,
  });
});