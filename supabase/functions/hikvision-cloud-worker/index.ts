import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-zhirox-hikvision-cloud-worker",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
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
    } catch (_) {}
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

async function sha256Hex(value: string | Uint8Array): Promise<string> {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  const source = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", source));
  return Array.from(digest).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function isAllowedHikHost(raw: string): boolean {
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:") return false;
    const host = url.hostname.toLowerCase();
    return host === "hikcentralconnect.com" ||
      host.endsWith(".hikcentralconnect.com") ||
      host === "hikcentralconnectru.com" ||
      host.endsWith(".hikcentralconnectru.com");
  } catch (_) {
    return false;
  }
}

function base(raw: string): string {
  return raw.trim().replace(/\/+$/, "");
}

function baghdadTime(iso: string): string {
  const date = new Date(iso);
  if (!Number.isFinite(date.getTime())) throw new Error("invalid_clip_time");
  const shifted = new Date(date.getTime() + 3 * 60 * 60 * 1000);
  const two = (n: number) => String(n).padStart(2, "0");
  return `${shifted.getUTCFullYear()}-${two(shifted.getUTCMonth() + 1)}-${two(shifted.getUTCDate())}` +
    `T${two(shifted.getUTCHours())}:${two(shifted.getUTCMinutes())}:${two(shifted.getUTCSeconds())}+03:00`;
}

