import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-daftar-sync-secret",
};

type SyncSource = {
  id: string;
  admin_id: string;
  legacy_user_id: number;
  source_fingerprint: string;
  api_base_url: string;
  trigger_secret_hash: string;
  last_contact_id: number;
  last_transaction_id: number;
  contacts_etag?: string | null;
  transactions_etag?: string | null;
  mirror_bootstrapped_at?: string | null;
};

type LegacyContact = {
  id: number;
  user_id: number;
  name: string;
  phone?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type LegacyTransaction = {
  id: number;
  user_id: number;
  contact_id: number;
  transaction_type: "LOAN" | "PAYMENT";
  amount: string | number;
  currency?: string | null;
  transaction_date?: string | null;
  note?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    return parsed.default ?? Object.values(parsed)[0] ?? null;
  } catch (_) {
    return raw;
  }
}

function isTransientDatabaseError(error: { message?: string; code?: string } | null): boolean {
  if (!error) return false;
  const message = String(error.message ?? "").toLowerCase();
  return message.includes("timeout") ||
    message.includes("gateway") ||
    message.includes("temporarily unavailable") ||
    String(error.code ?? "").startsWith("5");
}

async function loadSyncSource(admin: any, sourceId: string) {
  let lastError: any = null;
  for (let attempt = 1; attempt <= 4; attempt++) {
    const { data, error } = await admin.from("daftar_sync_sources")
      .select("*")
      .eq("id", sourceId)
      .eq("enabled", true)
      .maybeSingle();
    if (!error) return { data, error: null };
    lastError = error;
    if (!isTransientDatabaseError(error) || attempt === 4) break;
    await new Promise((resolve) => setTimeout(resolve, attempt * 750));
  }
  return { data: null, error: lastError };
}

function amount(value: unknown): number {
  const parsed = Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed < 0) throw new Error("invalid_amount");
  return Math.round(parsed * 100) / 100;
}

function normalizePhone(value: unknown): string {
  let digits = String(value ?? "").replace(/\D/g, "");
  if (digits.startsWith("964") && digits.length === 13) digits = `0${digits.slice(3)}`;
  return digits;
}

function randomPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  return `${Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("")}Aa1!`;
}

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function stableUuid(namespace: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(namespace)));
  const bytes = digest.slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

type SourceFetch<T> = {
  rows: T[] | null;
  etag: string | null;
  notModified: boolean;
};

async function fetchRows<T>(
  url: string,
  legacyUserId: number,
  etag?: string | null,
): Promise<SourceFetch<T>> {
  const endpoint = new URL(url);
  endpoint.searchParams.set("user_id", String(legacyUserId));
  let response: Response | null = null;
  let lastError: unknown = null;
  for (let attempt = 1; attempt <= 4; attempt++) {
    try {
      response = await fetch(endpoint, {
        headers: {
          Accept: "application/json",
          ...(etag ? { "If-None-Match": etag } : {}),
        },
        signal: AbortSignal.timeout(30_000),
      });
      if (response.ok || response.status === 304) break;
      if (![408, 425, 429, 500, 502, 503, 504].includes(response.status)) break;
      lastError = new Error(`source_http_${response.status}`);
    } catch (error) {
      lastError = error;
    }
    if (attempt < 4) {
      const jitter = crypto.getRandomValues(new Uint16Array(1))[0] % 300;
      await new Promise((resolve) => setTimeout(resolve, attempt * attempt * 500 + jitter));
    }
  }
  if (!response) throw lastError instanceof Error ? lastError : new Error("source_unreachable");
  if (response.status === 304) {
    return { rows: null, etag: response.headers.get("etag") ?? etag ?? null, notModified: true };
  }
  if (!response.ok) throw new Error(`source_http_${response.status}`);
  const payload = await response.json();
  if (payload?.success !== true || !Array.isArray(payload?.data)) throw new Error("invalid_source_response");
  return {
    rows: payload.data as T[],
    etag: response.headers.get("etag"),
    notModified: false,
  };
}

