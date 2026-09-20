import type { DaftarLiveReadOperation, ReadSource } from "./types.ts";
import {
  isFallbackEligible,
  isMirrorStale,
  LiveReadError,
  successEnvelope,
} from "./policy.ts";

export type Viewer = {
  id: string;
  role: "admin" | "employee" | "customer";
  tenantId: string;
};

export type RuntimeDeps = {
  verifyUser: (token: string) => Promise<{ id: string }>;
  loadViewer: (userId: string) => Promise<Viewer>;
  loadSource: (tenantId: string) => Promise<Record<string, any> | null>;
  ensureFresh: (source: Record<string, any>) => Promise<{
    liveStatus: number;
    liveLatencyMs: number;
    changed: boolean;
    validatedAt: string;
  }>;
  localRead: (
    operation: DaftarLiveReadOperation,
    params: Record<string, unknown>,
    viewer: Viewer,
  ) => Promise<unknown>;
  recordEvent: (event: Record<string, unknown>) => Promise<void>;
  now: () => number;
};

const OPERATIONS = new Set<DaftarLiveReadOperation>([
  "customer_directory",
  "customer_finance_snapshot",
  "customer_timeline",
  "customer_debts_page",
  "debt_detail",
  "debt_payments",
  "customer_all_debts",
  "admin_dashboard",
  "admin_all_debts",
  "employee_stats",
]);

const CUSTOMER_ID_OPERATIONS = new Set<DaftarLiveReadOperation>([
  "customer_finance_snapshot",
  "customer_timeline",
  "customer_debts_page",
  "customer_all_debts",
]);

function bearerToken(req: Request): string | null {
  const raw = req.headers.get("authorization") ?? "";
  const match = raw.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
    },
  });
}

function errorStatus(error: LiveReadError): number {
  if (error.failure.kind === "authentication") return 401;
  if (error.failure.kind === "authorization") return 403;
  if (error.failure.kind === "unsupported") return 400;
  return 502;
}

async function bestEffortEvent(
  deps: RuntimeDeps,
  event: Record<string, unknown>,
): Promise<void> {
  try {
    await deps.recordEvent(event);
  } catch (_) {
    // Telemetry must never break an otherwise valid read.
  }
}

function authorizeOperation(
  operation: DaftarLiveReadOperation,
  params: Record<string, unknown>,
  viewer: Viewer,
): void {
  if (
    viewer.role === "customer" &&
    CUSTOMER_ID_OPERATIONS.has(operation) &&
    String(params.customer_id ?? "") !== viewer.id
  ) {
    throw new LiveReadError({ kind: "authorization" }, "customer_scope_forbidden");
  }
  if (
    viewer.role === "customer" &&
    (operation === "customer_directory" ||
      operation === "admin_dashboard" ||
      operation === "admin_all_debts" ||
      operation === "employee_stats")
  ) {
    throw new LiveReadError({ kind: "authorization" }, "operation_forbidden");
  }
  if (
    operation === "admin_all_debts" &&
    String(params.admin_id ?? "") !== viewer.tenantId
  ) {
    throw new LiveReadError({ kind: "authorization" }, "wrong_tenant");
  }
}