async function hikPost(
  root: string,
  path: string,
  token: string | null,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (!isAllowedHikHost(root)) throw new Error("untrusted_hikconnect_host");
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Token = token;
  const response = await fetch(`${base(root)}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`hik_http_${response.status}`);
  const data = await response.json();
  if (!data || typeof data !== "object") throw new Error("hik_invalid_json");
  return data as Record<string, unknown>;
}

type Creds = {
  server_address: string;
  app_key: string;
  secret_key: string;
  access_token?: string | null;
  token_expires_at?: string | null;
  area_domain?: string | null;
};

async function getCreds(admin: any, marketId: string): Promise<Creds> {
  const { data, error } = await admin.rpc("hikvision_cloud_credentials_get_service", { p_market_id: marketId });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] as Record<string, unknown> | undefined : undefined;
  if (!row?.server_address || !row?.app_key || !row?.secret_key) throw new Error("hikconnect_credentials_missing");
  return row as unknown as Creds;
}

async function ensureToken(
  admin: any,
  marketId: string,
  creds: Creds,
): Promise<{ token: string; areaDomain: string }> {
  const cachedExpiry = creds.token_expires_at ? new Date(creds.token_expires_at).getTime() : 0;
  if (creds.access_token && creds.area_domain && cachedExpiry > Date.now() + 5 * 60 * 1000) {
    if (!isAllowedHikHost(creds.area_domain)) throw new Error("untrusted_cached_area_domain");
    return { token: creds.access_token, areaDomain: base(creds.area_domain) };
  }

  const result = await hikPost(creds.server_address, "/api/hccgw/platform/v1/token/get", null, {
    appKey: creds.app_key,
    secretKey: creds.secret_key,
  });
  if (String(result.errorCode ?? "") !== "0") {
    throw new Error(`hik_token_${String(result.errorCode ?? "unknown")}`);
  }
  const payload = (result.data ?? {}) as Record<string, unknown>;
  const token = String(payload.accessToken ?? "").trim();
  const areaDomain = base(String(payload.areaDomain ?? "").trim());
  if (!token || !isAllowedHikHost(areaDomain)) throw new Error("hik_token_response_invalid");

  const rawExpiry = Number(payload.expireTime ?? 0);
  const expiryMs = rawExpiry > 10_000_000_000 ? rawExpiry : rawExpiry * 1000;
  const expiry = Number.isFinite(expiryMs) && expiryMs > Date.now()
    ? new Date(expiryMs)
    : new Date(Date.now() + 6 * 24 * 60 * 60 * 1000);

  const { data: cached, error } = await admin.rpc("hikvision_cloud_token_cache_service", {
    p_market_id: marketId,
    p_access_token: token,
    p_expires_at: expiry.toISOString(),
    p_area_domain: areaDomain,
  });
  if (error || cached !== true) throw error ?? new Error("token_cache_failed");
  return { token, areaDomain };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = env("SUPABASE_URL");
  const key = serviceKey();
  if (!url || !key) return json({ error: "server_not_configured" }, 500);

  const secret = (req.headers.get("x-zhirox-hikvision-cloud-worker") ?? "").trim();
  if (secret.length < 32 || secret.length > 256) return json({ error: "unauthorized" }, 401);

  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const secretHash = await sha256Hex(secret);
  const { data: allowed, error: authError } = await admin.rpc("hikvision_cloud_worker_auth_service", {
    p_token_sha256: secretHash,
  });
  if (authError || allowed !== true) return json({ error: "unauthorized" }, 401);

  const { data: claimRows, error: claimError } = await admin.rpc("hikvision_cloud_claim_service");
  if (claimError) return json({ error: "claim_failed" }, 500);
  const job = Array.isArray(claimRows) ? claimRows[0] as Record<string, unknown> | undefined : undefined;
  if (!job?.job_id) return json({ ok: true, processed: 0 });

  const jobId = String(job.job_id);
  const marketId = String(job.market_id);
  const attemptToken = String(job.attempt_token);

  try {
    const creds = await getCreds(admin, marketId);
    const session = await ensureToken(admin, marketId, creds);

    if (String(job.stage) === "save") {
      const save = await hikPost(session.areaDomain, "/api/hccgw/video/v1/video/save", session.token, {
        cameraId: String(job.camera_id),
        beginTime: baghdadTime(String(job.clip_start_at)),
        endTime: baghdadTime(String(job.clip_end_at)),
        voiceSwitch: 2,
      });
      if (String(save.errorCode ?? "") !== "0") {
        throw new Error(`hik_video_save_${String(save.errorCode ?? "unknown")}`);
      }
      const payload = (save.data ?? {}) as Record<string, unknown>;
      const taskId = String(payload.taskId ?? "").trim();
      if (!taskId) throw new Error("hik_video_task_missing");
      const { data, error } = await admin.rpc("hikvision_cloud_task_started_service", {
        p_job_id: jobId,
        p_attempt_token: attemptToken,
        p_task_id: taskId,
      });
      if (error || data !== true) throw error ?? new Error("task_state_rejected");
      return json({ ok: true, processed: 1, stage: "save" });
    }

    const taskId = String(job.cloud_task_id ?? "").trim();
    if (!taskId) throw new Error("cloud_task_missing");
    const poll = await hikPost(session.areaDomain, "/api/hccgw/video/v1/video/download/url", session.token, {
      taskId,
    });
    if (String(poll.errorCode ?? "") !== "0") {
      throw new Error(`hik_video_poll_${String(poll.errorCode ?? "unknown")}`);
    }
    const payload = (poll.data ?? {}) as Record<string, unknown>;
    const status = Number(payload.status);

    if (status === 1) {
      const { data, error } = await admin.rpc("hikvision_cloud_wait_service", {
        p_job_id: jobId,
        p_attempt_token: attemptToken,
        p_seconds: 20,
      });
      if (error || data !== true) throw error ?? new Error("wait_state_rejected");
      return json({ ok: true, processed: 1, stage: "poll", cloud_status: "uploading" });
    }

    const urls = Array.isArray(payload.urls) ? payload.urls.map(String) : [];
    if (status !== 0 || urls.length === 0) {
      throw new Error(`hik_video_status_${Number.isFinite(status) ? status : "unknown"}`);
    }

    const downloadUrl = urls[0];
    let parsedDownload: URL;
    try { parsedDownload = new URL(downloadUrl); } catch (_) { throw new Error("invalid_download_url"); }
    if (parsedDownload.protocol !== "https:") throw new Error("unsafe_download_url");

    const download = await fetch(downloadUrl, { redirect: "follow" });
    if (!download.ok) throw new Error(`download_http_${download.status}`);
    const declaredSize = Number(download.headers.get("content-length") ?? 0);
    if (declaredSize > 100 * 1024 * 1024) throw new Error("clip_too_large");
    const bytes = new Uint8Array(await download.arrayBuffer());
    if (bytes.byteLength === 0 || bytes.byteLength > 100 * 1024 * 1024) throw new Error("invalid_clip_size");

    const start = new Date(String(job.clip_start_at));
    const end = new Date(String(job.clip_end_at));
    const yyyy = String(start.getUTCFullYear());
    const mm = String(start.getUTCMonth() + 1).padStart(2, "0");
    const dd = String(start.getUTCDate()).padStart(2, "0");
    const objectPath = `${marketId}/${yyyy}/${mm}/${dd}/cloud/${String(job.source_type)}/${String(job.source_id)}-${jobId}.mp4`;

    const { error: uploadError } = await admin.storage
      .from("transaction-camera-clips")
      .upload(objectPath, bytes, { contentType: "video/mp4", upsert: true, cacheControl: "3600" });
    if (uploadError) throw uploadError;

    const digest = await sha256Hex(bytes);
    const duration = Math.max(0, Math.round((end.getTime() - start.getTime()) / 1000));
    const { data: completed, error: completeError } = await admin.rpc("hikvision_cloud_complete_service", {
      p_job_id: jobId,
      p_attempt_token: attemptToken,
      p_object_path: objectPath,
      p_content_sha256: digest,
      p_byte_size: bytes.byteLength,
      p_duration_seconds: duration,
      p_metadata: {
        provider: "hikconnect_cloud",
        cloud_task_id: taskId,
        hikconnect_expire_time: payload.expireTime ?? null,
      },
    });
    if (completeError || completed !== true) throw completeError ?? new Error("complete_state_rejected");
    return json({ ok: true, processed: 1, stage: "complete" });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("hikvision-cloud-worker", message.slice(0, 240));
    await admin.rpc("hikvision_cloud_mark_error_service", {
      p_market_id: marketId,
      p_error: message.slice(0, 500),
    });
    await admin.rpc("hikvision_cloud_fail_service", {
      p_job_id: jobId,
      p_attempt_token: attemptToken,
      p_error: message.slice(0, 1000),
      p_missing: false,
    });
    return json({ ok: false, processed: 1, error: "cloud_job_failed" }, 500);
  }
});