async function upsertSeen(
  admin: any,
  syncSourceId: string,
  entityKind: string,
  sourceId: string,
  targetId: string | null,
  payloadHash: string | null,
) {
  const { error } = await admin.from("daftar_sync_seen").upsert({
    sync_source_id: syncSourceId,
    entity_kind: entityKind,
    source_id: sourceId,
    target_id: targetId,
    payload_hash: payloadHash,
  }, { onConflict: "sync_source_id,entity_kind,source_id", ignoreDuplicates: true });
  if (error) throw error;
}

async function mirrorRows(
  admin: any,
  table: "daftar_mirror_contacts" | "daftar_mirror_transactions",
  syncSourceId: string,
  rows: Array<{ id: number }>,
) {
  const mirroredAt = new Date().toISOString();
  for (let offset = 0; offset < rows.length; offset += 250) {
    const chunk = rows.slice(offset, offset + 250);
    const records = await Promise.all(
      chunk.map(async (row) => ({
        sync_source_id: syncSourceId,
        source_id: String(row.id),
        payload: row,
        payload_hash: await sha256Hex(JSON.stringify(row)),
        last_mirrored_at: mirroredAt,
      })),
    );
    const { error } = await admin.from(table).upsert(records, {
      onConflict: "sync_source_id,source_id",
      defaultToNull: false,
    });
    if (error) throw error;
  }
}

async function upsertLegacyLink(
  admin: any,
  source: SyncSource,
  entityKind: "customer" | "debt" | "payment",
  sourceId: string,
  targetId: string,
) {
  const { error } = await admin.from("legacy_import_links").upsert({
    admin_id: source.admin_id,
    source_fingerprint: source.source_fingerprint,
    entity_kind: entityKind,
    source_id: sourceId,
    target_id: targetId,
  }, { onConflict: "admin_id,source_fingerprint,entity_kind,source_id", ignoreDuplicates: true });
  if (error) throw error;
}

async function findLegacyTarget(admin: any, source: SyncSource, entityKind: string, sourceId: string) {
  const { data, error } = await admin.from("legacy_import_links")
    .select("target_id")
    .eq("admin_id", source.admin_id)
    .eq("entity_kind", entityKind)
    .eq("source_id", sourceId)
    .limit(20);
  if (error) throw error;
  const targets = [...new Set((data ?? []).map((row: { target_id: string }) => row.target_id))];
  if (targets.length > 1) throw new Error(`${entityKind}_source_id_conflict:${sourceId}`);
  return targets[0] ?? null;
}

