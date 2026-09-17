const TOKEN_PATTERN = /^[a-f0-9]{64}$/;
export const CUSTOMER_PUSH_STATIC_URL = "https://raw.githack.com/arambarzani07/zhiroxVIPuser/9b18c1b51f4cc6af71df221d5a50cb6b3ed5f83b/customer-push-web/index.html";
export const CUSTOMER_PUSH_STATIC_SCOPE = new URL("./", CUSTOMER_PUSH_STATIC_URL).href;

export function manifestResponse(request: Request): Response {
  const token = new URL(request.url).searchParams.get("token") ?? "";
  const startUrl = TOKEN_PATTERN.test(token)
    ? `${CUSTOMER_PUSH_STATIC_URL}#token=${encodeURIComponent(token)}`
    : CUSTOMER_PUSH_STATIC_URL;

  return new Response(JSON.stringify({
    name: "ZHIROX Customer Portal",
    short_name: "ZHIROX",
    start_url: startUrl,
    scope: CUSTOMER_PUSH_STATIC_SCOPE,
    display: "standalone",
    theme_color: "#f4f6fa",
    background_color: "#f4f6fa",
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
