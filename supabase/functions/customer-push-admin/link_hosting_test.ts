import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { routeCustomerPushLink } from "../customer-push-link/index.ts";

const token = "a".repeat(64);
const base = "https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push-link";

Deno.test("stable customer push gateway hosts the portal directly", async () => {
  const response = routeCustomerPushLink(
    new Request(`${base}?token=${token}`),
  );

  assertEquals(response.status, 200);
  assertEquals(response.headers.get("location"), null);
  assertEquals(response.headers.get("content-type")?.includes("text/html"), true);

  const html = await response.text();
  assertStringIncludes(html, "ZHIROX Customer Portal");
  assertStringIncludes(html, "/functions/v1/customer-push-link/styles.css");
  assertStringIncludes(html, "/functions/v1/customer-push-link/app.js");
});

Deno.test("stable customer push gateway serves PWA assets itself", async () => {
  const serviceWorker = routeCustomerPushLink(
    new Request(`${base}/sw.js`),
  );
  assertEquals(serviceWorker.status, 200);
  assertEquals(
    serviceWorker.headers.get("content-type")?.includes("application/javascript"),
    true,
  );
  assertStringIncludes(
    serviceWorker.headers.get("service-worker-allowed") ?? "",
    "/functions/v1/customer-push-link/",
  );

  const manifest = routeCustomerPushLink(
    new Request(`${base}/manifest.webmanifest?token=${token}`),
  );
  assertEquals(manifest.status, 200);
  assertEquals(
    manifest.headers.get("content-type")?.includes("application/manifest+json"),
    true,
  );
  const body = await manifest.json();
  assertEquals(body.scope, "/functions/v1/customer-push-link/");
  assertEquals(
    body.start_url,
    `/functions/v1/customer-push-link/?token=${token}`,
  );
});
