const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve((req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST" && req.method !== "GET") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // A OneSignal App ID is intentionally public and is embedded in normal
  // mobile/web clients. Never expose the REST API key from this endpoint.
  const appId = (Deno.env.get("ONESIGNAL_APP_ID") ?? "").trim();
  if (!appId) {
    return json({ configured: false, app_id: null }, 503);
  }

  return json({ configured: true, app_id: appId });
});
