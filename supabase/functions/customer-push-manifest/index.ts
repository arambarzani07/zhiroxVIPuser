const TOKEN_PATTERN = /^[a-f0-9]{64}$/;

export function manifestResponse(request: Request): Response {
  const token = new URL(request.url).searchParams.get("token") ?? "";
  const startUrl = TOKEN_PATTERN.test(token)
    ? `/?token=${encodeURIComponent(token)}`
    : "/";

  return new Response(JSON.stringify({
    name: "ZHIROX Notifications",
    short_name: "ZHIROX",
    start_url: startUrl,
    scope: "/",
    display: "standalone",
    theme_color: "#ffffff",
    background_color: "#ffffff",
    lang: "ku",
    dir: "rtl",
  }), {
    status: 200,
    headers: {
      "Content-Type": "application/manifest+json; charset=utf-8",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

if (import.meta.main) Deno.serve(manifestResponse);
