const PORTAL_BASE_URL = "https://zhirox-push.netlify.app/";

const securityHeaders = {
  "Referrer-Policy": "no-referrer",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

function isToken(value: string): boolean {
  return /^[a-f0-9]{64}$/.test(value);
}

export function routeCustomerPushLink(req: Request): Response {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        ...securityHeaders,
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET,HEAD,OPTIONS",
      },
    });
  }

  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("method_not_allowed", {
      status: 405,
      headers: securityHeaders,
    });
  }

  const source = new URL(req.url);
  const destination = new URL(PORTAL_BASE_URL);
  const token = source.searchParams.get("token") ?? "";
  if (isToken(token)) destination.searchParams.set("token", token);

  return Response.redirect(destination, 307);
}

if (import.meta.main) Deno.serve(routeCustomerPushLink);
