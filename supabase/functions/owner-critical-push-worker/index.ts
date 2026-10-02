import { createClient } from "npm:@supabase/supabase-js@2.116.0";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function env(name: string): string {
  return (Deno.env.get(name) ?? "").trim();
}

function serviceKey(): string {
  const modern = env("SUPABASE_SECRET_KEYS");
  if (modern) {
    try {
      const parsed = JSON.parse(modern) as Record<string, string>;
      const value = parsed.default ?? Object.values(parsed)[0];
      if (value) return String(value).trim();
    } catch (_) {
      return modern;
    }
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

async function secureEqual(left: string, right: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [aHash, bHash] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(left)),
    crypto.subtle.digest("SHA-256", encoder.encode(right)),
  ]);
  const a = new Uint8Array(aHash);
  const b = new Uint8Array(bHash);
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

async function loadRuntime(admin: any): Promise<{ appId: string; apiKey: string; workerSecret: string }> {
  let appId = env("ONESIGNAL_APP_ID");
  let apiKey = env("ONESIGNAL_REST_API_KEY");

  if (!appId || !apiKey) {
    const { data, error } = await admin.rpc("get_onesignal_runtime_config_service");
    if (!error) {
      const row = Array.isArray(data) ? data[0] : data;
      appId ||= String(row?.app_id ?? "").trim();
      apiKey ||= String(row?.rest_api_key ?? "").trim();
    }
  }

  const { data: pushConfig, error: pushError } = await admin.rpc("get_customer_push_runtime_config_service");
  if (pushError) throw pushError;
  const workerSecret = String(pushConfig?.customer_push_worker_secret ?? "").trim();
  return { appId, apiKey, workerSecret };
}

function errorText(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).slice(0, 500);
}

async function finish(admin: any, alertId: string, success: boolean, providerMessageId?: string, error?: string) {
  const { error: finishError } = await admin.rpc("finish_owner_critical_push_service", {
    p_alert_id: alertId,
    p_success: success,
    p_provider_message_id: providerMessageId ?? null,
    p_error: error ?? null,
  });
  if (finishError) throw finishError;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = env("SUPABASE_URL");
  const secret = serviceKey();
  if (!supabaseUrl || !secret) return json({ error: "server_not_configured" }, 500);

  const admin = createClient(supabaseUrl, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let runtime;
  try {
    runtime = await loadRuntime(admin);
  } catch (error) {
    console.error("Owner critical push runtime load failed", errorText(error));
    return json({ error: "server_not_configured" }, 500);
  }

  const provided = req.headers.get("x-zhirox-push-worker") ?? "";
  if (!provided || !runtime.workerSecret || !(await secureEqual(provided, runtime.workerSecret))) {
    return json({ error: "unauthorized" }, 401);
  }

  if (!runtime.appId || !runtime.apiKey) {
    return json({ error: "onesignal_not_configured" }, 503);
  }

  const { data: claimed, error: claimError } = await admin.rpc("claim_owner_critical_push_service", {
    p_limit: 20,
  });
  if (claimError) {
    console.error("Owner critical push claim failed", claimError.message);
    return json({ error: "claim_failed" }, 500);
  }

  let sent = 0;
  let deferred = 0;

  for (const row of claimed ?? []) {
    const alertId = String(row.alert_id ?? "");
    const recipientUserId = String(row.recipient_user_id ?? "");
    const title = String(row.title ?? "ZHIROX Alert").slice(0, 120);
    const body = String(row.body ?? "").slice(0, 1000);
    const eventType = String(row.event_type ?? "owner_autopilot_critical");
    const data = row.data && typeof row.data === "object" && !Array.isArray(row.data)
      ? row.data as Record<string, unknown>
      : {};

    try {
      const response = await fetch("https://api.onesignal.com/notifications", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Key ${runtime.apiKey}`,
        },
        body: JSON.stringify({
          app_id: runtime.appId,
          target_channel: "push",
          include_aliases: { external_id: [recipientUserId] },
          headings: { en: title },
          contents: { en: body },
          data: {
            ...data,
            type: eventType,
            zhirox_target_user_id: recipientUserId,
            zhirox_route: "owner_critical_alerts",
            alert_id: alertId,
          },
          idempotency_key: alertId,
        }),
      });

      let provider: Record<string, unknown> = {};
      try { provider = await response.json(); } catch (_) {}
      const messageId = typeof provider.id === "string" ? provider.id.trim() : "";

      if (response.ok && messageId) {
        await finish(admin, alertId, true, messageId);
        sent++;
      } else {
        const reason = response.ok
          ? "no_active_subscription"
          : `provider_${response.status}:${JSON.stringify(provider).slice(0, 350)}`;
        await finish(admin, alertId, false, undefined, reason);
        deferred++;
      }
    } catch (error) {
      try {
        await finish(admin, alertId, false, undefined, errorText(error));
      } catch (finishError) {
        console.error("Owner critical push finish failed", alertId, errorText(finishError));
      }
      deferred++;
    }
  }

  return json({ ok: true, claimed: (claimed ?? []).length, sent, deferred });
});
