const GATEWAY =
  "https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/daftar-credit-gateway";

function copyRequestHeaders(request) {
  const headers = new Headers();
  for (const name of [
    "authorization",
    "content-type",
    "accept",
    "accept-language",
    "user-agent",
    "if-none-match",
    "if-modified-since",
  ]) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }
  return headers;
}

export async function onRequest(context) {
  const request = context.request;
  const url = new URL(request.url);

  const prefix = "/xx";
  const originalPath = url.pathname.startsWith(prefix)
    ? url.pathname.slice(prefix.length)
    : url.pathname;

  const headers = copyRequestHeaders(request);
  headers.set("x-daftar-original-path", originalPath || "/");
  headers.set("x-daftar-original-query", url.search.slice(1));

  const method = request.method.toUpperCase();
  const init = {
    method,
    headers,
    redirect: "manual",
  };

  if (!["GET", "HEAD"].includes(method)) {
    init.body = await request.arrayBuffer();
  }

  let upstream;
  try {
    upstream = await fetch(GATEWAY, init);
  } catch (_) {
    return Response.json(
      {
        error: "zhirox_gateway_unavailable",
        message: "پشکنینی سنووری قەرز بەردەست نییە؛ مامەلە تۆمار نەکرا.",
      },
      { status: 503 },
    );
  }

  const responseHeaders = new Headers();
  for (const name of [
    "content-type",
    "etag",
    "cache-control",
    "last-modified",
    "content-disposition",
    "location",
    "x-zhirox-daftar-gateway",
  ]) {
    const value = upstream.headers.get(name);
    if (value) responseHeaders.set(name, value);
  }
  responseHeaders.set("x-zhirox-daftar-proxy", "pages-v1");

  // Daftar Qarz 0.2.7 handles a normal API envelope more safely than a
  // transport-level error. For credit-limit rejection only, keep the financial
  // block in the canonical gateway but return success=false to the original app
  // so it can show the message without creating an optimistic local transaction.
  if (
    upstream.status === 422 &&
    (upstream.headers.get("content-type") || "").includes("application/json")
  ) {
    const bodyText = await upstream.text();
    try {
      const payload = JSON.parse(bodyText);
      if (payload?.error === "credit_limit_exceeded") {
        responseHeaders.set("x-zhirox-daftar-compat", "credit-limit-message-v2");
        return Response.json(
          {
            success: false,
            error: "credit_limit_exceeded",
            message:
              "ئەم مامەڵەیە تۆمار نەکرا، چونکە لە سنووری قەرزی دیاری‌کراو زیاترە.",
            data: null,
            debt_limit: payload.debt_limit ?? null,
            current_balance: payload.current_balance ?? null,
            remaining_capacity: payload.remaining_capacity ?? null
          },
          { status: 200, headers: responseHeaders },
        );
      }
    } catch (_) {}

    return new Response(bodyText, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  }

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: responseHeaders,
  });
}
