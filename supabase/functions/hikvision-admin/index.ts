import { createClient } from "npm:@supabase/supabase-js@2.116.0";

import { duplicateWindow, summarizeClips } from "./clip_integrity.mjs";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function env(name: string): string { return (Deno.env.get(name) ?? "").trim(); }
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
function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}
async function sha256Hex(value: string): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return Array.from(digest).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function cleanBase(raw: string): string { return raw.trim().replace(/\/+$/, ""); }
function isAllowedHikHost(raw: string): boolean {
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:") return false;
    const host = url.hostname.toLowerCase();
    return host === "hikcentralconnect.com" ||
      host.endsWith(".hikcentralconnect.com") ||
      host === "hikcentralconnectru.com" ||
      host.endsWith(".hikcentralconnectru.com");
  } catch (_) { return false; }
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
  const response = await fetch(`${cleanBase(root)}${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`hik_http_${response.status}`);
  const data = await response.json();
  if (!data || typeof data !== "object") throw new Error("hik_invalid_json");
  return data as Record<string, unknown>;
}

type CloudCreds = {
  server_address: string;
  app_key: string;
  secret_key: string;
  access_token?: string | null;
  token_expires_at?: string | null;
  area_domain?: string | null;
};

async function getCloudCreds(admin: any, marketId: string): Promise<CloudCreds> {
  const { data, error } = await admin.rpc("hikvision_cloud_credentials_get_service", { p_market_id: marketId });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] as Record<string, unknown> | undefined : undefined;
  if (!row?.server_address || !row?.app_key || !row?.secret_key) throw new Error("hikconnect_credentials_missing");
  return row as unknown as CloudCreds;
}

async function ensureCloudToken(admin: any, marketId: string): Promise<{ token: string; areaDomain: string }> {
  const creds = await getCloudCreds(admin, marketId);
  const expiry = creds.token_expires_at ? new Date(creds.token_expires_at).getTime() : 0;
  if (creds.access_token && creds.area_domain && expiry > Date.now() + 5 * 60 * 1000) {
    if (!isAllowedHikHost(creds.area_domain)) throw new Error("untrusted_cached_area_domain");
    return { token: creds.access_token, areaDomain: cleanBase(creds.area_domain) };
  }

  const login = await hikPost(creds.server_address, "/api/hccgw/platform/v1/token/get", null, {
    appKey: creds.app_key,
    secretKey: creds.secret_key,
  });
  if (String(login.errorCode ?? "") !== "0") throw new Error(`hik_token_${String(login.errorCode ?? "unknown")}`);
  const payload = (login.data ?? {}) as Record<string, unknown>;
  const token = String(payload.accessToken ?? "").trim();
  const areaDomain = cleanBase(String(payload.areaDomain ?? "").trim());
  if (!token || !isAllowedHikHost(areaDomain)) throw new Error("hik_token_response_invalid");
  const rawExpiry = Number(payload.expireTime ?? 0);
  const expiryMs = rawExpiry > 10_000_000_000 ? rawExpiry : rawExpiry * 1000;
  const expiresAt = Number.isFinite(expiryMs) && expiryMs > Date.now()
    ? new Date(expiryMs)
    : new Date(Date.now() + 6 * 24 * 60 * 60 * 1000);
  const { data, error } = await admin.rpc("hikvision_cloud_token_cache_service", {
    p_market_id: marketId,
    p_access_token: token,
    p_expires_at: expiresAt.toISOString(),
    p_area_domain: areaDomain,
  });
  if (error || data !== true) throw error ?? new Error("token_cache_failed");
  return { token, areaDomain };
}

async function listCloudCameras(admin: any, marketId: string): Promise<Record<string, unknown>[]> {
  const session = await ensureCloudToken(admin, marketId);
  const result = await hikPost(
    session.areaDomain,
    "/api/hccgw/resource/v1/devices/get",
    session.token,
    { pageIndex: 1, pageSize: 500, deviceCategory: "encodingDevice" },
  );
  if (String(result.errorCode ?? "") !== "0") {
    throw new Error(`hik_devices_${String(result.errorCode ?? "unknown")}`);
  }
  const payload = (result.data ?? {}) as Record<string, unknown>;
  const devices = Array.isArray(payload.device) ? payload.device : [];
  const byId = new Map<string, Record<string, unknown>>();
  for (let index = 0; index < devices.length; index++) {
    const device = (devices[index] ?? {}) as Record<string, unknown>;
    const serialNo = String(device.serialNo ?? "").trim();
    if (!serialNo) continue;
    const detail = await hikPost(
      session.areaDomain,
      "/api/hccgw/resource/v1/devicedetail/get",
      session.token,
      { deviceSerialNo: serialNo },
    );
    if (String(detail.errorCode ?? "") !== "0") continue;
    const detailData = (detail.data ?? {}) as Record<string, unknown>;
    const detailDevice = (detailData.device ?? {}) as Record<string, unknown>;
    const baseInfo = (detailDevice.baseInfo ?? {}) as Record<string, unknown>;
    const channels = Array.isArray(detailDevice.cameraChannel)
      ? detailDevice.cameraChannel
      : [];
    for (const entry of channels) {
      const channel = (entry ?? {}) as Record<string, unknown>;
      const id = String(channel.id ?? "").trim();
      const channelNo = Number(channel.no ?? 0);
      if (!id || !Number.isFinite(channelNo) || channelNo < 1) continue;
      byId.set(id, {
        id,
        name: String(channel.name ?? ""),
        online: String(channel.online ?? "0") === "1",
        device_serial: String(baseInfo.serialNo ?? serialNo),
        channel_no: Math.trunc(channelNo),
      });
    }
    if (index + 1 < devices.length) {
      await new Promise((resolve) => setTimeout(resolve, 220));
    }
  }
  return [...byId.values()];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const url = env("SUPABASE_URL");
  const key = serviceKey();
  if (!url || !key) return json({ error: "server_not_configured" }, 500);
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : "";
  if (!bearer) return json({ error: "authentication_required" }, 401);
  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(bearer);
  const user = authData.user;
  if (authError || !user) return json({ error: "authentication_required" }, 401);
  const { data: profile, error: profileError } = await admin.from("profiles").select("id, role, active, approved, market_name").eq("id", user.id).maybeSingle();
  if (profileError || !profile || profile.role !== "admin" || profile.active !== true || profile.approved !== true) return json({ error: "admin_required" }, 403);
  const marketId = user.id;
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { return json({ error: "invalid_json" }, 400); }
  const action = String(body.action ?? "status").trim();

  try {
    if (action === "status") {
      const [{ data: config, error: configError }, { data: statusRows, error: statusError }, { data: cloudRows, error: cloudError }] = await Promise.all([
        admin.from("hikvision_market_config").select("enabled,auto_capture,nvr_label,nvr_host,nvr_model,nvr_firmware,cashier_channel_id,pre_seconds,post_seconds,timezone,retention_days,capture_provider,hikconnect_camera_id,hikconnect_camera_name,hikconnect_device_serial,hikconnect_server_address,updated_at").eq("market_id", marketId).maybeSingle(),
        admin.rpc("hikvision_gateway_status_service", { p_market_id: marketId }),
        admin.rpc("hikvision_cloud_status_service", { p_market_id: marketId }),
      ]);
      if (configError) throw configError;
      if (statusError) throw statusError;
      if (cloudError) throw cloudError;
      const gateway = Array.isArray(statusRows) && statusRows.length > 0 ? statusRows[0] : null;
      const cloud = Array.isArray(cloudRows) && cloudRows.length > 0 ? cloudRows[0] : { configured: false };
      const { data: clips, error: integrityError } = await admin.from("transaction_video_evidence")
        .select("id,market_id,status,content_sha256,channel_id,clip_start_at,clip_end_at,captured_at,playback_metadata")
        .eq("market_id", marketId).eq("status", "ready").order("captured_at", { ascending: false }).limit(200);
      const integrity = integrityError ? { available: false } : { available: true, ...summarizeClips(clips ?? []) };
      return json({ ok: true, market_name: profile.market_name, config, gateway, cloud, integrity });
    }

    if (action === "save_cloud_credentials") {
      const serverAddress = cleanBase(String(body.server_address ?? ""));
      const appKey = String(body.app_key ?? "").trim();
      const secretKey = String(body.secret_key ?? "").trim();
      if (!isAllowedHikHost(serverAddress) || appKey.length < 8 || secretKey.length < 8) return json({ error: "invalid_cloud_credentials" }, 400);
      const { data, error } = await admin.rpc("hikvision_cloud_credentials_set_service", { p_market_id: marketId, p_server_address: serverAddress, p_app_key: appKey, p_secret_key: secretKey });
      if (error || data !== true) throw error ?? new Error("credential_store_failed");
      try {
        const session = await ensureCloudToken(admin, marketId);
        return json({ ok: true, connected: true, area_domain: session.areaDomain });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await admin.rpc("hikvision_cloud_mark_error_service", { p_market_id: marketId, p_error: message.slice(0, 500) });
        return json({ error: "hikconnect_auth_failed" }, 422);
      }
    }

    if (action === "cloud_cameras") {
      const cameras = await listCloudCameras(admin, marketId);
      cameras.sort((a, b) => Number(a.channel_no ?? 9999) - Number(b.channel_no ?? 9999) || String(a.name).localeCompare(String(b.name)));
      return json({ ok: true, cameras });
    }

    if (action === "select_cloud_camera") {
      const cameraId = String(body.camera_id ?? "").trim();
      if (cameraId.length < 8 || cameraId.length > 128) return json({ error: "invalid_camera_id" }, 400);
      const cameras = await listCloudCameras(admin, marketId);
      const camera = cameras.find((item) => String(item.id) === cameraId);
      if (!camera) return json({ error: "camera_not_found" }, 404);
      const channelNo = Math.trunc(Number(camera.channel_no ?? 0));
      if (channelNo < 1 || channelNo > 256) return json({ error: "invalid_camera_channel" }, 409);
      const { data, error } = await admin.rpc("hikvision_cloud_activate_camera_service", { p_market_id: marketId, p_camera_id: cameraId, p_camera_name: String(camera.name ?? ""), p_device_serial: String(camera.device_serial ?? ""), p_channel_no: channelNo });
      if (error || data !== true) throw error ?? new Error("camera_activation_failed");
      return json({ ok: true, camera, provider: "hikconnect_cloud" });
    }

    if (action === "use_local_gateway") {
      const { data, error } = await admin.rpc("hikvision_use_local_gateway_service", { p_market_id: marketId });
      if (error || data !== true) throw error ?? new Error("provider_update_failed");
      return json({ ok: true, provider: "local_gateway" });
    }

    if (action === "issue_gateway_token") {
      const random = new Uint8Array(32);
      crypto.getRandomValues(random);
      const token = `zg_${base64Url(random)}`;
      const hash = await sha256Hex(token);
      const { data, error } = await admin.rpc("hikvision_gateway_rotate_token_service", { p_market_id: marketId, p_token_sha256: hash });
      if (error) throw error;
      const row = Array.isArray(data) && data.length > 0 ? data[0] : null;
      if (!row) return json({ error: "gateway_not_registered" }, 409);
      return json({ ok: true, gateway_id: row.gateway_id, gateway_token: token });
    }

    if (action === "update_config") {
      const channel = Math.trunc(Number(body.cashier_channel_id ?? 1));
      const pre = Math.trunc(Number(body.pre_seconds ?? 15));
      const post = Math.trunc(Number(body.post_seconds ?? 30));
      const retention = Math.trunc(Number(body.retention_days ?? 90));
      if (channel < 1 || channel > 256 || pre < 0 || pre > 300 || post < 1 || post > 600 || retention < 1 || retention > 3650) return json({ error: "invalid_config" }, 400);
      const update = { enabled: body.enabled !== false, auto_capture: body.auto_capture !== false, cashier_channel_id: channel, pre_seconds: pre, post_seconds: post, retention_days: retention, updated_at: new Date().toISOString() };
      const { data, error } = await admin.from("hikvision_market_config").update(update).eq("market_id", marketId).select("enabled,auto_capture,cashier_channel_id,pre_seconds,post_seconds,retention_days,updated_at").single();
      if (error) throw error;
      return json({ ok: true, config: data });
    }

    if (action === "video_url" || action === "video_status" || action === "rebuild_video") {
      const sourceType = String(body.source_type ?? "").trim();
      const sourceId = String(body.source_id ?? "").trim();
      if (!["debt", "payment", "general_payment"].includes(sourceType) || !/^[0-9a-f-]{36}$/i.test(sourceId)) return json({ error: "invalid_transaction" }, 400);
      if (action === "rebuild_video") {
        const { data, error } = await admin.rpc("hikvision_video_rebuild_service", {p_market_id:marketId,p_source_type:sourceType,p_source_id:sourceId});
        if (error) throw error;
        return json(data?.ok ? data : {error:data?.reason ?? "rebuild_failed"},data?.ok ? 200 : 409);
      }
      const { data: evidence, error } = await admin.from("transaction_video_evidence").select("id,market_id,status,content_sha256,object_path,channel_id,transaction_at,clip_start_at,clip_end_at,captured_at,playback_metadata").eq("market_id", marketId).eq("source_type", sourceType).eq("source_id", sourceId).maybeSingle();
      if (error) throw error;
      if (!evidence) return action === "video_status" ? json({ ok: true, evidence: null }) : json({ error: "video_not_found" }, 404);
      let integrity: Record<string, unknown> = { checked: false, duplicate_warning: false };
      if (evidence.status === "ready" && evidence.content_sha256 && evidence.clip_start_at && evidence.clip_end_at) {
        const { data: matches, error: matchError } = await admin.from("transaction_video_evidence")
          .select("id,market_id,status,content_sha256,channel_id,clip_start_at,clip_end_at")
          .eq("market_id", marketId).eq("channel_id", evidence.channel_id).eq("status", "ready")
          .eq("content_sha256", evidence.content_sha256).neq("id", evidence.id)
          .or(`clip_end_at.lte.${evidence.clip_start_at},clip_start_at.gte.${evidence.clip_end_at}`).limit(1);
        integrity = { checked: !matchError, duplicate_warning: !matchError && (matches ?? []).some((other) => duplicateWindow(evidence, other)) };
      }
      // Internal identifiers and file hashes are not needed by the client.
      const { id: _id, market_id: _market, content_sha256: _hash, ...publicFields } = evidence;
      const publicEvidence: Record<string, unknown> = { ...publicFields };
      publicEvidence.integrity = integrity;
      const { data: rebuild, error: rebuildError } = await admin.rpc("hikvision_video_rebuild_status_service", {p_market_id:marketId,p_source_type:sourceType,p_source_id:sourceId});
      publicEvidence.can_rebuild = !rebuildError && rebuild?.can_rebuild === true;
      publicEvidence.rebuild = rebuildError ? null : rebuild;
      if (action === "video_status") return json({ ok: true, evidence: publicEvidence });
      if (evidence.status !== "ready" || !evidence.object_path) return json({ ok: true, ready: false, evidence: publicEvidence });
      const { data: signed, error: signedError } = await admin.storage.from("transaction-camera-clips").createSignedUrl(evidence.object_path, 600);
      if (signedError || !signed?.signedUrl) throw signedError ?? new Error("signed_read_failed");
      return json({ ok: true, ready: true, signed_url: signed.signedUrl, expires_in: 600, evidence: publicEvidence });
    }

    return json({ error: "unsupported_action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("hikvision-admin", action, message.slice(0, 300));
    return json({ error: "hikvision_admin_failed" }, 500);
  }
});
