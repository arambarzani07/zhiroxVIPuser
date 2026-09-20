import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { authorizeDaftarSyncRequest } from "../_shared/daftar_sync_auth.ts";
import {
  buildContactCreate,
  buildTransactionCreate,
  fixedDaftarUrl,
  parseCreatedId,
  type DaftarWriteRequest,
} from "../_shared/daftar_outbound/client.ts";

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
  sync_mode: string;
  outbound_sync_enabled: boolean;
  outbound_write_contract_status: string;
};

type OutboxEvent = {
  id: string;
  entity_kind: "customer" | "debt" | "payment";
  entity_id: string;
  operation: "create";
  status: "pending" | "failed" | "blocked";
  attempts: number;
  created_at?: string;
  last_error?: string | null;
};

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

function datesAreClose(left: unknown, right: unknown, toleranceMs: number): boolean {
  const a = Date.parse(String(left ?? ""));
  const b = Date.parse(String(right ?? ""));
  return Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) <= toleranceMs;
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
      },
      body: JSON.stringify(request.body),
    });
  } catch (error) {
    throw new Error(
      `ambiguous_remote_write:${error instanceof Error ? error.message : String(error)}`,
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
    if (response.status === 429) throw new Error("remote_rate_limited");
    if (response.status >= 500) {
      throw new Error(`ambiguous_remote_http_${response.status}`);
    }
    throw new Error(
      `remote_rejected_${response.status}:${text.slice(0, 500)}`,
    );
  }

  let remoteId: string;
  try {
    remoteId = parseCreatedId(payload);
  } catch (error) {
    throw new Error(
      `ambiguous_remote_missing_id:${error instanceof Error ? error.message : String(error)}`,
    );
  }
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

    const { error: linkError } = await admin.from("legacy_import_links").upsert({
      admin_id: source.admin_id,
      source_fingerprint: source.source_fingerprint,
      entity_kind: "payment",
      source_id: allocationSourceId,
      target_id: event.entity_id,
    }, {
      onConflict: "admin_id,source_fingerprint,entity_kind,source_id",
      ignoreDuplicates: true,
    });
    if (linkError) throw linkError;

    const { error: seenPaymentError } = await admin.from("daftar_sync_seen").upsert({
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

    const { error: seenAllocationError } = await admin.from("daftar_sync_seen").upsert({
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
    .select("id, entity_kind, entity_id, operation, status, attempts, created_at, last_error")
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
    if (!profile || profile.role !== "customer" || profile.admin_id !== source.admin_id) {
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
        reconciliation: candidates.length === 0 ? "no_match" : "multiple_matches",
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
): Promise<{ request: DaftarWriteRequest } | { skip: string } | { defer: string }> {
  const existingRemoteId = await remoteLink(
    admin,
    source,
    event.entity_kind,
    event.entity_id,
  );
  if (existingRemoteId) return { skip: existingRemoteId };

  if (event.entity_kind === "customer") {
    const { data, error } = await admin.from("profiles")
      .select("id, name, phone, role, admin_id, created_at, updated_at")
      .eq("id", event.entity_id)
      .maybeSingle();
    if (error) throw error;
    if (!data || data.role !== "customer" || data.admin_id !== source.admin_id) {
      return { skip: "entity_missing" };
    }
    const createdAt = String(data.created_at ?? new Date().toISOString());
    const updatedAt = String(data.updated_at ?? data.created_at ?? createdAt);
    return {
      request: buildContactCreate({
        userId: Number(source.legacy_user_id),
        name: String(data.name ?? "").trim(),
        phone: String(data.phone ?? "").trim(),
        createdAt,
        updatedAt,
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

    const contactId = await remoteLink(
      admin,
      source,
      "customer",
      String(data.customer_id),
    );
    if (!contactId) {
      await ensureCustomerOutbox(admin, source, String(data.customer_id));
      return { defer: "customer_mapping_pending" };
    }

    return {
      request: buildTransactionCreate({
        userId: Number(source.legacy_user_id),
        contactId: Number(contactId),
        transactionType: "LOAN",
        amount: Number(data.amount ?? 0),
        currency: String(data.currency ?? "IQD"),
        transactionDate: String(
          data.custom_date ?? data.created_at ?? new Date().toISOString(),
        ),
        note: String(data.description ?? ""),
      }),
    };
  }

  const { data: payment, error: paymentError } = await admin.from("payments")
    .select("id, debt_id, amount, note, created_at")
    .eq("id", event.entity_id)
    .maybeSingle();
  if (paymentError) throw paymentError;
  if (!payment) return { skip: "entity_missing" };

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
    String(debt.customer_id),
  );
  if (!contactId) {
    await ensureCustomerOutbox(admin, source, String(debt.customer_id));
    return { defer: "customer_mapping_pending" };
  }

  return {
    request: buildTransactionCreate({
      userId: Number(source.legacy_user_id),
      contactId: Number(contactId),
      transactionType: "PAYMENT",
      amount: Number(payment.amount ?? 0),
      currency: String(debt.currency ?? "IQD"),
      transactionDate: String(payment.created_at ?? new Date().toISOString()),
      note: String(payment.note ?? ""),
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

    const sent = await sendWrite(source, built.request);
    try {
      await recordMapping(admin, source, event, sent.remoteId);
    } catch (error) {
      throw new Error(
        `ambiguous_mapping_failed:${error instanceof Error ? error.message : String(error)}`,
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
    const message = error instanceof Error ? error.message : String(error);
    const ambiguous = message.startsWith("ambiguous_remote_");
    const rejected = message.startsWith("remote_rejected_");
    const nextStatus = ambiguous || rejected ? "blocked" : "failed";
    await markEvent(admin, event.id, {
      status: nextStatus,
      last_error: message.slice(0, 1000),
      next_attempt_at: new Date(Date.now() + 5 * 60_000).toISOString(),
    });
    return { id: event.id, status: nextStatus, error: message };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceCredential = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    envJsonKey("SUPABASE_SECRET_KEYS") ?? "";
  if (!url || !serviceCredential) return json({ error: "server_not_configured" }, 500);

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
        "sync_mode, outbound_sync_enabled, outbound_write_contract_status",
    )
    .eq("id", sourceId)
    .maybeSingle();

  if (error || !sourceRow) return json({ error: "sync_source_not_found" }, 404);
  const source = sourceRow as unknown as Source;
  if (
    Number(source.legacy_user_id) !== 28 ||
    source.source_fingerprint !== "daftar-live-account-28-v1"
  ) {
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

  await admin.from("daftar_outbound_events").update({
    status: "blocked",
    last_error: "ambiguous_worker_interruption",
    updated_at: new Date().toISOString(),
  })
    .eq("sync_source_id", source.id)
    .eq("status", "processing")
    .lt("updated_at", new Date(Date.now() - 2 * 60_000).toISOString());

  const reconciled = await reconcileBlockedCustomerEvents(admin, source);

  const { data: events, error: eventsError } = await admin
    .from("daftar_outbound_events")
    .select("id, entity_kind, entity_id, operation, status, attempts")
    .eq("sync_source_id", source.id)
    .in("status", ["pending", "failed"])
    .lte("next_attempt_at", new Date().toISOString())
    .order("created_at", { ascending: true })
    .limit(10);
  if (eventsError) return json({ error: "outbox_read_failed" }, 500);

  const results: Record<string, unknown>[] = [];
  for (const raw of events ?? []) {
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