async function ensureCustomer(
  admin: any,
  source: SyncSource,
  contact: LegacyContact,
): Promise<{ id: string; created: boolean; reused: boolean }> {
  const sourceId = String(contact.id);
  const { data: seen, error: seenError } = await admin.from("daftar_sync_seen")
    .select("target_id")
    .eq("sync_source_id", source.id)
    .eq("entity_kind", "customer")
    .eq("source_id", sourceId)
    .maybeSingle();
  if (seenError) throw seenError;
  if (seen?.target_id) return { id: seen.target_id, created: false, reused: true };

  const legacyTarget = await findLegacyTarget(admin, source, "customer", sourceId);
  if (legacyTarget) {
    const { data: profile } = await admin.from("profiles")
      .select("id, role, admin_id")
      .eq("id", legacyTarget)
      .maybeSingle();
    if (!profile || profile.role !== "customer" || profile.admin_id !== source.admin_id) {
      throw new Error(`customer_target_conflict:${sourceId}`);
    }
    await upsertSeen(admin, source.id, "customer", sourceId, legacyTarget, await sha256Hex(JSON.stringify(contact)));
    await upsertLegacyLink(admin, source, "customer", sourceId, legacyTarget);
    return { id: legacyTarget, created: false, reused: true };
  }

  const phone = normalizePhone(contact.phone) || `legacy_${source.admin_id.slice(0, 8)}_${sourceId}`;
  const { data: existingProfile, error: profileLookupError } = await admin.from("profiles")
    .select("id, role, admin_id")
    .eq("phone", phone)
    .maybeSingle();
  if (profileLookupError) throw profileLookupError;

  let customerId: string;
  let created = false;
  if (existingProfile) {
    if (existingProfile.role !== "customer" || existingProfile.admin_id !== source.admin_id) {
      throw new Error(`phone_collision:${sourceId}`);
    }
    customerId = existingProfile.id;
  } else {
    const { data: createdAuth, error: authError } = await admin.auth.admin.createUser({
      email: `${phone}@zhirox.local`,
      password: randomPassword(),
      email_confirm: true,
      user_metadata: {
        imported: true,
        legacy_source_id: sourceId,
        admin_id: source.admin_id,
      },
    });
    if (authError || !createdAuth.user) throw new Error(`auth_create_failed:${sourceId}:${authError?.message ?? "unknown"}`);
    customerId = createdAuth.user.id;
    created = true;
    const occurredAt = contact.created_at ?? new Date().toISOString();
    const { error: profileError } = await admin.from("profiles").insert({
      id: customerId,
      name: String(contact.name ?? "").trim(),
      father_name: "",
      grandfather_name: "",
      phone,
      role: "customer",
      market_name: "",
      admin_id: source.admin_id,
      created_by: source.admin_id,
      approved: true,
      active: true,
      debt_limit: 0,
      debt_duration: 30,
      is_system_owner: false,
      created_at: occurredAt,
      updated_at: contact.updated_at ?? occurredAt,
    });
    if (profileError) {
      await admin.auth.admin.deleteUser(customerId);
      throw new Error(`profile_create_failed:${sourceId}:${profileError.message}`);
    }
  }

  await upsertSeen(admin, source.id, "customer", sourceId, customerId, await sha256Hex(JSON.stringify(contact)));
  await upsertLegacyLink(admin, source, "customer", sourceId, customerId);
  return { id: customerId, created, reused: !created };
}

async function sourceDebtIds(admin: any, syncSourceId: string): Promise<string[]> {
  const ids: string[] = [];
  for (let from = 0;; from += 1000) {
    const { data, error } = await admin.from("daftar_sync_seen")
      .select("target_id")
      .eq("sync_source_id", syncSourceId)
      .eq("entity_kind", "debt")
      .not("target_id", "is", null)
      .range(from, from + 999);
    if (error) throw error;
    ids.push(...(data ?? []).map((row: { target_id: string }) => row.target_id));
    if ((data ?? []).length < 1000) break;
  }
  return ids;
}

