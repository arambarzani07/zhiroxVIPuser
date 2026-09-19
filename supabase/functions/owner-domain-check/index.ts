import { createClient } from "npm:@supabase/supabase-js@2.116.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeHost(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//i, "")
    .split("/")[0]
    .replace(/\.$/, "");
}

function validPublicHostname(value: string): boolean {
  if (
    !/^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(
      value,
    )
  ) return false;
  if (
    value === "localhost" ||
    value.endsWith(".local") ||
    value.endsWith(".internal")
  ) return false;
  return true;
}

async function checkDns(hostname: string, target: string) {
  try {
    const url =
      "https://dns.google/resolve?name=" +
      encodeURIComponent(hostname) +
      "&type=CNAME";
    const response = await fetch(url, {
      headers: { Accept: "application/dns-json" },
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) {
      return { status: "error", detail: "dns_lookup_failed" };
    }

    const body = await response.json();
    const answers = Array.isArray(body?.Answer) ? body.Answer : [];
    const cnames = answers
      .filter((row: any) => Number(row?.type) === 5)
      .map((row: any) => normalizeHost(row?.data))
      .filter(Boolean);

    if (cnames.includes(target)) {
      return { status: "verified", detail: "cname_verified" };
    }
    return {
      status: "mismatch",
      detail: cnames.length === 0 ? "cname_missing" : "cname_target_mismatch",
    };
  } catch (_) {
    return { status: "error", detail: "dns_lookup_error" };
  }
}

async function checkHttps(hostname: string) {
  const url = `https://${hostname}/`;
  try {
    let response = await fetch(url, {
      method: "HEAD",
      redirect: "manual",
      signal: AbortSignal.timeout(8000),
    });
    if (response.status === 405) {
      response = await fetch(url, {
        method: "GET",
        redirect: "manual",
        signal: AbortSignal.timeout(8000),
      });
    }
    return {
      status: "reachable",
      httpStatus: response.status,
      detail: "https_reachable",
    };
  } catch (_) {
    return {
      status: "unreachable",
      httpStatus: null,
      detail: "https_unreachable",
    };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const secret =
      envJsonKey("SUPABASE_SECRET_KEYS") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!anonKey || !secret) {
      return json({ error: "server_not_configured" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "authentication_required" }, 401);

    const service = createClient(url, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: requesterData, error: requesterError } =
      await service.auth.getUser(token);
    const requester = requesterData.user;
    if (requesterError || !requester) {
      return json({ error: "authentication_required" }, 401);
    }

    const { data: requesterProfile, error: profileError } = await service
      .from("profiles")
      .select("id,is_system_owner,active,approved")
      .eq("id", requester.id)
      .maybeSingle();

    if (profileError) return json({ error: profileError.message }, 400);
    if (
      !requesterProfile ||
      requesterProfile.is_system_owner !== true ||
      requesterProfile.active !== true ||
      requesterProfile.approved !== true
    ) {
      return json({ error: "system_owner_required" }, 403);
    }

    const body = await req.json();
    const adminId = String(body?.admin_id ?? "").trim();
    if (!adminId) return json({ error: "invalid_input" }, 400);

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: targetData, error: targetError } = await userClient.rpc(
      "get_system_owner_domain_check_target",
      { p_admin_id: adminId },
    );
    if (targetError) {
      return json({ error: targetError.message }, 400);
    }

    const hostname = normalizeHost(targetData?.hostname);
    const routingTarget = normalizeHost(targetData?.routing_target);

    if (
      !validPublicHostname(hostname) ||
      !validPublicHostname(routingTarget)
    ) {
      return json({ error: "invalid_domain_hostname" }, 400);
    }

    const [dns, https] = await Promise.all([
      checkDns(hostname, routingTarget),
      checkHttps(hostname),
    ]);

    const detail = [dns.detail, https.detail].filter(Boolean).join(";");

    const { data: record, error: recordError } = await service.rpc(
      "record_system_owner_domain_check",
      {
        p_actor_id: requester.id,
        p_admin_id: adminId,
        p_dns_status: dns.status,
        p_https_status: https.status,
        p_http_status: https.httpStatus,
        p_detail: detail,
      },
    );
    if (recordError) return json({ error: recordError.message }, 400);

    return json({
      ok: true,
      admin_id: adminId,
      hostname,
      routing_target: routingTarget,
      dns_status: dns.status,
      https_status: https.status,
      http_status: https.httpStatus,
      detail,
      recorded: record,
    });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