export async function handleDaftarLiveRead(
  req: Request,
  deps: RuntimeDeps,
): Promise<Response> {
  if (req.method === "OPTIONS") return json({ ok: true });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const startedAt = deps.now();
  const token = bearerToken(req);
  if (!token) return json({ error: "authentication_required" }, 401);

  let viewer: Viewer;
  try {
    const user = await deps.verifyUser(token);
    viewer = await deps.loadViewer(user.id);
  } catch (error) {
    if (error instanceof LiveReadError) {
      return json({ error: error.message }, errorStatus(error));
    }
    return json({ error: "authentication_required" }, 401);
  }

  let body: Record<string, any>;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "invalid_request" }, 400);
  }

  const operation = String(body.operation ?? "") as DaftarLiveReadOperation;
  if (!OPERATIONS.has(operation)) {
    return json({ error: "unsupported_operation" }, 400);
  }
  const params = body.params && typeof body.params === "object" &&
      !Array.isArray(body.params)
    ? body.params as Record<string, unknown>
    : {};

  try {
    authorizeOperation(operation, params, viewer);
  } catch (error) {
    const liveError = error as LiveReadError;
    return json({ error: liveError.message }, errorStatus(liveError));
  }

  let source: Record<string, any> | null;
  try {
    source = await deps.loadSource(viewer.tenantId);
  } catch (_) {
    return json({ error: "source_lookup_failed" }, 503);
  }
  if (!source) return json({ error: "daftar_source_not_available" }, 404);
  if (Number(source.legacy_user_id) !== 28) {
    return json({ error: "daftar_source_not_available" }, 404);
  }

  const asOf = String(source.last_success_at ?? source.mirror_last_full_at ?? "") || null;
  const staleAfter = Number(source.live_read_stale_after_seconds ?? 300);
  const stale = isMirrorStale(asOf, staleAfter, deps.now());

  const materialize = async (
    resultSource: ReadSource,
    fallbackReason: string | null,
    liveStatus: number | null,
    liveLatencyMs: number | null,
    telemetryStatus?: string,
    detailCode?: string | null,
    responseSource?: ReadSource,
  ): Promise<Response> => {
    try {
      const data = await deps.localRead(operation, params, viewer);
      await bestEffortEvent(deps, {
        sync_source_id: source!.id,
        viewer_id: viewer.id,
        operation,
        result_source: resultSource,
        status: telemetryStatus ?? (fallbackReason ? "fallback" : "success"),
        fallback_reason: fallbackReason,
        detail_code: detailCode ?? null,
        live_status: liveStatus,
        live_latency_ms: liveLatencyMs,
        total_latency_ms: Math.max(0, deps.now() - startedAt),
        mirror_age_ms: resultSource === "mirror" && asOf
          ? Math.max(0, deps.now() - Date.parse(asOf))
          : null,
      });
      const envelopeSource = responseSource ?? resultSource;
      const responseAsOf = resultSource === "zhirox_primary"
        ? new Date(deps.now()).toISOString()
        : asOf;
      return json(successEnvelope({
        source: envelopeSource,
        asOf: responseAsOf,
        stale: resultSource === "mirror" ? stale : false,
        fallbackReason,
        data,
      }));
    } catch (_) {
      return json({ error: "local_read_failed" }, 500);
    }
  };

  const syncMode = String(source.sync_mode ?? "mirror");
  if (syncMode === "zhirox_primary") {
    // Keep the response source backward-compatible with already-installed
    // clients while telemetry records the actual ZHIROX-primary source.
    return await materialize(
      "zhirox_primary",
      null,
      null,
      null,
      undefined,
      null,
      "mirror",
    );
  }
  if (syncMode !== "mirror" || source.enabled === false) {
    return json({ error: "daftar_source_not_available" }, 503);
  }

  const liveReadMode = String(source.live_read_mode ?? "off");
  if (liveReadMode === "off") {
    return await materialize("mirror", null, null, null);
  }

  if (liveReadMode === "shadow") {
    try {
      const fresh = await deps.ensureFresh(source);
      return await materialize(
        "mirror",
        null,
        fresh.liveStatus,
        fresh.liveLatencyMs,
        "shadow_success",
      );
    } catch (error) {
      const detailCode = error instanceof LiveReadError
        ? error.message
        : "live_read_failed";
      const liveStatus = error instanceof LiveReadError &&
          error.failure.kind === "http"
        ? error.failure.status
        : null;
      return await materialize(
        "mirror",
        null,
        liveStatus,
        null,
        "shadow_failed",
        detailCode,
      );
    }
  }

  try {
    const fresh = await deps.ensureFresh(source);
    return await materialize(
      "live",
      null,
      fresh.liveStatus,
      fresh.liveLatencyMs,
    );
  } catch (error) {
    if (!(error instanceof LiveReadError)) {
      return json({ error: "live_read_failed" }, 502);
    }
    const fallbackEnabled = source.live_read_fallback_enabled !== false;
    if (fallbackEnabled && isFallbackEligible(error.failure)) {
      return await materialize("mirror", error.message, error.failure.kind === "http" ? error.failure.status : null, null);
    }
    await bestEffortEvent(deps, {
      sync_source_id: source.id,
      viewer_id: viewer.id,
      operation,
      result_source: "error",
      status: "failed",
      fallback_reason: null,
      detail_code: error.message,
      total_latency_ms: Math.max(0, deps.now() - startedAt),
    });
    return json({ error: error.message }, errorStatus(error));
  }
}