async function availableSourceDebts(
  admin: any,
  linkedIds: Set<string>,
  customerId: string,
  currency: string,
) {
  const { data, error } = await admin.from("debts")
    .select("id, remaining, custom_date, created_at")
    .eq("customer_id", customerId)
    .eq("currency", currency)
    .eq("is_deleted", false)
    .gt("remaining", 0)
    .limit(5000);
  if (error) throw error;
  const rows = (data ?? []).filter((row: { id: string }) => linkedIds.has(row.id));
  rows.sort((left, right) => {
    const dateDifference = Date.parse(left.custom_date ?? left.created_at) - Date.parse(right.custom_date ?? right.created_at);
    return dateDifference || String(left.id).localeCompare(String(right.id));
  });
  return rows;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  // Prefer the stable built-in service-role key. Rotating secret-key bundles can
  // contain more than one key, and selecting the first JSON value is not stable
  // across warm Edge Function instances.
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? envJsonKey("SUPABASE_SECRET_KEYS");
  if (!secret) return json({ error: "server_not_configured" }, 500);
  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

  let source: SyncSource | null = null;
  let runId: string | null = null;
  const startedAt = Date.now();
  const counters = {
    fetched_contacts: 0,
    fetched_transactions: 0,
    new_customers: 0,
    new_debts: 0,
    new_payment_allocations: 0,
    new_zero_events: 0,
    reused_records: 0,
  };

  try {
    const body = await req.json().catch(() => ({}));
    const sourceId = String(body?.source_id ?? "").trim();
    const providedSecret = req.headers.get("x-daftar-sync-secret") ?? "";
    if (!sourceId || !providedSecret) return json({ error: "unauthorized" }, 401);

    const { data: sourceRow, error: sourceError } = await loadSyncSource(admin, sourceId);
    if (sourceError || !sourceRow) {
      return json({
        error: "sync_source_not_found",
        database_code: sourceError?.code ?? null,
        database_message: sourceError?.message ?? null,
      }, sourceError && isTransientDatabaseError(sourceError) ? 503 : 404);
    }
    source = sourceRow as SyncSource;

    const providedHash = await sha256Hex(providedSecret);
    if (!constantTimeEqual(providedHash, source.trigger_secret_hash)) return json({ error: "unauthorized" }, 401);

    const { data: claimed, error: claimError } = await admin.rpc("claim_daftar_sync", { p_source_id: source.id });
    if (claimError) throw claimError;
    if (claimed !== true) return json({ ok: true, skipped: true, reason: "sync_already_running" });

    const { data: run, error: runError } = await admin.from("daftar_sync_runs")
      .insert({ sync_source_id: source.id, status: "running" })
      .select("id")
      .single();
    if (runError) throw runError;
    runId = run.id;

    const mirrorBootstrap = !source.mirror_bootstrapped_at;
    let [contactsFetch, transactionsFetch] = await Promise.all([
      fetchRows<LegacyContact>(
        `${source.api_base_url}/contacts`,
        source.legacy_user_id,
        mirrorBootstrap ? null : source.contacts_etag,
      ),
      fetchRows<LegacyTransaction>(
        `${source.api_base_url}/transactions`,
        source.legacy_user_id,
        mirrorBootstrap ? null : source.transactions_etag,
      ),
    ]);
    // A changed transaction may refer to an unchanged contact. Fetch the small
    // contact list once without ETag so customer mapping remains complete.
    if (!transactionsFetch.notModified && contactsFetch.notModified) {
      contactsFetch = await fetchRows<LegacyContact>(
        `${source.api_base_url}/contacts`,
        source.legacy_user_id,
      );
    }
    const contactsRaw = contactsFetch.rows ?? [];
    const transactionsRaw = transactionsFetch.rows ?? [];
    const contacts = contactsRaw.filter((row) => Number(row.user_id) === Number(source!.legacy_user_id));
    const transactions = transactionsRaw.filter((row) => Number(row.user_id) === Number(source!.legacy_user_id));
    counters.fetched_contacts = contacts.length;
    counters.fetched_transactions = transactions.length;

    await Promise.all([
      mirrorRows(admin, "daftar_mirror_contacts", source.id, contacts),
      mirrorRows(admin, "daftar_mirror_transactions", source.id, transactions),
    ]);

    if (mirrorBootstrap) {
      const mirroredAt = new Date().toISOString();
      const { error: mirrorStateError } = await admin.from("daftar_sync_sources").update({
        mirror_bootstrapped_at: mirroredAt,
        mirror_last_full_at: mirroredAt,
      }).eq("id", source.id);
      if (mirrorStateError) throw mirrorStateError;
      source.mirror_bootstrapped_at = mirroredAt;
    }

    const contactMap = new Map(contacts.map((row) => [Number(row.id), row]));
    const newContacts = contacts
      .filter((row) => Number(row.id) > Number(source!.last_contact_id))
      .sort((a, b) => Number(a.id) - Number(b.id))
      .slice(0, 250);
    const delta = transactions
      .filter((row) => Number(row.id) > Number(source!.last_transaction_id))
      .sort((a, b) => Number(a.id) - Number(b.id))
      .slice(0, 500);

    const requiredContactIds = new Set<number>([
      ...newContacts.map((row) => Number(row.id)),
      ...delta.map((row) => Number(row.contact_id)),
    ]);
    const customerIds = new Map<number, string>();
    for (const contactId of requiredContactIds) {
      const contact = contactMap.get(contactId);
      if (!contact || !String(contact.name ?? "").trim()) throw new Error(`contact_missing:${contactId}`);
      const result = await ensureCustomer(admin, source, contact);
      customerIds.set(contactId, result.id);
      if (result.created) counters.new_customers++;
      if (result.reused) counters.reused_records++;
    }

    for (const transaction of delta.filter((row) => row.transaction_type === "LOAN")) {
      const sourceTransactionId = String(transaction.id);
      const customerId = customerIds.get(Number(transaction.contact_id));
      if (!customerId) throw new Error(`customer_mapping_missing:${transaction.contact_id}`);
      const transactionAmount = amount(transaction.amount);
      const occurredAt = transaction.transaction_date ?? transaction.created_at ?? new Date().toISOString();
      const currency = String(transaction.currency || "IQD");
      const payloadHash = await sha256Hex(JSON.stringify(transaction));

      if (transactionAmount === 0) {
        const { data: seenZero } = await admin.from("daftar_sync_seen")
          .select("target_id").eq("sync_source_id", source.id)
          .eq("entity_kind", "zero_event").eq("source_id", sourceTransactionId).maybeSingle();
        if (seenZero) {
          counters.reused_records++;
          continue;
        }
        const eventId = await stableUuid(`${source.admin_id}:zero_event:${sourceTransactionId}`);
        const { error } = await admin.from("financial_events").upsert({
          id: eventId,
          customer_id: customerId,
          event_type: "debt_created",
          actor_id: source.admin_id,
          actor_name: "Daftar Qarz Sync",
          actor_role: "admin",
          amount: 0,
          remaining: 0,
          currency,
          description: String(transaction.note ?? ""),
          metadata: {
            legacy_zero_amount: true,
            legacy_transaction_id: sourceTransactionId,
            legacy_contact_id: String(transaction.contact_id),
            source: "daftar_live_sync",
          },
          created_at: occurredAt,
        }, { onConflict: "id", ignoreDuplicates: true });
        if (error) throw error;
        await upsertSeen(admin, source.id, "zero_event", sourceTransactionId, eventId, payloadHash);
        counters.new_zero_events++;
        continue;
      }

      const { data: seenDebt } = await admin.from("daftar_sync_seen")
        .select("target_id").eq("sync_source_id", source.id)
        .eq("entity_kind", "debt").eq("source_id", sourceTransactionId).maybeSingle();
      if (seenDebt?.target_id) {
        counters.reused_records++;
        continue;
      }
      const legacyTarget = await findLegacyTarget(admin, source, "debt", sourceTransactionId);
      const debtId = legacyTarget ?? await stableUuid(`${source.admin_id}:debt:${sourceTransactionId}`);
      if (!legacyTarget) {
        const { error } = await admin.from("debts").upsert({
          id: debtId,
          customer_id: customerId,
          description: String(transaction.note ?? ""),
          amount: transactionAmount,
          remaining: transactionAmount,
          due_date: null,
          status: "pending",
          created_by: source.admin_id,
          currency,
          dollar_rate: 0,
          amount_usd: currency === "USD" ? transactionAmount : 0,
          items: [],
          custom_date: occurredAt,
          receipt_image_path: "",
          created_at: occurredAt,
          updated_at: occurredAt,
          subtotal: transactionAmount,
          discount_percent: 0,
          discount_amount: 0,
          reference_snapshot: {
            legacy_transaction_id: sourceTransactionId,
            legacy_contact_id: String(transaction.contact_id),
            legacy_transaction_type: "LOAN",
            source_created_at: transaction.created_at,
            source_updated_at: transaction.updated_at,
            source: "daftar_live_sync",
          },
        }, { onConflict: "id", ignoreDuplicates: true });
        if (error) throw error;
        counters.new_debts++;
      } else {
        counters.reused_records++;
      }
      await upsertSeen(admin, source.id, "debt", sourceTransactionId, debtId, payloadHash);
      await upsertLegacyLink(admin, source, "debt", sourceTransactionId, debtId);
    }

    const linkedSourceDebtIds = new Set(await sourceDebtIds(admin, source.id));
    for (const transaction of delta.filter((row) => row.transaction_type === "PAYMENT")) {
      const sourceTransactionId = String(transaction.id);
      const customerId = customerIds.get(Number(transaction.contact_id));
      if (!customerId) throw new Error(`customer_mapping_missing:${transaction.contact_id}`);
      const transactionAmount = amount(transaction.amount);
      const occurredAt = transaction.transaction_date ?? transaction.created_at ?? new Date().toISOString();
      const currency = String(transaction.currency || "IQD");
      const payloadHash = await sha256Hex(JSON.stringify(transaction));

      const { data: paymentMarker } = await admin.from("daftar_sync_seen")
        .select("source_id").eq("sync_source_id", source.id)
        .eq("entity_kind", "payment").eq("source_id", sourceTransactionId).maybeSingle();
      if (paymentMarker) {
        counters.reused_records++;
        continue;
      }

      if (transactionAmount === 0) {
        const eventId = await stableUuid(`${source.admin_id}:zero_event:${sourceTransactionId}`);
        const { error } = await admin.from("financial_events").upsert({
          id: eventId,
          customer_id: customerId,
          event_type: "payment_created",
          actor_id: source.admin_id,
          actor_name: "Daftar Qarz Sync",
          actor_role: "admin",
          amount: 0,
          remaining: 0,
          currency,
          description: String(transaction.note ?? ""),
          metadata: {
            legacy_zero_amount: true,
            legacy_transaction_id: sourceTransactionId,
            legacy_contact_id: String(transaction.contact_id),
            source: "daftar_live_sync",
          },
          created_at: occurredAt,
        }, { onConflict: "id", ignoreDuplicates: true });
        if (error) throw error;
        await upsertSeen(admin, source.id, "zero_event", sourceTransactionId, eventId, payloadHash);
        await upsertSeen(admin, source.id, "payment", sourceTransactionId, eventId, payloadHash);
        counters.new_zero_events++;
        continue;
      }

      const { data: existingAllocationLinks, error: allocationLinkError } = await admin.from("legacy_import_links")
        .select("source_id, target_id")
        .eq("admin_id", source.admin_id)
        .eq("entity_kind", "payment")
        .like("source_id", `${sourceTransactionId}:%`);
      if (allocationLinkError) throw allocationLinkError;
      const allocationIds = (existingAllocationLinks ?? []).map((row: { target_id: string }) => row.target_id);
      let alreadyAllocated = 0;
      if (allocationIds.length > 0) {
        const { data: existingPayments, error } = await admin.from("payments")
          .select("amount").in("id", allocationIds);
        if (error) throw error;
        alreadyAllocated = (existingPayments ?? []).reduce((sum: number, row: { amount: number }) => sum + amount(row.amount), 0);
      }
      let remaining = Math.round((transactionAmount - alreadyAllocated) * 100) / 100;
      let part = (existingAllocationLinks ?? []).reduce((max: number, row: { source_id: string }) => {
        const parsed = Number(String(row.source_id).split(":").pop());
        return Number.isFinite(parsed) ? Math.max(max, parsed) : max;
      }, 0);
      if (remaining < 0) throw new Error(`payment_allocation_conflict:${sourceTransactionId}`);

      const debts = await availableSourceDebts(admin, linkedSourceDebtIds, customerId, currency);
      for (const debt of debts) {
        if (remaining <= 0) break;
        const allocated = Math.min(remaining, amount(debt.remaining));
        if (allocated <= 0) continue;
        part++;
        const allocationSourceId = `${sourceTransactionId}:${part}`;
        const paymentId = await stableUuid(`${source.admin_id}:payment:${allocationSourceId}`);
        const { error } = await admin.rpc("legacy_import_apply_payment", {
          p_admin_id: source.admin_id,
          p_debt_id: debt.id,
          p_payment_id: paymentId,
          p_amount: allocated,
          p_note: String(transaction.note ?? ""),
          p_created_at: occurredAt,
        });
        if (error) throw error;
        const { error: snapshotError } = await admin.from("payments").update({
          reference_snapshot: {
            legacy_transaction_id: sourceTransactionId,
            legacy_contact_id: String(transaction.contact_id),
            legacy_transaction_type: "PAYMENT",
            allocation_part: part,
            original_payment_amount: transactionAmount,
            source_created_at: transaction.created_at,
            source_updated_at: transaction.updated_at,
            source: "daftar_live_sync",
          },
        }).eq("id", paymentId);
        if (snapshotError) throw snapshotError;
        await upsertSeen(admin, source.id, "payment_allocation", allocationSourceId, paymentId, payloadHash);
        await upsertLegacyLink(admin, source, "payment", allocationSourceId, paymentId);
        counters.new_payment_allocations++;
        remaining = Math.round((remaining - allocated) * 100) / 100;
      }
      if (remaining > 0) throw new Error(`unallocatable_payment:${sourceTransactionId}:${remaining}`);
      await upsertSeen(admin, source.id, "payment", sourceTransactionId, null, payloadHash);
    }

    const newContactCheckpoint = newContacts.length > 0
      ? Math.max(Number(source.last_contact_id), ...newContacts.map((row) => Number(row.id)))
      : Number(source.last_contact_id);
    const newTransactionCheckpoint = delta.length > 0
      ? Math.max(Number(source.last_transaction_id), ...delta.map((row) => Number(row.id)))
      : Number(source.last_transaction_id);
    const result = {
      ...counters,
      processed_contacts: newContacts.length,
      processed_transactions: delta.length,
      last_contact_id: newContactCheckpoint,
      last_transaction_id: newTransactionCheckpoint,
      mirror_bootstrapped: Boolean(source.mirror_bootstrapped_at),
      mirror_contacts: contacts.length,
      mirror_transactions: transactions.length,
    };

    const finishedAt = new Date().toISOString();
    await admin.from("daftar_sync_sources").update({
      last_contact_id: newContactCheckpoint,
      last_transaction_id: newTransactionCheckpoint,
      contacts_etag: contactsFetch.etag ?? source.contacts_etag ?? null,
      transactions_etag: transactionsFetch.etag ?? source.transactions_etag ?? null,
      lease_until: null,
      last_success_at: finishedAt,
      last_status: "success",
      last_error: null,
      last_result: result,
      consecutive_failures: 0,
      next_retry_at: null,
      circuit_open_until: null,
      last_heartbeat_at: finishedAt,
      last_duration_ms: Date.now() - startedAt,
      health_status: "healthy",
      updated_at: finishedAt,
    }).eq("id", source.id);
    if (runId) await admin.from("daftar_sync_runs").update({
      status: "success",
      ...counters,
      completed_at: finishedAt,
    }).eq("id", runId);
    return json({ ok: true, result });
  } catch (error) {
    console.error(error);
    const message = error instanceof Error
      ? error.message
      : String((error as { message?: unknown } | null)?.message ?? "internal_error");
    const finishedAt = new Date().toISOString();
    if (source) {
      const parts = message.split(":");
      const errorCode = parts.shift() || "sync_failed";
      const sourceEntityId = parts.length > 0 ? parts[0] : null;
      const { error: failureError } = await admin.rpc("record_daftar_sync_failure", {
        p_source_id: source.id,
        p_error_code: errorCode,
        p_error_detail: message,
        p_entity_kind: errorCode.includes("contact") || errorCode.includes("customer")
          ? "customer"
          : errorCode.includes("payment") ? "payment" : errorCode.includes("debt") ? "debt" : "sync",
        p_entity_source_id: sourceEntityId,
        p_payload: { counters, duration_ms: Date.now() - startedAt },
      });
      if (failureError) console.error("failure_record_failed", failureError);
    }
    if (runId) await admin.from("daftar_sync_runs").update({
      status: "failed",
      ...counters,
      error_message: message,
      completed_at: finishedAt,
    }).eq("id", runId);
    return json({ error: message }, 500);
  }
});
