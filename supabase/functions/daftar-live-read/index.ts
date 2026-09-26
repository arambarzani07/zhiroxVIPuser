import { createClient } from "npm:@supabase/supabase-js@2.116.0";
import { ensureDaftarFresh } from "../_shared/daftar_live_read/freshness.ts";
import { executeLocalRead } from "../_shared/daftar_live_read/local_read.ts";
import {
  handleDaftarLiveRead,
  type Viewer,
} from "../_shared/daftar_live_read/runtime.ts";
import { LiveReadError } from "../_shared/daftar_live_read/policy.ts";

function envJsonKey(name: string): string | null {
  const raw = Deno.env.get(name);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    const first = parsed.default ?? Object.values(parsed)[0];
    return typeof first === "string" ? first : null;
  } catch (_) {
    return raw;
  }
}

function resolveServiceCredential(): string {
  const value = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    envJsonKey("SUPABASE_SECRET_KEYS");
  if (!value) throw new Error("server_not_configured");
  return value;
}

function resolveAnonKey(): string {
  const value = Deno.env.get("SUPABASE_ANON_KEY") ??
    envJsonKey("SUPABASE_PUBLISHABLE_KEYS") ??
    envJsonKey("SUPABASE_ANON_KEYS");
  if (!value) throw new Error("server_not_configured");
  return value;
}

Deno.serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    if (!supabaseUrl) {
      return new Response(JSON.stringify({ error: "server_not_configured" }), {
        status: 500,
        headers: { "content-type": "application/json" },
      });
    }

    const serviceCredential = resolveServiceCredential();
    const anonKey = resolveAnonKey();
    const admin = createClient(supabaseUrl, serviceCredential, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    let userClient: any = null;
    let currentToken = "";

    return await handleDaftarLiveRead(req, {
      verifyUser: async (token) => {
        currentToken = token;
        const { data, error } = await admin.auth.getUser(token);
        if (error || !data.user) {
          throw new LiveReadError(
            { kind: "authentication" },
            "authentication_required",
          );
        }
        userClient = createClient(supabaseUrl, anonKey, {
          auth: { persistSession: false, autoRefreshToken: false },
          global: { headers: { Authorization: `Bearer ${currentToken}` } },
        });
        return { id: data.user.id };
      },

      loadViewer: async (userId): Promise<Viewer> => {
        const { data, error } = await admin
          .from("profiles")
          .select("id, role, admin_id, active, approved")
          .eq("id", userId)
          .single();
        if (error || !data) {
          throw new LiveReadError(
            { kind: "authorization" },
            "viewer_not_found",
          );
        }
        if (data.active === false || data.approved === false) {
          throw new LiveReadError(
            { kind: "authorization" },
            "viewer_inactive",
          );
        }
        const role = String(data.role);
        if (!["admin", "employee", "customer"].includes(role)) {
          throw new LiveReadError(
            { kind: "authorization" },
            "viewer_role_forbidden",
          );
        }
        const tenantId = role === "admin"
          ? String(data.id)
          : String(data.admin_id ?? "");
        if (!tenantId) {
          throw new LiveReadError(
            { kind: "authorization" },
            "tenant_not_found",
          );
        }
        return {
          id: String(data.id),
          role: role as Viewer["role"],
          tenantId,
        };
      },

      loadSource: async (tenantId) => {
        const { data, error } = await admin
          .from("daftar_sync_sources")
          .select(
            "id, admin_id, legacy_user_id, api_base_url, contacts_etag, transactions_etag, " +
              "live_read_mode, live_read_fallback_enabled, live_read_stale_after_seconds, " +
              "last_success_at, mirror_last_full_at, sync_mode, enabled, source_fingerprint",
          )
          .eq("admin_id", tenantId)
          .eq("enabled", true)
          .maybeSingle();
        if (error) throw new Error("source_lookup_failed");
        return data;
      },

      ensureFresh: async (source) =>
        await ensureDaftarFresh(
          {
            id: String(source.id),
            legacy_user_id: Number(source.legacy_user_id),
            api_base_url: String(source.api_base_url),
            contacts_etag: source.contacts_etag == null
              ? null
              : String(source.contacts_etag),
            transactions_etag: source.transactions_etag == null
              ? null
              : String(source.transactions_etag),
          },
          {
            fetcher: fetch,
            invokeWorker: async () => {
              const response = await fetch(
                `${supabaseUrl}/functions/v1/daftar-sync`,
                {
                  method: "POST",
                  headers: {
                    "content-type": "application/json",
                    authorization: `Bearer ${serviceCredential}`,
                  },
                  body: JSON.stringify({ source_id: source.id }),
                  signal: AbortSignal.timeout(120_000),
                },
              );
              if (!response.ok) {
                throw new LiveReadError(
                  { kind: "integrity" },
                  `normalization_http_${response.status}`,
                );
              }
              const payload = await response.json().catch(() => ({}));
              return { ok: payload?.ok !== false };
            },
            now: Date.now,
            sleep: (milliseconds) =>
              new Promise((resolve) => setTimeout(resolve, milliseconds)),
          },
        ),

      localRead: async (operation, params, viewer) => {
        if (!userClient || !currentToken) {
          throw new LiveReadError(
            { kind: "authentication" },
            "authentication_required",
          );
        }
        return await executeLocalRead(userClient, operation, params, viewer);
      },

      recordEvent: async (event) => {
        const { error } = await admin.from("daftar_live_read_events").insert(
          event,
        );
        if (error) throw new Error("telemetry_write_failed");
      },

      now: Date.now,
    });
  } catch (_) {
    return new Response(JSON.stringify({ error: "server_not_configured" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
});
