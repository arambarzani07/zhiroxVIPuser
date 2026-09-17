import { assertEquals } from "jsr:@std/assert@1";
import {
  CUSTOMER_PUSH_STATIC_URL,
  routeCustomerPushLink,
} from "../customer-push-link/index.ts";
import { manifestResponse } from "../customer-push-manifest/index.ts";

const token = "a".repeat(64);
const publicBase = "https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push-link";
const runtimeBase = "https://hsoyfbtpvwfmjokudznx.supabase.co/customer-push-link";
function expectRedirect(url: string, expected: string) {
  const response = routeCustomerPushLink(new Request(url));
  assertEquals(response.status, 307);
  assertEquals(response.headers.get("location"), expected);
}

Deno.test("stable customer push gateway keeps bearer token out of the static host request", () => {
  assertEquals(new URL(CUSTOMER_PUSH_STATIC_URL).search, "");
  for (const base of [publicBase, runtimeBase]) {
    expectRedirect(
      `${base}?token=${token}`,
      `${CUSTOMER_PUSH_STATIC_URL}#token=${token}`,
    );
  }
});

Deno.test("stable customer push gateway preserves a token-free portal entry", () => {
  expectRedirect(publicBase, CUSTOMER_PUSH_STATIC_URL);
});

Deno.test("gateway no longer serves HTML directly from Supabase Edge", async () => {
  const response = routeCustomerPushLink(new Request(`${publicBase}?token=${token}`));
  assertEquals(response.headers.get("content-type")?.includes("text/html") ?? false, false);
  assertEquals(await response.text(), "");
});


Deno.test("install manifest carries the fragment token back to the immutable portal", async () => {
  const response = manifestResponse(
    new Request(
      `https://hsoyfbtpvwfmjokudznx.supabase.co/functions/v1/customer-push-manifest?token=${token}`,
    ),
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.scope, new URL("./", CUSTOMER_PUSH_STATIC_URL).href);
  assertEquals(body.start_url, `${CUSTOMER_PUSH_STATIC_URL}#token=${token}`);
});
